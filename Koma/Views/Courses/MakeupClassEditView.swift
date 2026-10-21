import SwiftData
import SwiftUI

/// 振替の追加・編集。休講になった回の代わりに、別の日へ1回ぶん足す。
struct MakeupClassEditView: View {
    enum Mode {
        case create(course: Course, replacing: Date?)
        case edit(MakeupClass)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode
    @State private var date: Date
    @State private var period: Int
    @State private var roomOverride: String
    @State private var note: String

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case let .create(course, _):
            let calendar = Calendar.current
            _date = State(initialValue: calendar.date(byAdding: .day, value: 7, to: .now) ?? .now)
            _period = State(initialValue: course.sortedMeetings.first?.period ?? 1)
            _roomOverride = State(initialValue: "")
            _note = State(initialValue: "")
        case let .edit(makeup):
            _date = State(initialValue: makeup.date)
            _period = State(initialValue: makeup.period)
            _roomOverride = State(initialValue: makeup.roomOverride)
            _note = State(initialValue: makeup.note)
        }
    }

    private var isNew: Bool {
        if case .create = mode { return true }
        return false
    }

    private var course: Course? {
        switch mode {
        case let .create(course, _): return course
        case let .edit(makeup): return makeup.course
        }
    }

    private var replacing: Date? {
        switch mode {
        case let .create(_, replacing): return replacing
        case let .edit(makeup): return makeup.replacesDay
        }
    }

    private var availablePeriods: [Int] {
        let periods = course?.semester?.sortedPeriods.map(\.index) ?? Array(1...6)
        return periods.isEmpty ? Array(1...6) : periods
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Period", selection: $period) {
                        ForEach(availablePeriods, id: \.self) { value in
                            Text("Period \(value)").tag(value)
                        }
                    }
                    TextField("Room (if different)", text: $roomOverride)
                } header: {
                    Text("Make-up class")
                } footer: {
                    if let replacing {
                        Text("Stands in for the cancelled class on \(replacing.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))). Attendance, FS, and the assignment are created for this date instead.")
                    } else {
                        Text("One extra class on this date. Attendance, FS, and the assignment are created for it, the same as a normal class.")
                    }
                }

                Section("Notes") {
                    TextField("Anything to remember", text: $note, axis: .vertical)
                        .lineLimit(1...4)
                }

                if case let .edit(makeup) = mode {
                    Section {
                        Button("Delete Make-up", role: .destructive) { delete(makeup) }
                    }
                }
            }
            .navigationTitle(isNew ? "Add make-up" : "Edit make-up")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") { save() }
                }
            }
        }
    }

    private func save() {
        switch mode {
        case let .create(course, replacing):
            let makeup = MakeupClass(date: date, period: period, course: course, replacesDay: replacing)
            makeup.roomOverride = roomOverride.trimmingCharacters(in: .whitespaces)
            makeup.note = note
            context.insert(makeup)
        case let .edit(makeup):
            makeup.date = Calendar.current.startOfDay(for: date)
            makeup.period = period
            makeup.roomOverride = roomOverride.trimmingCharacters(in: .whitespaces)
            makeup.note = note
        }

        try? context.save()
        dismiss()
        Task { await TaskSyncCoordinator.shared.sync(context: context) }
    }

    private func delete(_ makeup: MakeupClass) {
        context.delete(makeup)
        try? context.save()
        dismiss()
        Task { await TaskSyncCoordinator.shared.sync(context: context) }
    }
}
