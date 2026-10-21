import Foundation
import SwiftData

/// 振替の授業。休講になった回の代わりに、別の日時へ1回ぶん足す。
/// 時間割のコマとは別に持ち、この回ぶんの出席・FS・課題が作られる。
@Model
final class MakeupClass {
    var uid: UUID = UUID()
    /// 振替で行う日（その日の0時）。
    var date: Date = Date.now
    var period: Int = 1
    /// いつもと違う教室でやるときに使う。
    var roomOverride: String = ""
    var note: String = ""
    /// どの休講の振替か（その日の0時）。記録用で、無くてもよい。
    var replacesDay: Date?

    var course: Course?

    init(date: Date, period: Int, course: Course? = nil, replacesDay: Date? = nil) {
        self.uid = UUID()
        self.date = Calendar.current.startOfDay(for: date)
        self.period = period
        self.course = course
        self.replacesDay = replacesDay.map { Calendar.current.startOfDay(for: $0) }
    }

    var dateText: String {
        date.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
    }

    var slotText: String { "\(dateText) · P\(period)" }
}
