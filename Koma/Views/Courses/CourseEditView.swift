import SwiftData
import SwiftUI

/// 授業の追加・編集。フォームは「授業の情報」→「時間と教室」→「リマインダー」の順に並べている。
struct CourseEditView: View {
    enum Mode {
        case create(semester: Semester, slot: TimetableSlot?)
        case edit(Course)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let mode: Mode
    @State private var draft: CourseDraft
    @FocusState private var isNameFocused: Bool

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case let .create(_, slot):
            var draft = CourseDraft()
            if let slot {
                draft.meetings = [MeetingDraft(weekday: slot.weekday, period: slot.period)]
            } else {
                draft.meetings = [MeetingDraft()]
            }
            _draft = State(initialValue: draft)
        case let .edit(course):
            _draft = State(initialValue: CourseDraft(course: course))
        }
    }

    private var semester: Semester? {
        switch mode {
        case let .create(semester, _): return semester
        case let .edit(course): return course.semester
        }
    }

    private var isNew: Bool {
        if case .create = mode { return true }
        return false
    }

    private var availablePeriods: [Int] {
        let periods = semester?.sortedPeriods.map(\.index) ?? Array(1...6)
        return periods.isEmpty ? Array(1...6) : periods
    }

    var body: some View {
        NavigationStack {
            Form {
                basicsSection
                scheduleSection
                itemsSection
                attendanceSection
                fsSection
                assignmentSection
                finalSection
                noteSection
            }
            .navigationTitle(isNew ? "Add Course" : "Edit Course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!draft.isValid)
                }
            }
            .onAppear {
                if isNew { isNameFocused = true }
            }
        }
    }

    // MARK: - セクション

    private var basicsSection: some View {
        Section {
            TextField("Course name", text: $draft.name)
                .focused($isNameFocused)
            TextField("Instructor", text: $draft.teacher)
                .textContentType(.name)
            ColorChoiceRow(selection: $draft.colorIndex)
        } header: {
            Text("Course")
        } footer: {
            Text("The color is used for this course in the timetable.")
        }
    }

    private var scheduleSection: some View {
        Section {
            TextField("Room (e.g. Bldg 3, Rm 402)", text: $draft.room)

            ForEach($draft.meetings) { $meeting in
                MeetingEditRow(meeting: $meeting, availablePeriods: availablePeriods)
            }
            .onDelete { offsets in
                draft.meetings.remove(atOffsets: offsets)
            }

            Button {
                draft.meetings.append(nextMeetingDraft())
            } label: {
                Label("Add Slot", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Time & Room")
        } footer: {
            Text(scheduleFooter)
        }
    }

    private var scheduleFooter: String {
        if draft.meetings.isEmpty {
            return "Add at least one slot so the course appears in the timetable and gets reminders."
        }
        let times = semester?.sortedPeriods ?? []
        let descriptions = draft.meetings.compactMap { meeting -> String? in
            guard let slot = times.first(where: { $0.index == meeting.period }) else { return nil }
            return "\(WeekdayText.short(meeting.weekday)) \(slot.label), \(slot.rangeText)"
        }
        if descriptions.isEmpty {
            return "Period times can be changed per semester in Settings."
        }
        return descriptions.joined(separator: " · ") + ". Fill in a slot's own room if it differs."
    }

    private var itemsSection: some View {
        Section {
            TextField("Items to bring", text: $draft.items, axis: .vertical)
                .lineLimit(3...6)
        } header: {
            Text("What to Bring")
        } footer: {
            Text("Put one item per line to list them individually under Today.")
        }
    }

    private var attendanceSection: some View {
        Section {
            ForEach(AttendanceChannel.allCases) { channel in
                Toggle(isOn: channelBinding(channel)) {
                    Label(channel.title, systemImage: channel.symbolName)
                }
            }

            if draft.usesOnlineAttendance {
                Picker("Check-in window", selection: $draft.attendanceWindowMinutes) {
                    ForEach([3, 5, 10, 15, 20, 30], id: \.self) { minutes in
                        Text("\(minutes) min from start").tag(minutes)
                    }
                }

                Toggle("Attendance reminder", isOn: $draft.attendanceReminderEnabled)

                if draft.attendanceReminderEnabled {
                    Picker("Notify", selection: $draft.attendanceLeadMinutes) {
                        ForEach([0, 1, 2, 3, 5], id: \.self) { minutes in
                            Text(ReminderText.minuteOffset(minutes)).tag(minutes)
                        }
                    }

                    TextField(
                        draft.autoAttendancePrompt,
                        text: $draft.attendancePrompt,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                }
            }

            Picker("Credit needs over", selection: $draft.attendanceThresholdPercent) {
                ForEach([50, 60, 66, 70, 75, 80], id: \.self) { value in
                    Text("\(value)%").tag(value)
                }
            }

            TextField("Note (e.g. roll call in the second half)", text: $draft.attendanceDetail, axis: .vertical)
                .lineLimit(1...3)
        } header: {
            Text("Attendance")
        } footer: {
            Text(attendanceFooter)
        }
    }

    private var attendanceFooter: String {
        if draft.attendanceChannels.isEmpty {
            return "Choose how attendance is taken. A course can use a site and in-person roll call at the same time."
        }
        guard draft.usesOnlineAttendance else {
            return "The instructor records attendance, so no reminder is sent. Each class is still listed under Record, so absences and late arrivals can be kept there."
        }
        let sites = draft.onlineAttendanceChannels.map(\.shortTitle).formatted(.list(type: .and))
        let window = max(1, draft.attendanceWindowMinutes)
        guard draft.attendanceReminderEnabled else {
            return "You have \(window) minutes from the start of class to check in on \(sites). Turn the reminder on to get a notification."
        }
        return "You have \(window) minutes from the start of class to check in on \(sites). The reminder arrives \(ReminderText.atClassStart(draft.attendanceLeadMinutes)). Leave the message blank to use the suggested wording."
    }

    private func channelBinding(_ channel: AttendanceChannel) -> Binding<Bool> {
        Binding(
            get: { draft.attendanceChannels.contains(channel) },
            set: { isOn in
                if isOn {
                    draft.attendanceChannels.insert(channel)
                } else {
                    draft.attendanceChannels.remove(channel)
                }
            }
        )
    }

    private var fsSection: some View {
        Section {
            Toggle("FS reminder", isOn: $draft.fsEnabled)

            if draft.fsEnabled {
                DatePicker("Remind at", selection: $draft.fsTime, displayedComponents: .hourAndMinute)
                TextField("Notification message", text: $draft.fsPrompt, axis: .vertical)
                    .lineLimit(1...3)
            }
        } header: {
            Label(TaskKind.feedbackSheet.defaultLabel, systemImage: TaskKind.feedbackSheet.symbolName)
        } footer: {
            if draft.fsEnabled {
                let time = draft.fsTime.formatted(date: .omitted, time: .shortened)
                let deadline = TimeText.string(hour: Course.fsDeadlineHour, minute: Course.fsDeadlineMinute)
                Text("Writable from the class day. Due two days later at \(deadline) for every course. The reminder arrives on the due date at \(time).")
            } else {
                Text("While this is off, no FS to-dos are created for this course.")
            }
        }
    }

    private var assignmentSection: some View {
        Section {
            Toggle("Weekly assignment", isOn: $draft.assignmentEnabled)

            if draft.assignmentEnabled {
                Picker("Deadline", selection: $draft.assignmentDeadlineMode) {
                    ForEach(AssignmentDeadlineMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                if draft.assignmentDeadlineMode == .daysAfterClass {
                    Picker("Due", selection: $draft.assignmentDueDays) {
                        ForEach(0...14, id: \.self) { day in
                            Text(ReminderText.picker(day)).tag(day)
                        }
                    }
                    DatePicker("Due at", selection: $draft.assignmentDueTime, displayedComponents: .hourAndMinute)
                }

                Picker("Remind me", selection: $draft.assignmentReminderDaysBefore) {
                    ForEach([0, 1, 2, 3, 7], id: \.self) { days in
                        Text(ReminderText.before(days)).tag(days)
                    }
                }
                DatePicker("Reminder at", selection: $draft.assignmentReminderTime, displayedComponents: .hourAndMinute)

                TextField("Notification message", text: $draft.assignmentPrompt, axis: .vertical)
                    .lineLimit(1...3)
                TextField("Note (e.g. one-page report each week)", text: $draft.assignmentNote, axis: .vertical)
                    .lineLimit(1...3)
            }
        } header: {
            Label(TaskKind.assignment.defaultLabel, systemImage: TaskKind.assignment.symbolName)
        } footer: {
            Text(assignmentFooter)
        }
    }

    private var assignmentFooter: String {
        guard draft.assignmentEnabled else {
            return "Turn this on only for courses that give an assignment every week."
        }
        let due: String
        switch draft.assignmentDeadlineMode {
        case .daysAfterClass:
            due = "\(ReminderText.afterClass(draft.assignmentDueDays)) at \(draft.assignmentDueTime.formatted(date: .omitted, time: .shortened))"
        case .beforeNextClass:
            due = "when the next class starts"
        }
        let remind = "\(ReminderText.before(draft.assignmentReminderDaysBefore).lowercased()) at \(draft.assignmentReminderTime.formatted(date: .omitted, time: .shortened))"
        return "Due \(due). Reminder \(remind)."
    }

    private var finalSection: some View {
        Section {
            Toggle("Final project", isOn: $draft.finalEnabled)

            if draft.finalEnabled {
                TextField("Title", text: $draft.finalTitle)
                DatePicker("Due", selection: $draft.finalDueDate, displayedComponents: [.date, .hourAndMinute])
                Picker("Remind me", selection: $draft.finalReminderDaysBefore) {
                    ForEach([0, 1, 3, 7, 14], id: \.self) { days in
                        Text(ReminderText.before(days)).tag(days)
                    }
                }
                DatePicker("Reminder at", selection: $draft.finalReminderTime, displayedComponents: .hourAndMinute)
                TextField("Note (e.g. 10 pages, submit on the portal)", text: $draft.finalNote, axis: .vertical)
                    .lineLimit(1...3)
            }
        } header: {
            Label("Final project", systemImage: TaskKind.finalAssignment.symbolName)
        } footer: {
            Text(draft.finalEnabled
                 ? "Kept apart from the weekly assignments. Reminder \(ReminderText.before(draft.finalReminderDaysBefore).lowercased()) at \(draft.finalReminderTime.formatted(date: .omitted, time: .shortened))."
                 : "Turn this on for a single end-of-term submission.")
        }
    }

    private var noteSection: some View {
        Section("Notes") {
            TextField("Anything else to remember", text: $draft.note, axis: .vertical)
                .lineLimit(3...8)
        }
    }

    // MARK: - 補助

    private func nextMeetingDraft() -> MeetingDraft {
        if let last = draft.meetings.last {
            return MeetingDraft(weekday: last.weekday, period: last.period)
        }
        return MeetingDraft(weekday: 2, period: availablePeriods.first ?? 1)
    }

    private func save() {
        switch mode {
        case let .create(semester, _):
            let course = Course(semester: semester)
            context.insert(course)
            draft.apply(to: course, in: context)
            course.semester = semester
        case let .edit(course):
            draft.apply(to: course, in: context)
        }

        try? context.save()
        dismiss()

        Task {
            await NotificationManager.shared.requestAuthorizationIfNeeded()
            await TaskSyncCoordinator.shared.sync(context: context)
        }
    }
}

/// 曜日と限、コマ固有の教室を1行で編集する。
private struct MeetingEditRow: View {
    @Binding var meeting: MeetingDraft
    let availablePeriods: [Int]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Day", selection: $meeting.weekday) {
                    ForEach([2, 3, 4, 5, 6, 7, 1], id: \.self) { weekday in
                        Text(WeekdayText.full(weekday)).tag(weekday)
                    }
                }
                .pickerStyle(.menu)

                Picker("Period", selection: $meeting.period) {
                    ForEach(availablePeriods, id: \.self) { period in
                        Text("Period \(period)").tag(period)
                    }
                }
                .pickerStyle(.menu)
            }

            TextField("Room for this slot (optional)", text: $meeting.roomOverride)
                .font(.subheadline)
        }
    }
}

/// 時間割の色を選ぶ行。色の名前も読み上げられるようにしている。
private struct ColorChoiceRow: View {
    @Binding var selection: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Color")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(Array(CoursePalette.colors.enumerated()), id: \.offset) { index, color in
                        Button {
                            selection = index
                        } label: {
                            Circle()
                                .fill(color)
                                .frame(width: 30, height: 30)
                                .overlay {
                                    if selection == index {
                                        Image(systemName: "checkmark")
                                            .font(.caption.weight(.bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .overlay {
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(selection == index ? 0.4 : 0), lineWidth: 2)
                                        .padding(-3)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(CoursePalette.name(at: index))
                        .accessibilityAddTraits(selection == index ? [.isSelected, .isButton] : .isButton)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
