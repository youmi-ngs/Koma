import Foundation
import SwiftData

/// 時間割から「やること」を作り、通知の内容を組み立てる。
enum TaskScheduler {
    /// 先どこまで作るか。過去側は「授業を登録した日」以降をずっと見る
    /// （休講を取り消したとき、古い回のやることも戻せるようにするため）。
    static let futureWindowDays = 120

    private struct TaskKey: Hashable {
        var kind: TaskKind
        var day: Date
        /// 出席は限ごとに1件作るので限で区別する。ほかの種類は 0（1日1件）。
        var period: Int
    }

    private struct Desired {
        var classDate: Date
        var period: Int
        var dueDate: Date
        var examUID: UUID?
        var title: String?
    }

    /// 出席と FS はコマ単位。連続コマでも、押すのも書くのもコマごとに必要なため。
    private static func key(kind: TaskKind, day: Date, period: Int) -> TaskKey {
        TaskKey(kind: kind, day: day, period: kind.isPerPeriod ? period : 0)
    }

    /// 授業の予定と設定にあわせて TaskItem を作成・更新・削除する。
    @MainActor
    static func generateTasks(in context: ModelContext, now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        guard let windowEnd = calendar.date(byAdding: .day, value: futureWindowDays, to: today)
        else { return }

        let courses = (try? context.fetch(FetchDescriptor<Course>())) ?? []

        for course in courses {
            let historyStart = historyStart(for: course, calendar: calendar)
            let desired = desiredTasks(
                for: course,
                historyStart: historyStart,
                windowEnd: windowEnd,
                calendar: calendar
            )

            var matched: Set<TaskKey> = []
            for task in course.tasks where !task.isManual {
                // コマ単位にする前に作られたぶんは、どのコマだったかを補っておく。
                // そうしないと完了済みの古い1件が宙に浮き、同じ日に新しい2件が増えてしまう。
                if task.kind.isPerPeriod, task.period == 0,
                   let inferred = inferredPeriod(for: task, course: course, calendar: calendar) {
                    task.period = inferred
                }

                let key = key(
                    kind: task.kind,
                    day: calendar.startOfDay(for: task.classDate),
                    period: task.period
                )
                if let wanted = desired[key], !matched.contains(key) {
                    matched.insert(key)
                    // 完了済みのものは記録として触らない。
                    if !task.isDone {
                        task.classDate = wanted.classDate
                        task.dueDate = wanted.dueDate
                        task.period = wanted.period
                        task.examUID = wanted.examUID
                        task.customTitle = wanted.title ?? ""
                    }
                } else if !task.isDone,
                          task.kind == .finalAssignment
                            || task.kind == .exam
                            // 過去の回でも、休講にしたぶんは片付ける。
                            || course.isCancelled(on: task.classDate, calendar: calendar)
                            || (key.day >= historyStart && key.day <= windowEnd) {
                    // 設定変更やコマの削除で不要になった未完了分を片付ける。
                    context.delete(task)
                }
            }

            for (key, value) in desired where !matched.contains(key) {
                let task = TaskItem(
                    kind: key.kind,
                    classDate: value.classDate,
                    dueDate: value.dueDate,
                    course: course
                )
                task.period = value.period
                task.examUID = value.examUID
                task.customTitle = value.title ?? ""
                context.insert(task)
            }
        }

        try? context.save()
    }

    /// 古いやることの「どのコマだったか」を、開始時刻から割り出す。
    private static func inferredPeriod(for task: TaskItem, course: Course, calendar: Calendar) -> Int? {
        let time = calendar.dateComponents([.hour, .minute], from: task.classDate)
        if let semester = course.semester,
           let slot = semester.periods.first(where: { $0.startHour == time.hour && $0.startMinute == time.minute }) {
            return slot.index
        }
        let weekday = calendar.component(.weekday, from: task.classDate)
        return course.meetings.filter { $0.weekday == weekday }.map(\.period).min()
    }

    /// この授業のやることを面倒みる範囲の始まり。
    /// 学期の開始まで遡る。学期途中で授業を登録しても、
    /// すでに終わった回のぶん（書けていない FS や課題）がちゃんと出てくるようにするため。
    private static func historyStart(for course: Course, calendar: Calendar) -> Date {
        guard let semester = course.semester else {
            return calendar.startOfDay(for: course.createdAt)
        }
        return calendar.startOfDay(for: semester.startDate)
    }

    @MainActor
    private static func desiredTasks(
        for course: Course,
        historyStart: Date,
        windowEnd: Date,
        calendar: Calendar
    ) -> [TaskKey: Desired] {
        var result: [TaskKey: Desired] = [:]
        guard let semester = course.semester else { return result }

        // 最終課題は授業にひとつだけ。学期やコマの並びとは関係なく締め切りで決まる。
        if course.finalEnabled {
            let finalKey = key(kind: .finalAssignment, day: calendar.startOfDay(for: course.finalDueDate), period: 0)
            result[finalKey] = Desired(classDate: course.finalDueDate, period: 0, dueDate: course.finalDueDate)
        }

        // 試験も日時そのものが決め手。同じ授業で同じ日に2つは入らない前提。
        for exam in course.exams {
            let examKey = key(kind: .exam, day: calendar.startOfDay(for: exam.date), period: 0)
            result[examKey] = Desired(
                classDate: exam.date,
                period: 0,
                dueDate: exam.date,
                examUID: exam.uid,
                title: exam.displayTitle
            )
        }

        let kinds = course.enabledReminderKinds.filter(\.isRecurring)
        guard !kinds.isEmpty else { return result }

        let rangeEnd = min(calendar.startOfDay(for: semester.endDate), windowEnd)
        guard historyStart <= rangeEnd else { return result }

        let occurrences = ClassDays.classOccurrences(
            for: course,
            in: semester,
            from: historyStart,
            to: rangeEnd,
            calendar: calendar
        )
        guard !occurrences.isEmpty else { return result }

        // 「次の授業の前まで」を期限にする場合だけ、学期ぶんの授業開始時刻を並べておく。
        let classStarts: [Date] = course.assignmentEnabled
            && course.assignmentDeadlineMode == .beforeNextClass
            ? allClassStarts(for: course, in: semester, calendar: calendar)
            : []

        for kind in kinds {
            for occurrence in occurrences {
                let slotKey = key(kind: kind, day: occurrence.day, period: occurrence.period)
                // コマ単位でないものは1日1件。同じ日に2コマある授業は早いコマを基準にする。
                if !kind.isPerPeriod,
                   let existing = result[slotKey],
                   existing.classDate <= occurrence.start {
                    continue
                }
                result[slotKey] = Desired(
                    classDate: occurrence.start,
                    period: occurrence.period,
                    dueDate: dueDate(
                        for: kind,
                        course: course,
                        classDay: occurrence.day,
                        classStart: occurrence.start,
                        nextClassStart: classStarts.first { $0 > occurrence.start },
                        calendar: calendar
                    )
                )
            }
        }
        return result
    }

    /// この授業の「授業日」を時系列で並べる。
    /// 2時間続きのように同じ日に複数コマある授業は、その日の最初のコマを代表にして1件にまとめる。
    /// まとめないと、1限の課題の期限が同じ日の2限になってしまう。
    @MainActor
    private static func allClassStarts(
        for course: Course,
        in semester: Semester,
        calendar: Calendar
    ) -> [Date] {
        let occurrences = ClassDays.classOccurrences(
            for: course,
            in: semester,
            from: calendar.startOfDay(for: semester.startDate),
            to: calendar.startOfDay(for: semester.endDate),
            calendar: calendar
        )
        var firstStartByDay: [Date: Date] = [:]
        for occurrence in occurrences {
            if let existing = firstStartByDay[occurrence.day], existing <= occurrence.start { continue }
            firstStartByDay[occurrence.day] = occurrence.start
        }
        return firstStartByDay.values.sorted()
    }

    /// 提出期限を求める。    /// 提出期限を求める。出席は授業開始からの分、課題は設定した決め方による。
    static func dueDate(
        for kind: TaskKind,
        course: Course,
        classDay: Date,
        classStart: Date,
        nextClassStart: Date? = nil,
        calendar: Calendar = .current
    ) -> Date {
        if kind == .assignment, course.assignmentDeadlineMode == .beforeNextClass {
            // 学期最後の回は次が無いので、1週間後の同じ時刻を期限にしておく。
            return nextClassStart
                ?? calendar.date(byAdding: .day, value: 7, to: classStart)
                ?? classStart
        }

        if kind.isMinuteBased {
            return calendar.date(
                byAdding: .minute,
                value: max(0, course.attendanceLeadMinutes),
                to: classStart
            ) ?? classStart
        }

        let day = calendar.startOfDay(for: classDay)
        let shifted = calendar.date(byAdding: .day, value: course.delayDays(for: kind), to: day) ?? day
        let time = course.deadlineTime(for: kind)
        return calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: shifted) ?? shifted
    }

    /// 未完了のやることから通知の予定表を作る。
    /// あわせて、アプリアイコンのバッジに出す件数（To-Do タブと同じ）も返す。
    @MainActor
    static func reminderPlans(
        in context: ModelContext,
        now: Date = .now
    ) -> (plans: [ReminderPlan], badgeCount: Int) {
        let calendar = Calendar.current
        var descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.isDone == false },
            sortBy: [SortDescriptor(\.dueDate, order: .forward)]
        )
        descriptor.fetchLimit = 400
        let tasks = (try? context.fetch(descriptor)) ?? []

        // アイコンのバッジは To-Do タブの件数に合わせる。期限切れの数ではない。
        let badgeCount = TaskBoard.groups(from: tasks, now: now).count

        var plans: [ReminderPlan] = []
        for task in tasks {
            // 試験だけは「1週間前」「前日」のように複数回知らせる。
            if task.kind == .exam, let exam = task.exam {
                for (index, fireAt) in exam.reminderDates(calendar: calendar).enumerated() where fireAt > now {
                    plans.append(ReminderPlan(
                        id: "\(task.uid.uuidString)-\(index)",
                        taskUID: task.uid.uuidString,
                        title: task.courseName,
                        body: task.prompt,
                        subtitle: subtitle(for: task),
                        fireAt: fireAt
                    ))
                }
                continue
            }

            guard task.notifyDate > now else { continue }
            plans.append(ReminderPlan(
                id: task.uid.uuidString,
                taskUID: task.uid.uuidString,
                title: task.courseName,
                body: task.prompt,
                subtitle: subtitle(for: task),
                fireAt: task.notifyDate
            ))
        }
        plans.sort { $0.fireAt < $1.fireAt }

        return (plans, badgeCount)
    }

    /// 通知の2行目。出席は締め切りを出し、それ以外はどの回の分かを出す。
    private static func subtitle(for task: TaskItem) -> String {
        if task.kind == .attendance, let deadline = task.attendanceDeadline {
            let until = "Open until \(deadline.formatted(date: .omitted, time: .shortened))"
            // 連続コマは通知が続けて届くので、どのコマのぶんか分かるようにする。
            guard let periodText = task.periodText else { return until }
            return "\(periodText) · \(until)"
        }
        if let exam = task.exam {
            let room = exam.room.isEmpty ? "" : " · \(exam.room)"
            return "\(exam.dateText)\(room)"
        }
        if task.kind == .finalAssignment {
            return "Due \(task.dueDate.formatted(.dateTime.month(.abbreviated).day()))"
        }
        let base = "\(task.title) · \(task.classDateText) class"
        // 連続コマは同じ時刻に2件届くので、どのコマのぶんか分かるようにする。
        guard let periodText = task.periodText else { return base }
        return "\(periodText) · \(base)"
    }
}

/// 画面や通知から呼ばれる同期の入口。
@MainActor
final class TaskSyncCoordinator {
    static let shared = TaskSyncCoordinator()

    private init() {}

    /// やることを作り直し、通知も貼り替える。
    func sync(context: ModelContext? = nil) async {
        let context = context ?? ModelContext(AppContainer.shared)
        TaskScheduler.generateTasks(in: context)
        await refreshNotifications(context: context)
    }

    /// データはそのままで、通知だけ貼り替える。
    func refreshNotifications(context: ModelContext? = nil) async {
        let context = context ?? ModelContext(AppContainer.shared)
        let result = TaskScheduler.reminderPlans(in: context)
        await NotificationManager.shared.reschedule(
            with: result.plans,
            badgeCount: result.badgeCount
        )
    }
}
