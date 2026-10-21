import Foundation
import SwiftData
import SwiftUI

/// 1つの授業。時間割のコマ、持ち物、出席方法、そして FS／課題のリマインド設定を持つ。
@Model
final class Course {
    var name: String = ""
    var teacher: String = ""
    /// 教室の場所。コマごとに違う場合は Meeting 側で上書きできる。
    var room: String = ""
    /// 持ち物。改行区切りで複数書ける。
    var items: String = ""
    /// 出席の取り方。サイトと対面を併用する授業があるため複数持てる。
    var attendanceChannelsRaw: [String] = [AttendanceChannel.digiCan.rawValue]
    /// 出席方法の補足（「後半に呼名あり」など）。
    var attendanceDetail: String = ""
    /// サイトで出席を押せる時間。授業開始から何分までか。
    var attendanceWindowMinutes: Int = 5
    /// 授業開始から何分後に確認の通知を出すか。
    var attendanceLeadMinutes: Int = 0
    var attendanceReminderEnabled: Bool = true
    /// 単位が認定される出席率（%）。これを「超える」ことが条件。
    var attendanceThresholdPercent: Int = 70
    /// 空のときは出席方法から文を自動で作る。
    var attendancePrompt: String = ""
    var colorIndex: Int = 0
    var note: String = ""
    var createdAt: Date = Date.now

    // MARK: - フィードバックシート（FS）

    /// FS は「授業の2日後の 23:59」で固定。授業ごとに変えられるのは通知の時刻だけ。
    static let fsDelayDays = 2
    static let fsDeadlineHour = 23
    static let fsDeadlineMinute = 59

    var fsEnabled: Bool = true
    var fsReminderHour: Int = 19
    var fsReminderMinute: Int = 0
    var fsPrompt: String = "Did you write your FS?"

    // MARK: - 課題

    var assignmentEnabled: Bool = false
    var assignmentDeadlineModeRaw: String = AssignmentDeadlineMode.daysAfterClass.rawValue
    /// 授業の何日後が提出期限か。既定は次の授業の前日（週1コマなら6日後）。
    var assignmentDueDays: Int = 6
    var assignmentDueHour: Int = 23
    var assignmentDueMinute: Int = 59
    /// 期限の何日前に知らせるか。
    var assignmentReminderDaysBefore: Int = 1
    var assignmentReminderHour: Int = 19
    var assignmentReminderMinute: Int = 0
    var assignmentPrompt: String = "Have you finished the assignment?"
    /// 課題の出題形式のメモ（「毎回レポート1枚」など）。
    var assignmentNote: String = ""

    // MARK: - 最終課題

    var finalEnabled: Bool = false
    var finalTitle: String = "Final project"
    /// 提出の締め切りそのもの。
    var finalDueDate: Date = Date.now
    /// 締め切りの何日前に知らせるか。
    var finalReminderDaysBefore: Int = 7
    var finalReminderHour: Int = 19
    var finalReminderMinute: Int = 0
    var finalNote: String = ""

    /// 休講にした日（その日の0時）。この日は出席・FS・課題を作らない。
    var cancelledDays: [Date] = []

    var semester: Semester?

    @Relationship(deleteRule: .cascade, inverse: \Meeting.course)
    var meetings: [Meeting] = []

    @Relationship(deleteRule: .cascade, inverse: \TaskItem.course)
    var tasks: [TaskItem] = []

    @Relationship(deleteRule: .cascade, inverse: \Exam.course)
    var exams: [Exam] = []

    @Relationship(deleteRule: .cascade, inverse: \MakeupClass.course)
    var makeups: [MakeupClass] = []

    init(
        name: String = "",
        teacher: String = "",
        room: String = "",
        colorIndex: Int = 0,
        semester: Semester? = nil
    ) {
        self.name = name
        self.teacher = teacher
        self.room = room
        self.colorIndex = colorIndex
        self.semester = semester
        self.createdAt = .now
    }

    var attendanceChannels: [AttendanceChannel] {
        get {
            attendanceChannelsRaw
                .compactMap(AttendanceChannel.init(rawValue:))
                .sorted { $0.sortOrder < $1.sortOrder }
        }
        set {
            attendanceChannelsRaw = newValue
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.rawValue)
        }
    }

    /// サイトで自分で押す必要がある方式だけ。
    var onlineAttendanceChannels: [AttendanceChannel] {
        attendanceChannels.filter(\.isOnline)
    }

    var usesOnlineAttendance: Bool { !onlineAttendanceChannels.isEmpty }

    /// 「DigiCan and In person」のような要約。
    var attendanceSummary: String {
        let channels = attendanceChannels
        guard !channels.isEmpty else { return "Not set" }
        return channels.map(\.shortTitle).formatted(.list(type: .and))
    }

    /// 出席の既定の通知文。サイト名や締め切りは通知の件名と2行目に出るので、本文は短く聞くだけにする。
    var autoAttendancePrompt: String { "Did you check in?" }

    /// 授業開始時刻から、サイトで押せる締め切りを求める。
    func attendanceDeadline(fromClassStart start: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .minute, value: max(1, attendanceWindowMinutes), to: start) ?? start
    }

    var color: Color { CoursePalette.color(at: colorIndex) }

    var displayName: String { name.isEmpty ? "Untitled course" : name }

    var itemList: [String] {
        items
            .split(whereSeparator: { $0.isNewline || $0 == "," || $0 == "、" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var sortedMeetings: [Meeting] {
        meetings.sorted {
            if $0.sortWeekday != $1.sortWeekday { return $0.sortWeekday < $1.sortWeekday }
            return $0.period < $1.period
        }
    }

    /// 「Mon P1 · Wed P3」のような短い要約。
    var scheduleSummary: String {
        let parts = sortedMeetings.map { "\($0.weekdayShortText) P\($0.period)" }
        return parts.isEmpty ? "No times set" : parts.joined(separator: " · ")
    }

    // MARK: - 休講

    func isCancelled(on day: Date, calendar: Calendar = .current) -> Bool {
        cancelledDays.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    func setCancelled(_ cancelled: Bool, on day: Date, calendar: Calendar = .current) {
        let target = calendar.startOfDay(for: day)
        var days = cancelledDays.filter { !calendar.isDate($0, inSameDayAs: target) }
        if cancelled { days.append(target) }
        cancelledDays = days.sorted()
    }

    /// これから先の休講の数。
    func upcomingCancellationCount(from date: Date = .now, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: date)
        return cancelledDays.filter { $0 >= today }.count
    }

    /// 詳細画面に出す休講の要約。過去ぶんしか無いときに「なし」と出さないようにする。
    func cancellationSummary(from date: Date = .now, calendar: Calendar = .current) -> String {
        let total = cancelledDays.count
        guard total > 0 else { return "None" }
        let upcoming = upcomingCancellationCount(from: date, calendar: calendar)
        if upcoming == 0 { return "\(total) past" }
        if upcoming == total { return "\(total) upcoming" }
        return "\(upcoming) upcoming · \(total) total"
    }

    func room(for meeting: Meeting) -> String {
        meeting.roomOverride.isEmpty ? room : meeting.roomOverride
    }

    /// リマインドを有効にしている種類。
    var enabledReminderKinds: [TaskKind] {
        TaskKind.allCases.filter { isEnabled($0) }
    }

    /// 表示名を変えられるのは最終課題だけ。試験は各 Exam が名前を持つ。
    func label(for kind: TaskKind) -> String {
        guard kind == .finalAssignment else { return kind.defaultLabel }
        return finalTitle.isEmpty ? TaskKind.finalAssignment.defaultLabel : finalTitle
    }

    /// 設定だけを写す。名前・コマ・やること・試験は含めない。
    /// 学期の複製と、授業を分けるときに使う。
    func copySettings(from other: Course) {
        teacher = other.teacher
        room = other.room
        items = other.items
        note = other.note

        attendanceChannelsRaw = other.attendanceChannelsRaw
        attendanceDetail = other.attendanceDetail
        attendanceWindowMinutes = other.attendanceWindowMinutes
        attendanceLeadMinutes = other.attendanceLeadMinutes
        attendanceReminderEnabled = other.attendanceReminderEnabled
        attendancePrompt = other.attendancePrompt

        fsEnabled = other.fsEnabled
        fsReminderHour = other.fsReminderHour
        fsReminderMinute = other.fsReminderMinute
        fsPrompt = other.fsPrompt

        assignmentEnabled = other.assignmentEnabled
        assignmentDeadlineModeRaw = other.assignmentDeadlineModeRaw
        assignmentDueDays = other.assignmentDueDays
        assignmentDueHour = other.assignmentDueHour
        assignmentDueMinute = other.assignmentDueMinute
        assignmentReminderDaysBefore = other.assignmentReminderDaysBefore
        assignmentReminderHour = other.assignmentReminderHour
        assignmentReminderMinute = other.assignmentReminderMinute
        assignmentPrompt = other.assignmentPrompt
        assignmentNote = other.assignmentNote

        finalEnabled = other.finalEnabled
        finalTitle = other.finalTitle
        finalDueDate = other.finalDueDate
        finalReminderDaysBefore = other.finalReminderDaysBefore
        finalReminderHour = other.finalReminderHour
        finalReminderMinute = other.finalReminderMinute
        finalNote = other.finalNote
    }

    var sortedExams: [Exam] {
        exams.sorted { $0.date < $1.date }
    }

    /// 学期ぶんの授業回数（コマ単位）。休講を除き、振替を足す。
    @MainActor
    func plannedClassCount(calendar: Calendar = .current) -> Int {
        guard let semester else { return 0 }
        return ClassDays.classOccurrences(
            for: self,
            in: semester,
            from: calendar.startOfDay(for: semester.startDate),
            to: calendar.startOfDay(for: semester.endDate),
            calendar: calendar
        ).count
    }

    /// 単位認定に必要な出席回数と、あと何回休めるか。
    /// 「70%超」なので、ちょうど70%では足りない点に注意。
    @MainActor
    func creditOutlook(upTo now: Date = .now, calendar: Calendar = .current) -> (total: Int, needed: Int, canMiss: Int)? {
        let total = plannedClassCount(calendar: calendar)
        guard total > 0 else { return nil }
        let ratio = Double(max(0, min(100, attendanceThresholdPercent))) / 100
        // p / total > ratio を満たす最小の整数
        let needed = min(total, Int((Double(total) * ratio).rounded(.down)) + 1)
        let absent = attendanceTally(upTo: now).absent
        return (total, needed, max(0, total - needed - absent))
    }

    /// これまでの出席の集計。授業がすでに終わった回だけを数える。
    func attendanceTally(upTo now: Date = .now) -> (present: Int, absent: Int, unrecorded: Int) {
        let past = tasks.filter { $0.kind == .attendance && $0.classDate <= now }
        var present = 0, absent = 0, unrecorded = 0
        for task in past {
            switch task.attendanceOutcome {
            case .present: present += 1
            case .absent: absent += 1
            case nil: unrecorded += 1
            }
        }
        return (present, absent, unrecorded)
    }

    var sortedMakeups: [MakeupClass] {
        makeups.sorted { $0.date == $1.date ? $0.period < $1.period : $0.date < $1.date }
    }

    /// これから先の振替の数。
    func upcomingMakeupCount(from date: Date = .now, calendar: Calendar = .current) -> Int {
        let today = calendar.startOfDay(for: date)
        return makeups.filter { $0.date >= today }.count
    }

    func prompt(for kind: TaskKind) -> String {
        switch kind {
        case .attendance:
            return attendancePrompt.isEmpty ? autoAttendancePrompt : attendancePrompt
        case .exam:
            return "You have an exam coming up."
        case .finalAssignment:
            return "\(label(for: kind)) is due \(finalDueDate.formatted(.dateTime.month(.abbreviated).day()))."
        case .feedbackSheet:
            return fsPrompt.isEmpty ? "Did you write your \(label(for: kind))?" : fsPrompt
        case .assignment:
            return assignmentPrompt.isEmpty ? "Have you finished your \(label(for: kind).lowercased())?" : assignmentPrompt
        }
    }

    func delayDays(for kind: TaskKind) -> Int {
        switch kind {
        case .attendance, .finalAssignment, .exam: return 0
        case .feedbackSheet: return Self.fsDelayDays
        case .assignment: return max(0, assignmentDueDays)
        }
    }

    var assignmentDeadlineMode: AssignmentDeadlineMode {
        get { AssignmentDeadlineMode(rawValue: assignmentDeadlineModeRaw) ?? .daysAfterClass }
        set { assignmentDeadlineModeRaw = newValue.rawValue }
    }

    /// 提出期限そのものの時刻。FS は通知時刻がそのまま期限になる。
    func deadlineTime(for kind: TaskKind) -> (hour: Int, minute: Int) {
        switch kind {
        case .assignment: return (assignmentDueHour, assignmentDueMinute)
        case .feedbackSheet: return (Self.fsDeadlineHour, Self.fsDeadlineMinute)
        default: return reminderTime(for: kind)
        }
    }

    /// 期限から逆算した通知日時。期限と通知は別々に設定できる。
    func notifyDate(forDeadline deadline: Date, kind: TaskKind, calendar: Calendar = .current) -> Date {
        let daysBefore: Int
        let time: (hour: Int, minute: Int)
        switch kind {
        case .assignment:
            daysBefore = max(0, assignmentReminderDaysBefore)
            time = (assignmentReminderHour, assignmentReminderMinute)
        case .finalAssignment:
            daysBefore = max(0, finalReminderDaysBefore)
            time = (finalReminderHour, finalReminderMinute)
        case .feedbackSheet:
            // 期限は 23:59 だが、その時刻に鳴らしても遅いので当日の指定時刻に出す。
            daysBefore = 0
            time = (fsReminderHour, fsReminderMinute)
        default:
            return deadline
        }
        let base = calendar.date(byAdding: .day, value: -daysBefore, to: deadline) ?? deadline
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: base) ?? base
    }

    func reminderTime(for kind: TaskKind) -> (hour: Int, minute: Int) {
        switch kind {
        case .attendance, .exam: return (0, 0)
        case .finalAssignment: return (finalReminderHour, finalReminderMinute)
        case .feedbackSheet: return (fsReminderHour, fsReminderMinute)
        case .assignment: return (assignmentReminderHour, assignmentReminderMinute)
        }
    }

    func isEnabled(_ kind: TaskKind) -> Bool {
        switch kind {
        // 対面だけの授業は自分で操作する必要がないので通知しない。
        case .attendance: return attendanceReminderEnabled && usesOnlineAttendance
        case .feedbackSheet: return fsEnabled
        case .assignment: return assignmentEnabled
        case .finalAssignment: return finalEnabled
        case .exam: return !exams.isEmpty
        }
    }
}
