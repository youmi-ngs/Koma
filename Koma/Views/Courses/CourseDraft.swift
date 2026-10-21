import Foundation
import SwiftData

/// 編集中のコマ。保存するまでデータベースには触らない。
struct MeetingDraft: Identifiable, Hashable {
    var id = UUID()
    var weekday: Int = 2
    var period: Int = 1
    var roomOverride: String = ""
}

/// 授業の編集内容。キャンセルで元に戻せるよう、一度値型に写してから保存する。
struct CourseDraft {
    var name: String = ""
    var teacher: String = ""
    var room: String = ""
    var items: String = ""
    var attendanceChannels: Set<AttendanceChannel> = [.digiCan]
    var attendanceDetail: String = ""
    var attendanceWindowMinutes: Int = 5
    var attendanceLeadMinutes: Int = 0
    var attendanceReminderEnabled: Bool = true
    var attendanceThresholdPercent: Int = 70
    var attendancePrompt: String = ""
    var colorIndex: Int = 0
    var note: String = ""
    var meetings: [MeetingDraft] = []

    var fsEnabled: Bool = true
    var fsTime: Date = TimeText.date(hour: 19, minute: 0)
    var fsPrompt: String = "Did you write your FS?"

    var assignmentEnabled: Bool = false
    var assignmentDeadlineMode: AssignmentDeadlineMode = .daysAfterClass
    var assignmentDueDays: Int = 6
    var assignmentDueTime: Date = TimeText.date(hour: 23, minute: 59)
    var assignmentReminderDaysBefore: Int = 1
    var assignmentReminderTime: Date = TimeText.date(hour: 19, minute: 0)
    var assignmentPrompt: String = "Have you finished the assignment?"
    var assignmentNote: String = ""

    var finalEnabled: Bool = false
    var finalTitle: String = TaskKind.finalAssignment.defaultLabel
    var finalDueDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
    var finalReminderDaysBefore: Int = 7
    var finalReminderTime: Date = TimeText.date(hour: 19, minute: 0)
    var finalNote: String = ""

    init() {}

    init(course: Course) {
        name = course.name
        teacher = course.teacher
        room = course.room
        items = course.items
        attendanceChannels = Set(course.attendanceChannels)
        attendanceDetail = course.attendanceDetail
        attendanceWindowMinutes = course.attendanceWindowMinutes
        attendanceLeadMinutes = course.attendanceLeadMinutes
        attendanceReminderEnabled = course.attendanceReminderEnabled
        attendanceThresholdPercent = course.attendanceThresholdPercent
        attendancePrompt = course.attendancePrompt
        colorIndex = course.colorIndex
        note = course.note
        meetings = course.sortedMeetings.map {
            MeetingDraft(weekday: $0.weekday, period: $0.period, roomOverride: $0.roomOverride)
        }

        fsEnabled = course.fsEnabled
        fsTime = TimeText.date(hour: course.fsReminderHour, minute: course.fsReminderMinute)
        fsPrompt = course.fsPrompt

        assignmentEnabled = course.assignmentEnabled
        assignmentDeadlineMode = course.assignmentDeadlineMode
        assignmentDueDays = course.assignmentDueDays
        assignmentDueTime = TimeText.date(
            hour: course.assignmentDueHour,
            minute: course.assignmentDueMinute
        )
        assignmentReminderDaysBefore = course.assignmentReminderDaysBefore
        assignmentReminderTime = TimeText.date(
            hour: course.assignmentReminderHour,
            minute: course.assignmentReminderMinute
        )
        assignmentPrompt = course.assignmentPrompt
        assignmentNote = course.assignmentNote

        finalEnabled = course.finalEnabled
        finalTitle = course.finalTitle
        finalDueDate = course.finalDueDate
        finalReminderDaysBefore = course.finalReminderDaysBefore
        finalReminderTime = TimeText.date(
            hour: course.finalReminderHour,
            minute: course.finalReminderMinute
        )
        finalNote = course.finalNote
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var onlineAttendanceChannels: [AttendanceChannel] {
        attendanceChannels.filter(\.isOnline).sorted { $0.sortOrder < $1.sortOrder }
    }

    var usesOnlineAttendance: Bool { !onlineAttendanceChannels.isEmpty }

    /// 未入力のときに使われる通知文。TextField のプレースホルダにも出す。
    var autoAttendancePrompt: String { "Did you check in?" }

    /// 入力内容を授業に書き戻す。コマは作り直す（やることは授業に紐づくので失われない）。
    @MainActor
    func apply(to course: Course, in context: ModelContext) {
        course.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        course.teacher = teacher.trimmingCharacters(in: .whitespaces)
        course.room = room.trimmingCharacters(in: .whitespaces)
        course.items = items
        course.attendanceChannels = Array(attendanceChannels)
        course.attendanceDetail = attendanceDetail
        course.attendanceWindowMinutes = max(1, attendanceWindowMinutes)
        course.attendanceLeadMinutes = max(0, attendanceLeadMinutes)
        course.attendanceReminderEnabled = attendanceReminderEnabled
        course.attendanceThresholdPercent = attendanceThresholdPercent
        course.attendancePrompt = attendancePrompt
        course.colorIndex = colorIndex
        course.note = note

        course.fsEnabled = fsEnabled
        let fs = TimeText.components(from: fsTime)
        course.fsReminderHour = fs.hour
        course.fsReminderMinute = fs.minute
        course.fsPrompt = fsPrompt

        course.assignmentEnabled = assignmentEnabled
        course.assignmentDeadlineMode = assignmentDeadlineMode
        course.assignmentDueDays = max(0, assignmentDueDays)
        let assignmentDue = TimeText.components(from: assignmentDueTime)
        course.assignmentDueHour = assignmentDue.hour
        course.assignmentDueMinute = assignmentDue.minute
        course.assignmentReminderDaysBefore = max(0, assignmentReminderDaysBefore)
        let assignmentReminder = TimeText.components(from: assignmentReminderTime)
        course.assignmentReminderHour = assignmentReminder.hour
        course.assignmentReminderMinute = assignmentReminder.minute
        course.assignmentPrompt = assignmentPrompt
        course.assignmentNote = assignmentNote

        course.finalEnabled = finalEnabled
        course.finalTitle = finalTitle
        course.finalDueDate = finalDueDate
        course.finalReminderDaysBefore = max(0, finalReminderDaysBefore)
        let final = TimeText.components(from: finalReminderTime)
        course.finalReminderHour = final.hour
        course.finalReminderMinute = final.minute
        course.finalNote = finalNote

        for existing in course.meetings {
            context.delete(existing)
        }
        course.meetings = []

        for draft in meetings {
            let meeting = Meeting(
                weekday: draft.weekday,
                period: draft.period,
                roomOverride: draft.roomOverride.trimmingCharacters(in: .whitespaces)
            )
            meeting.course = course
            context.insert(meeting)
        }
    }
}
