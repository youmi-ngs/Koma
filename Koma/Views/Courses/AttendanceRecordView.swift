import SwiftData
import SwiftUI

/// 授業ごとの出席記録。出た回・休んだ回を数えて、あとから直せるようにする。
struct AttendanceRecordView: View {
    @Environment(\.modelContext) private var context
    @Bindable var course: Course

    private var calendar: Calendar { .current }

    /// すでに終わった回を新しい順に。これから先の回は記録しようがないので出さない。
    private var past: [TaskItem] {
        course.tasks
            .filter { $0.kind == .attendance && $0.classDate <= .now }
            .sorted {
                $0.classDate == $1.classDate ? $0.period < $1.period : $0.classDate > $1.classDate
            }
    }

    private var upcoming: [TaskItem] {
        course.tasks
            .filter { $0.kind == .attendance && $0.classDate > .now }
            .sorted { $0.classDate < $1.classDate }
    }

    var body: some View {
        Group {
            if past.isEmpty && upcoming.isEmpty {
                ContentUnavailableView {
                    Label("No Classes Yet", systemImage: "person.crop.circle.badge.checkmark")
                } description: {
                    Text("Once this course has had a class, its attendance shows up here.")
                }
            } else {
                list
            }
        }
        .navigationTitle("Attendance")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var list: some View {
        List {
            Section {
                let tally = course.attendanceTally()
                LabeledContent("Present") { Text("\(tally.present)").monospacedDigit() }
                LabeledContent("Absent") {
                    Text("\(tally.absent)")
                        .monospacedDigit()
                        .foregroundStyle(tally.absent > 0 ? Color.red : .secondary)
                }
                if tally.unrecorded > 0 {
                    LabeledContent("Not recorded") {
                        Text("\(tally.unrecorded)").monospacedDigit()
                    }
                }
            } header: {
                Text("So far")
            } footer: {
                Text("Counts the classes that have already happened, one per period.")
            }

            if !past.isEmpty {
                Section("Past classes") {
                    ForEach(past) { task in
                        row(task)
                    }
                }
            }

            if !upcoming.isEmpty {
                Section("Coming up") {
                    ForEach(upcoming.prefix(10)) { task in
                        HStack {
                            Text(label(for: task))
                            Spacer()
                            Text("—").foregroundStyle(.tertiary)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ task: TaskItem) -> some View {
        HStack {
            Text(label(for: task))
            Spacer()
            Picker("", selection: binding(for: task)) {
                Text("—").tag(AttendanceOutcome?.none)
                ForEach(AttendanceOutcome.allCases) { outcome in
                    Text(outcome.title).tag(AttendanceOutcome?.some(outcome))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(task.attendanceOutcome == .absent ? .red : .accentColor)
        }
    }

    private func label(for task: TaskItem) -> String {
        let date = task.classDate.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
        return task.period > 0 ? "\(date) · P\(task.period)" : date
    }

    private func binding(for task: TaskItem) -> Binding<AttendanceOutcome?> {
        Binding(
            get: { task.attendanceOutcome },
            set: { outcome in
                if let outcome {
                    task.record(outcome)
                } else {
                    task.markDone(false)
                }
                try? context.save()
                Task { await TaskSyncCoordinator.shared.refreshNotifications(context: context) }
            }
        )
    }
}
