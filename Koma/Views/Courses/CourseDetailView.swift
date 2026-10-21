import SwiftData
import SwiftUI

/// 授業1件の詳細。情報の確認と、FS／課題のリマインド設定の見直しができる。
struct CourseDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var course: Course

    @State private var isEditing = false
    @State private var isConfirmingDelete = false
    @State private var examBeingEdited: Exam?
    @State private var isAddingExam = false
    @State private var isSplitting = false
    @State private var isMerging = false
    @State private var makeupBeingEdited: MakeupClass?
    @State private var makeupRequest: MakeupRequest?

    private var upcomingTasks: [TaskItem] {
        course.tasks
            .filter { !$0.isDone }
            .sorted { $0.dueDate < $1.dueDate }
            .prefix(6)
            .map { $0 }
    }

    var body: some View {
        List {
            headerSection
            scheduleSection
            attendanceSection
            if !course.itemList.isEmpty { itemsSection }
            reminderSummarySection
            makeupsSection
            examsSection
            if !upcomingTasks.isEmpty { upcomingSection }
            if !course.note.isEmpty { noteSection }
            deleteSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(course.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { isEditing = true }
            }
        }
        .sheet(isPresented: $isEditing) {
            CourseEditView(mode: .edit(course))
        }
        .sheet(isPresented: $isSplitting) {
            CourseSplitView(course: course)
        }
        .sheet(isPresented: $isMerging) {
            CourseMergeView(course: course)
        }
        .sheet(item: $makeupRequest) { request in
            MakeupClassEditView(mode: .create(course: course, replacing: request.replacing))
        }
        .sheet(item: $makeupBeingEdited) { makeup in
            MakeupClassEditView(mode: .edit(makeup))
        }
        .sheet(isPresented: $isAddingExam) {
            ExamEditView(mode: .create(course: course))
        }
        .sheet(item: $examBeingEdited) { exam in
            ExamEditView(mode: .edit(exam))
        }
        .confirmationDialog(
            "Delete “\(course.displayName)”?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its to-dos and reminders will be deleted too.")
        }
    }

    // MARK: - セクション

    private var headerSection: some View {
        Section {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(course.color.opacity(0.22))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: "book.closed")
                            .font(.title3)
                            .foregroundStyle(course.color)
                    }

                VStack(alignment: .leading, spacing: 4) {
                    Text(course.displayName)
                        .font(.headline)
                    Text(course.scheduleSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private var scheduleSection: some View {
        Section("Time & Room") {
            if course.meetings.isEmpty {
                Text("No slots set")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(course.sortedMeetings) { meeting in
                    let slot = course.semester?.period(at: meeting.period)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(meeting.slotText)
                                .font(.body.weight(.medium))
                            Spacer()
                            if let slot {
                                Text(slot.rangeText)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        let room = course.room(for: meeting)
                        if !room.isEmpty {
                            Label(room, systemImage: "mappin.and.ellipse")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            if !course.teacher.isEmpty {
                LabeledContent {
                    Text(course.teacher)
                } label: {
                    Label("Instructor", systemImage: "person")
                }
            }

            if course.meetings.count > 1 {
                Button {
                    isSplitting = true
                } label: {
                    Label("Split into another course", systemImage: "square.split.2x1")
                }
            }

            if (course.semester?.courses.count ?? 0) > 1 {
                Button {
                    isMerging = true
                } label: {
                    Label("Merge another course into this", systemImage: "square.on.square")
                }
            }

            NavigationLink {
                ClassCancellationView(course: course)
            } label: {
                LabeledContent {
                    Text(course.cancellationSummary())
                        .foregroundStyle(course.cancelledDays.isEmpty ? .secondary : Color.orange)
                } label: {
                    Label("Cancelled classes", systemImage: "calendar.badge.minus")
                }
            }
        }
    }

    private var attendanceSection: some View {
        Section {
            if course.attendanceChannels.isEmpty {
                Text("Not set")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(course.attendanceChannels) { channel in
                    Label(channel.title, systemImage: channel.symbolName)
                }
            }

            if course.usesOnlineAttendance {
                LabeledContent {
                    Text("\(max(1, course.attendanceWindowMinutes)) min from start")
                        .monospacedDigit()
                } label: {
                    Label("Check-in window", systemImage: "clock.badge.checkmark")
                }
            }

            NavigationLink {
                AttendanceRecordView(course: course)
            } label: {
                let tally = course.attendanceTally()
                LabeledContent {
                    Text(tally.absent > 0 ? "\(tally.present) present · \(tally.absent) absent" : "\(tally.present) present")
                        .foregroundStyle(tally.absent > 0 ? Color.red : .secondary)
                } label: {
                    Label("Record", systemImage: "list.bullet.rectangle")
                }
            }

            if !course.attendanceDetail.isEmpty {
                Text(course.attendanceDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Attendance")
        } footer: {
            if course.usesOnlineAttendance {
                Text("Check in on the site within the window, or the class counts as missed.")
            }
        }
    }

    private var itemsSection: some View {
        Section("What to Bring") {
            ForEach(course.itemList, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle")
                    .labelStyle(.titleAndIcon)
            }
        }
    }

    private var reminderSummarySection: some View {
        Section {
            if course.enabledReminderKinds.isEmpty {
                Text("No reminders set")
                    .foregroundStyle(.secondary)
            }

            if course.isEnabled(.attendance) {
                reminderRow(
                    title: TaskKind.attendance.defaultLabel,
                    symbol: TaskKind.attendance.symbolName,
                    value: ReminderText.minuteOffset(course.attendanceLeadMinutes),
                    detail: "Check-in window \(max(1, course.attendanceWindowMinutes)) min from start"
                )
            }

            if course.fsEnabled {
                reminderRow(
                    title: TaskKind.feedbackSheet.defaultLabel,
                    symbol: TaskKind.feedbackSheet.symbolName,
                    value: "Due \(ReminderText.offset(Course.fsDelayDays).lowercased()), \(TimeText.string(hour: Course.fsDeadlineHour, minute: Course.fsDeadlineMinute))",
                    detail: "Reminder on the due date at \(TimeText.string(hour: course.fsReminderHour, minute: course.fsReminderMinute))"
                )
            }

            if course.assignmentEnabled {
                reminderRow(
                    title: TaskKind.assignment.defaultLabel,
                    symbol: TaskKind.assignment.symbolName,
                    value: assignmentDeadlineText,
                    detail: "Reminder \(ReminderText.before(course.assignmentReminderDaysBefore).lowercased()) at \(TimeText.string(hour: course.assignmentReminderHour, minute: course.assignmentReminderMinute))"
                )
                if !course.assignmentNote.isEmpty {
                    Text(course.assignmentNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            if course.finalEnabled {
                reminderRow(
                    title: course.label(for: .finalAssignment),
                    symbol: TaskKind.finalAssignment.symbolName,
                    value: course.finalDueDate.formatted(.dateTime.month(.abbreviated).day().hour().minute()),
                    detail: "Reminder \(ReminderText.before(course.finalReminderDaysBefore).lowercased()) at \(TimeText.string(hour: course.finalReminderHour, minute: course.finalReminderMinute))"
                )
                if !course.finalNote.isEmpty {
                    Text(course.finalNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Tap Edit to change the deadline and the reminder separately.")
        }
    }

    private var assignmentDeadlineText: String {
        switch course.assignmentDeadlineMode {
        case .daysAfterClass:
            return "Due \(ReminderText.offset(course.assignmentDueDays).lowercased()), \(TimeText.string(hour: course.assignmentDueHour, minute: course.assignmentDueMinute))"
        case .beforeNextClass:
            return "Before next class"
        }
    }

    private func reminderRow(title: String, symbol: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent {
                Text(value).monospacedDigit()
            } label: {
                Label(title, systemImage: symbol)
            }
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var makeupsSection: some View {
        Section {
            ForEach(course.sortedMakeups) { makeup in
                Button {
                    makeupBeingEdited = makeup
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(makeup.slotText)
                                .foregroundStyle(.primary)
                            Spacer()
                            if let replaces = makeup.replacesDay {
                                Text("for \(replaces.formatted(.dateTime.month(.abbreviated).day()))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !makeup.roomOverride.isEmpty {
                            Label(makeup.roomOverride, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                makeupRequest = MakeupRequest(replacing: nil)
            } label: {
                Label("Add make-up class", systemImage: "plus.circle.fill")
            }
        } header: {
            Label("Make-up classes", systemImage: "calendar.badge.plus")
        } footer: {
            Text("An extra class on a one-off date, for when a cancelled one is rescheduled. It gets its own attendance, FS, and assignment.")
        }
    }

    private var examsSection: some View {
        Section {
            ForEach(course.sortedExams) { exam in
                Button {
                    examBeingEdited = exam
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(exam.displayTitle)
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(exam.dateText)
                                .font(.subheadline)
                                .foregroundStyle(exam.date < .now ? .secondary : Color.accentColor)
                        }
                        if !exam.room.isEmpty {
                            Label(exam.room, systemImage: "mappin.and.ellipse")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if !exam.note.isEmpty {
                            Text(exam.note)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Button {
                isAddingExam = true
            } label: {
                Label("Add Exam", systemImage: "plus.circle.fill")
            }
        } header: {
            Label("Exams", systemImage: TaskKind.exam.symbolName)
        } footer: {
            Text("Two reminders are sent before each exam. They also show up under To-Do.")
        }
    }

    private var upcomingSection: some View {
        Section("Coming Up") {
            ForEach(upcomingTasks) { task in
                TaskRow(task: task, showsCourseName: false) {
                    toggle(task)
                }
            }
        }
    }

    private var noteSection: some View {
        Section("Notes") {
            Text(course.note)
        }
    }

    private var deleteSection: some View {
        Section {
            Button("Delete Course", role: .destructive) {
                isConfirmingDelete = true
            }
        }
    }

    // MARK: - 操作

    private func toggle(_ task: TaskItem) {
        task.markDone(!task.isDone)
        try? context.save()
        Task { await TaskSyncCoordinator.shared.refreshNotifications(context: context) }
    }

    private func delete() {
        context.delete(course)
        try? context.save()
        dismiss()
        Task { await TaskSyncCoordinator.shared.refreshNotifications(context: context) }
    }
}
