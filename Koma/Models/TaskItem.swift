import Foundation
import SwiftData

/// 出席の結果。押し忘れと欠席を区別するために持つ。
enum AttendanceOutcome: String, CaseIterable, Identifiable, Codable, Sendable {
    case present
    case late
    case absent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .present: return "Present"
        case .late: return "Late"
        case .absent: return "Absent"
        }
    }

    var symbolName: String {
        switch self {
        case .present: return "checkmark.circle.fill"
        case .late: return "clock.badge.exclamationmark.fill"
        case .absent: return "xmark.circle.fill"
        }
    }

    /// 出席率の計算で「出ていない」として数えるかどうか。遅刻は欠席と同じ扱い。
    var countsAsMissed: Bool { self != .present }
}

/// やることの種類。
enum TaskKind: String, CaseIterable, Identifiable, Codable, Sendable {
    /// 授業の開始直後に、学内サイトで出席を押したか確認する。
    case attendance
    case feedbackSheet
    /// 毎週出る課題。
    case assignment
    /// 学期末の最終課題。回ごとではなく授業にひとつだけ。
    case finalAssignment
    /// 試験。授業にひもづけて日時を登録する。
    case exam

    var id: String { rawValue }

    var defaultLabel: String {
        switch self {
        case .attendance: return "Attendance"
        case .feedbackSheet: return "FS"
        case .assignment: return "Assignment"
        case .finalAssignment: return "Final project"
        case .exam: return "Exam"
        }
    }

    var shortLabel: String {
        switch self {
        case .attendance: return "Attendance"
        case .feedbackSheet: return "FS"
        case .assignment: return "Assignment"
        case .finalAssignment: return "Final"
        case .exam: return "Exam"
        }
    }

    var symbolName: String {
        switch self {
        case .attendance: return "person.crop.circle.badge.checkmark"
        case .feedbackSheet: return "doc.text"
        case .assignment: return "pencil.and.list.clipboard"
        case .finalAssignment: return "flag.checkered"
        case .exam: return "pencil.and.ruler"
        }
    }

    /// 毎週の授業から繰り返し作られる種類かどうか。最終課題と試験は例外。
    var isRecurring: Bool { self != .finalAssignment && self != .exam }

    /// 日単位ではなく、授業開始からの分で計るリマインドかどうか。
    var isMinuteBased: Bool { self == .attendance }

    /// コマごとに1件作る種類かどうか。
    /// 出席はコマごとに押す必要があり、FS もコマごとに1枚書く必要がある。
    var isPerPeriod: Bool { self == .attendance || self == .feedbackSheet }
}

/// 授業から自動で作られる、あるいは手で足した1件のやること。
@Model
final class TaskItem {
    /// 通知の識別子と検索キーを兼ねる。
    var uid: UUID = UUID()
    var kindRaw: String = TaskKind.feedbackSheet.rawValue
    /// 元になった授業の日時（手動で足したものは作成日）。
    var classDate: Date = Date.now
    /// リマインドが来る日時。
    var dueDate: Date = Date.now
    var isDone: Bool = false
    var completedAt: Date?
    /// 手で追加したものは授業予定と同期させず、消さない。
    var isManual: Bool = false
    /// 手動タスクのタイトル（自動生成のものは空）。
    var customTitle: String = ""
    /// 出席と FS は限ごとに1件作るので、どのコマのものかを持っておく。ほかの種類は 0。
    var period: Int = 0
    /// 試験のときだけ、どの試験のものかを指す。
    var examUID: UUID?
    /// 出席のときだけ、出たか休んだかを持つ。未記録なら nil。
    var attendanceOutcomeRaw: String?
    var memo: String = ""

    var course: Course?

    init(
        kind: TaskKind,
        classDate: Date,
        dueDate: Date,
        course: Course?,
        isManual: Bool = false,
        customTitle: String = ""
    ) {
        self.uid = UUID()
        self.kindRaw = kind.rawValue
        self.classDate = classDate
        self.dueDate = dueDate
        self.course = course
        self.isManual = isManual
        self.customTitle = customTitle
        self.isDone = false
    }

    var kind: TaskKind {
        get { TaskKind(rawValue: kindRaw) ?? .assignment }
        set { kindRaw = newValue.rawValue }
    }

    var title: String {
        if !customTitle.isEmpty { return customTitle }
        return course?.label(for: kind) ?? kind.defaultLabel
    }

    var courseName: String { course?.displayName ?? "No course" }

    var attendanceOutcome: AttendanceOutcome? {
        get { attendanceOutcomeRaw.flatMap(AttendanceOutcome.init(rawValue:)) }
        set { attendanceOutcomeRaw = newValue?.rawValue }
    }

    /// 出たか休んだかを記録する。どちらでも「片付いた」扱いにして、やることからは外す。
    func record(_ outcome: AttendanceOutcome) {
        attendanceOutcome = outcome
        markDone(true)
    }

    /// 自分で何かする必要がある回かどうか。
    /// 対面で先生が取る出席は、こちらが操作することがないのでやることには出さない。
    var requiresAction: Bool {
        guard kind == .attendance else { return true }
        return course?.usesOnlineAttendance ?? true
    }

    var exam: Exam? {
        guard let examUID else { return nil }
        return course?.exams.first { $0.uid == examUID }
    }

    var prompt: String {
        if let exam {
            return "\(exam.displayTitle) is on \(exam.dateText)."
        }
        return course?.prompt(for: kind) ?? "Have you finished \(title)?"
    }

    var isOverdue: Bool {
        !isDone && dueDate < .now
    }

    /// 通知を出す日時。課題と最終課題は、期限の何日か前に知らせる。
    var notifyDate: Date {
        guard !isManual, let course else { return dueDate }
        return course.notifyDate(forDeadline: dueDate, kind: kind)
    }

    /// コマごとに作る種類のときだけ、どのコマのものかを返す。
    var periodText: String? {
        guard kind.isPerPeriod, period > 0 else { return nil }
        return "P\(period)"
    }

    /// 出席をサイトで押せる締め切り。授業開始から設定した分数まで。
    var attendanceDeadline: Date? {
        guard kind == .attendance, let course else { return nil }
        return Calendar.current.date(
            byAdding: .minute,
            value: max(1, course.attendanceWindowMinutes),
            to: classDate
        )
    }

    /// 「Oct 7 (Tue)」のような、どの回のものか分かる説明。
    var classDateText: String {
        classDate.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated))
    }

    var dueText: String {
        let calendar = Calendar.current
        let time = dueDate.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(dueDate) { return "Today \(time)" }
        if calendar.isDateInTomorrow(dueDate) { return "Tomorrow \(time)" }
        if calendar.isDateInYesterday(dueDate) { return "Yesterday \(time)" }
        return dueDate.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated).hour().minute())
    }

    func markDone(_ done: Bool) {
        isDone = done
        completedAt = done ? .now : nil
        // チェックを外したら、出席の記録も未記録に戻す。
        if !done { attendanceOutcome = nil }
        // 出席をチェックしただけなら「出た」とみなす。
        if done, kind == .attendance, attendanceOutcome == nil { attendanceOutcome = .present }
    }
}
