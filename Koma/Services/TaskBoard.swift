import Foundation

/// やることの仕分け。To-Do タブの並びと、タブバーのバッジで同じ基準を使う。
@MainActor
enum TaskBoard {
    struct Groups {
        var checkIn: [TaskItem] = []
        var thisWeek: [TaskItem] = []
        var later: [TaskItem] = []
        var finals: [TaskItem] = []
        var exams: [TaskItem] = []
        /// 「Next 7 days」が含む最後の日。
        var lastDay: Date = .now

        /// To-Do に並ぶ件数。タブバーのバッジもこれを使う。
        var count: Int {
            checkIn.count + thisWeek.count + later.count + finals.count + exams.count
        }
    }

    /// 同じ期限のものは早いコマから並べる。FS は連続コマで2件出るため。
    static func inOrder(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.dueDate != rhs.dueDate { return lhs.dueDate < rhs.dueDate }
        if lhs.period != rhs.period { return lhs.period < rhs.period }
        return lhs.kindRaw < rhs.kindRaw
    }

    static func groups(
        from tasks: [TaskItem],
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Groups {
        let open = tasks.filter { !$0.isDone }
        let today = calendar.startOfDay(for: now)
        // 今日から数えて7日後まで（今日が土曜なら次の土曜の終わりまで）を含める。
        guard
            let lastDay = calendar.date(byAdding: .day, value: 7, to: today),
            let weekEnd = calendar.date(byAdding: .day, value: 1, to: lastDay)
        else { return Groups() }

        // 出席だけは授業中の数分しか押せないので、今日ぶんを独立させる。
        let checkIn = open
            .filter { !$0.isManual && $0.kind == .attendance && $0.requiresAction && calendar.isDateInToday($0.dueDate) }
            .sorted(by: inOrder)

        // FS と課題は授業が終わってから期限までのあいだ手を動かせる。
        // FS は授業当日・翌日・2日後（期限日）の3日間が窓になる。
        let thisWeek = open
            .filter {
                guard $0.kind != .attendance, $0.kind != .finalAssignment, $0.kind != .exam else { return false }
                guard $0.dueDate >= today, $0.dueDate < weekEnd else { return false }
                return $0.isManual || $0.classDate <= now
            }
            .sorted(by: inOrder)

        let later = open.filter { $0.isManual && $0.dueDate >= weekEnd }
        let exams = open
            .filter { $0.kind == .exam }
            .sorted { $0.dueDate < $1.dueDate }
        let finals = open
            .filter { $0.kind == .finalAssignment }
            .sorted { $0.dueDate < $1.dueDate }

        return Groups(
            checkIn: checkIn,
            thisWeek: thisWeek,
            later: later,
            finals: finals,
            exams: exams,
            lastDay: lastDay
        )
    }
}
