import Foundation

/// 学期の途中に入る休み（冬休みなど）。この期間は全授業が行われない。
/// 授業ごとの休講とは別で、学期に対して1つ置けば全科目に効く。
struct TermBreak: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var start: Date
    var end: Date

    init(id: UUID = UUID(), name: String = "", start: Date, end: Date) {
        self.id = id
        self.name = name
        self.start = Calendar.current.startOfDay(for: start)
        self.end = Calendar.current.startOfDay(for: end)
    }

    var displayName: String { name.isEmpty ? "Break" : name }

    var rangeText: String {
        let from = start.formatted(.dateTime.month(.abbreviated).day())
        let to = end.formatted(.dateTime.month(.abbreviated).day())
        return from == to ? from : "\(from) – \(to)"
    }

    func contains(_ day: Date, calendar: Calendar = .current) -> Bool {
        let target = calendar.startOfDay(for: day)
        return target >= calendar.startOfDay(for: start) && target <= calendar.startOfDay(for: end)
    }
}
