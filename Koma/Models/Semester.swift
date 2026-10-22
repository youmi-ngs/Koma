import Foundation
import SwiftData

/// 学期。時間割は学期ごとに丸ごと切り替わる。
@Model
final class Semester {
    var name: String = ""
    var startDate: Date = Date.now
    var endDate: Date = Date.now
    /// 時間割タブで表示している学期かどうか。アプリ全体で1つだけ true になる。
    var isCurrent: Bool = false
    /// この学期のコマの時間設定。
    var periods: [PeriodSlot] = PeriodSlot.standard
    /// 学期の途中に入る休み。冬休みのように全授業が止まる期間。
    var breaks: [TermBreak] = []
    var showsSaturday: Bool = true
    var showsSunday: Bool = false
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .cascade, inverse: \Course.semester)
    var courses: [Course] = []

    init(
        name: String,
        startDate: Date,
        endDate: Date,
        isCurrent: Bool = false,
        periods: [PeriodSlot] = PeriodSlot.standard,
        breaks: [TermBreak] = [],
        showsSaturday: Bool = true,
        showsSunday: Bool = false
    ) {
        self.name = name
        self.startDate = startDate
        self.endDate = endDate
        self.isCurrent = isCurrent
        self.periods = periods
        self.breaks = breaks
        self.showsSaturday = showsSaturday
        self.showsSunday = showsSunday
        self.createdAt = .now
    }

    /// 時間割に並べる曜日（日曜始まりの Calendar 準拠：1 = 日曜）。
    var visibleWeekdays: [Int] {
        var days: [Int] = []
        if showsSunday { days.append(1) }
        days.append(contentsOf: [2, 3, 4, 5, 6])
        if showsSaturday { days.append(7) }
        return days
    }

    var sortedPeriods: [PeriodSlot] {
        periods.sorted { $0.index < $1.index }
    }

    var dateRangeText: String {
        let start = startDate.formatted(.dateTime.year().month(.abbreviated).day())
        let end = endDate.formatted(.dateTime.year().month(.abbreviated).day())
        return "\(start) – \(end)"
    }

    /// 休みの期間に入っている日かどうか。
    func isBreak(_ day: Date, calendar: Calendar = .current) -> Bool {
        breaks.contains { $0.contains(day, calendar: calendar) }
    }

    func period(at index: Int) -> PeriodSlot? {
        periods.first { $0.index == index }
    }

    func contains(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: startDate)
            && day <= calendar.startOfDay(for: endDate)
    }

    /// 1学期は8週。1コマにつき8回で1単位という数え方に合わせる。
    static let weeksPerTerm = 8

    /// その日が属するクォーター。(年度, 1〜4)
    private static func quarter(for date: Date, calendar: Calendar = .current) -> (year: Int, number: Int) {
        let month = calendar.component(.month, from: date)
        let year = calendar.component(.year, from: date)
        switch month {
        case 4, 5: return (year, 1)
        case 6, 7, 8, 9: return (year, 2)
        case 10, 11: return (year, 3)
        case 12: return (year, 4)
        default: return (year - 1, 4)   // 1〜3月は前年度の4Q
        }
    }

    /// 「2026 3Q」のような既定の名前。
    static func suggestedName(for date: Date = .now) -> String {
        let term = quarter(for: date)
        return "\(term.year) \(term.number)Q"
    }

    /// クォーターの始まりから8週間。正確な日付は学校の暦に合わせて直す前提。
    static func suggestedRange(for date: Date = .now) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let term = quarter(for: date)
        let startMonth: Int
        switch term.number {
        case 1: startMonth = 4
        case 2: startMonth = 6
        case 3: startMonth = 10
        default: startMonth = 12
        }
        let startComponents = DateComponents(year: term.year, month: startMonth, day: 1)
        let start = calendar.date(from: startComponents) ?? date
        let end = calendar.date(byAdding: .day, value: weeksPerTerm * 7 - 1, to: start) ?? start
        return (start, end)
    }
}
