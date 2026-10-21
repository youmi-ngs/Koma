import SwiftData
import SwiftUI

/// 学期の追加・編集。
struct SemesterEditView: View {
    enum Mode {
        case create
        case edit(Semester)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Semester.startDate, order: .reverse) private var semesters: [Semester]

    private let mode: Mode
    @State private var name: String
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var showsSaturday: Bool
    @State private var showsSunday: Bool
    @State private var makeCurrent: Bool

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .create:
            let range = Semester.suggestedRange()
            _name = State(initialValue: Semester.suggestedName())
            _startDate = State(initialValue: range.start)
            _endDate = State(initialValue: range.end)
            _showsSaturday = State(initialValue: true)
            _showsSunday = State(initialValue: false)
            _makeCurrent = State(initialValue: true)
        case let .edit(semester):
            _name = State(initialValue: semester.name)
            _startDate = State(initialValue: semester.startDate)
            _endDate = State(initialValue: semester.endDate)
            _showsSaturday = State(initialValue: semester.showsSaturday)
            _showsSunday = State(initialValue: semester.showsSunday)
            _makeCurrent = State(initialValue: semester.isCurrent)
        }
    }

    private var isNew: Bool {
        if case .create = mode { return true }
        return false
    }

    private var editingSemester: Semester? {
        if case let .edit(semester) = mode { return semester }
        return nil
    }

    /// 期間が何週あるか。端数は切り上げる。
    private var weekCount: Int {
        let calendar = Calendar.current
        let days = calendar.dateComponents(
            [.day],
            from: calendar.startOfDay(for: startDate),
            to: calendar.startOfDay(for: endDate)
        ).day ?? 0
        return max(1, Int((Double(days + 1) / 7).rounded(.up)))
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && startDate <= endDate
    }

    var body: some View {
        Group {
            if isNew {
                NavigationStack { form }
            } else {
                form
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Semester name (e.g. Fall 2026)", text: $name)
            } header: {
                Text("Semester")
            }

            Section {
                DatePicker("Starts", selection: $startDate, displayedComponents: .date)
                DatePicker("Ends", selection: $endDate, in: startDate..., displayedComponents: .date)
            } header: {
                Text("Dates")
            } footer: {
                // 期間がずれていると授業回数が合わなくなり、出席率の見込みまで狂う。
                Text("\(weekCount) weeks, so a weekly slot holds \(weekCount) classes. Reminders are created only for class days inside this range.")
            }

            Section("Days Shown") {
                Toggle("Saturday", isOn: $showsSaturday)
                Toggle("Sunday", isOn: $showsSunday)
            }

            Section {
                Toggle("Show This Semester", isOn: $makeCurrent)
            } footer: {
                Text("Turning this on switches the Timetable tab to this semester.")
            }

            if let semester = editingSemester {
                Section {
                    NavigationLink {
                        PeriodEditView(semester: semester)
                    } label: {
                        LabeledContent("Period Times") {
                            Text("\(semester.periods.count) periods")
                        }
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Add Semester" : "Edit Semester")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { save() }
                        .disabled(!isValid)
                }
            } else {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        switch mode {
        case .create:
            let semester = Semester(
                name: trimmed,
                startDate: startDate,
                endDate: endDate,
                showsSaturday: showsSaturday,
                showsSunday: showsSunday
            )
            context.insert(semester)
            if makeCurrent {
                SemesterPicker.makeCurrent(semester, among: semesters + [semester])
            }
        case let .edit(semester):
            semester.name = trimmed
            semester.startDate = startDate
            semester.endDate = endDate
            semester.showsSaturday = showsSaturday
            semester.showsSunday = showsSunday
            if makeCurrent {
                SemesterPicker.makeCurrent(semester, among: semesters)
            } else if semesters.count > 1 {
                semester.isCurrent = false
            }
        }

        try? context.save()
        dismiss()
        Task { await TaskSyncCoordinator.shared.sync(context: context) }
    }
}
