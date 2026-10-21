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
            newCourse.copySettings(from: course)
            // 最終課題の締め切りは新しい学期の終わりに置き直す。
            newCourse.finalDueDate = copy.endDate

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
