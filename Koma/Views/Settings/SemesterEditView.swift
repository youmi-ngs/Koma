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
    @State private var breaks: [TermBreak]
    @State private var breakBeingEdited: TermBreak?
    @State private var isAddingBreak = false

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
            _breaks = State(initialValue: [])
        case let .edit(semester):
            _name = State(initialValue: semester.name)
            _startDate = State(initialValue: semester.startDate)
            _endDate = State(initialValue: semester.endDate)
            _showsSaturday = State(initialValue: semester.showsSaturday)
            _showsSunday = State(initialValue: semester.showsSunday)
            _makeCurrent = State(initialValue: semester.isCurrent)
            _breaks = State(initialValue: semester.breaks)
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

    /// 曜日ごとに、その期間に授業が何回あるか。休みの期間は除く。
    /// 週数だけだと端数や休みが隠れて、出席率の母数がずれていても気づけない。
    private var classCountSummary: String {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { return "Set an end date after the start" }

        var weekdays = [2, 3, 4, 5, 6]
        if showsSaturday { weekdays.append(7) }
        if showsSunday { weekdays.insert(1, at: 0) }

        let counts = weekdays.map { weekday -> (String, Int) in
            let days = ClassDays.occurrences(weekday: weekday, from: start, to: end, calendar: calendar)
                .filter { day in !breaks.contains { $0.contains(day, calendar: calendar) } }
            return (WeekdayText.short(weekday), days.count)
        }

        if Set(counts.map(\.1)).count == 1, let value = counts.first?.1 {
            return "\(value) classes for every weekly slot"
        }
        return counts.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
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
                Text("\(classCountSummary). Reminders are created only for class days inside this range.")
            }

            Section {
                ForEach(breaks.sorted { $0.start < $1.start }) { item in
                    Button {
                        breakBeingEdited = item
                    } label: {
                        HStack {
                            Text(item.displayName).foregroundStyle(.primary)
                            Spacer()
                            Text(item.rangeText).foregroundStyle(.secondary)
                        }
                    }
                }

                Button {
                    isAddingBreak = true
                } label: {
                    Label("Add break", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Breaks")
            } footer: {
                Text("A stretch in the middle of the term with no classes, such as the winter break. It applies to every course, and the counts above leave it out.")
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
        .sheet(isPresented: $isAddingBreak) {
            TermBreakEditView(existing: nil) { newBreak in
                breaks.append(newBreak)
            }
        }
        .sheet(item: $breakBeingEdited) { item in
            TermBreakEditView(existing: item) { updated in
                if let index = breaks.firstIndex(where: { $0.id == updated.id }) {
                    breaks[index] = updated
                }
            } onDelete: {
                breaks.removeAll { $0.id == item.id }
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
                breaks: breaks,
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
            semester.breaks = breaks
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
