import Foundation
import SwiftData

/// 学期を丸ごと複製する。履修が前期と似ている学期を一から入れ直さずに済むようにする。
enum SemesterDuplicator {
    /// 授業とコマだけを引き継ぐ。やること・休講・試験はその学期固有なので持っていかない。
    @MainActor
    @discardableResult
    static func duplicate(_ source: Semester, in context: ModelContext) -> Semester {
        let copy = Semester(
            name: nextName(for: source.name),
            startDate: source.startDate,
            endDate: source.endDate,
            periods: source.periods,
            showsSaturday: source.showsSaturday,
            showsSunday: source.showsSunday
        )
        context.insert(copy)

        for course in source.courses {
            let newCourse = Course(
                name: course.name,
                teacher: course.teacher,
                room: course.room,
                colorIndex: course.colorIndex,
                semester: copy
            )
            newCourse.items = course.items
            newCourse.note = course.note

            newCourse.attendanceChannelsRaw = course.attendanceChannelsRaw
            newCourse.attendanceDetail = course.attendanceDetail
            newCourse.attendanceWindowMinutes = course.attendanceWindowMinutes
            newCourse.attendanceLeadMinutes = course.attendanceLeadMinutes
            newCourse.attendanceReminderEnabled = course.attendanceReminderEnabled
            newCourse.attendancePrompt = course.attendancePrompt

            newCourse.fsEnabled = course.fsEnabled
            newCourse.fsReminderHour = course.fsReminderHour
            newCourse.fsReminderMinute = course.fsReminderMinute
            newCourse.fsPrompt = course.fsPrompt

            newCourse.assignmentEnabled = course.assignmentEnabled
            newCourse.assignmentDeadlineModeRaw = course.assignmentDeadlineModeRaw
            newCourse.assignmentDueDays = course.assignmentDueDays
            newCourse.assignmentDueHour = course.assignmentDueHour
            newCourse.assignmentDueMinute = course.assignmentDueMinute
            newCourse.assignmentReminderDaysBefore = course.assignmentReminderDaysBefore
            newCourse.assignmentReminderHour = course.assignmentReminderHour
            newCourse.assignmentReminderMinute = course.assignmentReminderMinute
            newCourse.assignmentPrompt = course.assignmentPrompt
            newCourse.assignmentNote = course.assignmentNote

            // 最終課題は設定だけ引き継ぎ、締め切りは新しい学期の終わりに置き直す。
            newCourse.finalEnabled = course.finalEnabled
            newCourse.finalTitle = course.finalTitle
            newCourse.finalDueDate = copy.endDate
            newCourse.finalReminderDaysBefore = course.finalReminderDaysBefore
            newCourse.finalReminderHour = course.finalReminderHour
            newCourse.finalReminderMinute = course.finalReminderMinute
            newCourse.finalNote = course.finalNote

            context.insert(newCourse)

            for meeting in course.meetings {
                let newMeeting = Meeting(
                    weekday: meeting.weekday,
                    period: meeting.period,
                    roomOverride: meeting.roomOverride
                )
                newMeeting.course = newCourse
                context.insert(newMeeting)
            }
        }

        try? context.save()
        return copy
    }

    /// 「2026 3Q」→「2026 3Q 2」のように、末尾の数字を足して区別する。
    private static func nextName(for name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "Copy" }
        return "\(trimmed) copy"
    }
}
