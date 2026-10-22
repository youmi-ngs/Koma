import Foundation

/// 授業が行われる日の計算。時間割の生成と休講の編集で共通に使う。
enum ClassDays {
    /// 指定した曜日にあたる日付を期間内で列挙する。
    static func occurrences(
        weekday: Int,
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let startWeekday = calendar.component(.weekday, from: start)
        let offset = ((weekday - startWeekday) + 7) % 7
        guard var day = calendar.date(byAdding: .day, value: offset, to: start) else { return [] }

        var days: [Date] = []
        while day <= end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 7, to: day) else { break }
            day = next
        }
        return days
    }

    /// 授業の1コマ。試験を「どの回か」で選ぶときに使う。
    struct Session: Identifiable, Hashable {
        var id: String
        var start: Date
        var period: Int
        var title: String
    }

    /// 休講を除いた、これからの授業のコマを時系列で返す。
    @MainActor
    static func upcomingSessions(
        for course: Course,
        from start: Date = .now,
        calendar: Calendar = .current
    ) -> [Session] {
        guard let semester = course.semester else { return [] }
        let rangeStart = max(calendar.startOfDay(for: semester.startDate), calendar.startOfDay(for: start))
        let rangeEnd = calendar.startOfDay(for: semester.endDate)
        guard rangeStart <= rangeEnd else { return [] }

        var sessions: [Session] = []
        for meeting in course.meetings {
            let slot = semester.period(at: meeting.period)
            for day in occurrences(weekday: meeting.weekday, from: rangeStart, to: rangeEnd, calendar: calendar) {
                guard !semester.isBreak(day, calendar: calendar) else { continue }
                guard !course.isCancelled(on: day, calendar: calendar) else { continue }
                guard let begin = calendar.date(
                    bySettingHour: slot?.startHour ?? 9,
                    minute: slot?.startMinute ?? 0,
                    second: 0,
                    of: day
                ) else { continue }

                let label = day.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
                let time = TimeText.string(hour: slot?.startHour ?? 9, minute: slot?.startMinute ?? 0)
                sessions.append(Session(
                    id: "\(calendar.startOfDay(for: day).timeIntervalSince1970)-\(meeting.period)",
                    start: begin,
                    period: meeting.period,
                    title: "\(label) · P\(meeting.period) \(time)"
                ))
            }
        }
        return sessions.sorted { $0.start < $1.start }
    }

    /// 授業が行われる1回ぶん。時間割のコマと、振替で足した回の両方を指す。
    struct Occurrence: Hashable {
        var day: Date
        var period: Int
        var start: Date
    }

    /// その授業が実際に行われる回を並べる。休講は除き、振替は足す。
    @MainActor
    static func classOccurrences(
        for course: Course,
        in semester: Semester,
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [Occurrence] {
        var result: [Occurrence] = []

        func add(day: Date, period: Int) {
            let day = calendar.startOfDay(for: day)
            guard day >= start, day <= end else { return }
            guard !semester.isBreak(day, calendar: calendar) else { return }
            guard !course.isCancelled(on: day, calendar: calendar) else { return }
            let slot = semester.period(at: period)
            guard let begin = calendar.date(
                bySettingHour: slot?.startHour ?? 9,
                minute: slot?.startMinute ?? 0,
                second: 0,
                of: day
            ) else { return }
            result.append(Occurrence(day: day, period: period, start: begin))
        }

        for meeting in course.meetings {
            for day in occurrences(weekday: meeting.weekday, from: start, to: end, calendar: calendar) {
                add(day: day, period: meeting.period)
            }
        }
        // 振替は休講になった回の代わりなので、同じように1回ぶんの授業として扱う。
        for makeup in course.makeups {
            add(day: makeup.date, period: makeup.period)
        }

        return Array(Set(result)).sorted { $0.start < $1.start }
    }

    /// その授業がある日（休講を含む）を重複なく時系列で返す。学期の休みは除く。
    @MainActor
    static func allDays(
        for course: Course,
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> [Date] {
        let semester = course.semester
        var days: Set<Date> = []
        for meeting in course.meetings {
            for day in occurrences(weekday: meeting.weekday, from: start, to: end, calendar: calendar) {
                let day = calendar.startOfDay(for: day)
                if semester?.isBreak(day, calendar: calendar) == true { continue }
                days.insert(day)
            }
        }
        return days.sorted()
    }
}
