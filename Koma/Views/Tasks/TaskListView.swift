import SwiftData
import SwiftUI

/// やることタブ。上の切り替えで、いま動かせるもの・やり損ねたもの・済んだものを行き来する。
struct TaskListView: View {
    private enum Scope: String, CaseIterable, Identifiable {
        case todo
        case missed
        case done

        var id: String { rawValue }

        var title: String {
            switch self {
            case .todo: return "To-Do"
            case .missed: return "Missed"
            case .done: return "Done"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.dueDate, order: .forward) private var tasks: [TaskItem]
    @Query private var semesters: [Semester]

    @State private var scope: Scope = .todo
    /// nil なら全部。種類で絞り込むとどのタブでも効く。
    @State private var kindFilter: TaskKind?
    @State private var isAddingTask = false

    private struct Bucket: Identifiable {
        var id: String
        var title: String
        var footer: String?
        var items: [TaskItem]
        /// 中身が空でも見出しを残すかどうか。
        var placeholder: String?
    }

    // MARK: - 仕分け

    private var filteredTasks: [TaskItem] {
        guard let kindFilter else { return tasks }
        return tasks.filter { $0.kind == kindFilter }
    }

    private var openTasks: [TaskItem] { filteredTasks.filter { !$0.isDone } }

    private var missedTasks: [TaskItem] {
        let today = Calendar.current.startOfDay(for: .now)
        return openTasks
            // 自分で押す必要のない出席は、記録がなくてもやり損ねではない。
            .filter { $0.dueDate < today && $0.requiresAction }
            .sorted { TaskBoard.inOrder($1, $0) }
    }

    private var doneTasks: [TaskItem] {
        filteredTasks
            .filter(\.isDone)
            .sorted { ($0.completedAt ?? $0.dueDate) > ($1.completedAt ?? $1.dueDate) }
    }

    private var buckets: [Bucket] {
        let groups = TaskBoard.groups(from: filteredTasks)
        let through = groups.lastDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())

        var result: [Bucket] = []
        if !groups.checkIn.isEmpty {
            result.append(Bucket(
                id: "checkin",
                title: "Check in",
                footer: "Mark yourself present on the site before the window closes.",
                items: groups.checkIn,
                placeholder: nil
            ))
        }
        if !groups.thisWeek.isEmpty || kindFilter == nil {
            result.append(Bucket(
                id: "week",
                title: "Next 7 days",
                footer: "Everything due through \(through). FS can be written from the class day until the deadline two days later. Anything past its deadline moves to Missed.",
                items: groups.thisWeek,
                // 絞り込み中は、空の見出しを残すとかえって分かりにくい。
                placeholder: kindFilter == nil ? "Nothing due through \(through)." : nil
            ))
        }
        if !groups.exams.isEmpty {
            result.append(Bucket(
                id: "exam",
                title: "Exams",
                footer: nil,
                items: groups.exams,
                placeholder: nil
            ))
        }
        if !groups.later.isEmpty {
            result.append(Bucket(id: "later", title: "Later", footer: nil, items: groups.later, placeholder: nil))
        }
        // 最終課題は毎週のものと混ざらないよう、いちばん下にまとめる。
        if !groups.finals.isEmpty {
            result.append(Bucket(
                id: "final",
                title: "Final projects",
                footer: "Shown until you tick them off, however far away the deadline is.",
                items: groups.finals,
                placeholder: nil
            ))
        }
        return result
    }

    /// どれがどれだけ溜まっているか、切り替えなくても分かるようにまとめて出す。
    /// セグメントは等幅なので、ラベルに数字を入れると桁が増えたとき文字が切れてしまう。
    private var summaryText: String? {
        let parts: [(Int, String)] = [
            (TaskBoard.groups(from: filteredTasks).count, "to do"),
            (missedTasks.count, "missed"),
            (doneTasks.count, "done"),
        ]
        let shown = parts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        guard !shown.isEmpty else { return nil }
        return shown.joined(separator: " · ")
    }

    private var summaryBar: some View {
        Group {
            if let summaryText {
                Text(summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                    .accessibilityLabel(summaryText)
            }
        }
    }

    private var hasCourses: Bool {
        semesters.contains { !$0.courses.isEmpty }
    }

    // MARK: - 画面

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if hasCourses {
                    summaryBar
                }

                if !hasCourses {
                    noCoursesState
                } else {
                    switch scope {
                    case .todo:
                        bucketList
                    case .missed:
                        flatList(
                            missedTasks,
                            footer: "These are past their deadline. You can still tick one off if you got it done.",
                            emptyTitle: "Nothing Missed",
                            emptySymbol: "checkmark.seal",
                            emptyMessage: "Everything due so far has been taken care of."
                        )
                    case .done:
                        flatList(
                            Array(doneTasks.prefix(200)),
                            footer: nil,
                            emptyTitle: "Nothing Finished Yet",
                            emptySymbol: "tray",
                            emptyMessage: "Items you tick off show up here."
                        )
                    }
                }
            }
            .navigationTitle("To-Do")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Show", selection: $scope) {
                        ForEach(Scope.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 240)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("Filter", selection: $kindFilter) {
                            Text("All").tag(TaskKind?.none)
                            ForEach(TaskKind.allCases) { kind in
                                Label(kind.defaultLabel, systemImage: kind.symbolName)
                                    .tag(TaskKind?.some(kind))
                            }
                        }
                    } label: {
                        Label(
                            "Filter",
                            systemImage: kindFilter == nil
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill"
                        )
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isAddingTask = true
                    } label: {
                        Label("Add To-Do", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingTask) {
                ManualTaskEditView()
            }
        }
    }

    private var bucketList: some View {
        List {
            ForEach(buckets) { bucket in
                Section {
                    if bucket.items.isEmpty, let placeholder = bucket.placeholder {
                        Text(placeholder)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(bucket.items) { task in
                            row(for: task)
                        }
                    }
                } header: {
                    Text(bucket.title)
                } footer: {
                    if let footer = bucket.footer {
                        Text(footer)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func flatList(
        _ items: [TaskItem],
        footer: String?,
        emptyTitle: String,
        emptySymbol: String,
        emptyMessage: String
    ) -> some View {
        Group {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySymbol)
                } description: {
                    Text(emptyMessage)
                }
            } else {
                List {
                    Section {
                        ForEach(items) { task in
                            row(for: task)
                        }
                    } footer: {
                        if let footer {
                            Text(footer)
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func row(for task: TaskItem) -> some View {
        TaskRow(task: task) { toggle(task) }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    toggle(task)
                } label: {
                    Label(
                        task.isDone ? "Not Done" : "Done",
                        systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark"
                    )
                }
                .tint(task.isDone ? .gray : .accentColor)
            }
            .swipeActions(edge: .trailing) {
                if task.isManual {
                    Button(role: .destructive) {
                        delete(task)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                // 押し忘れと欠席は意味が違うので、休んだぶんは記録として残せるようにする。
                if task.kind == .attendance, task.attendanceOutcome != .absent {
                    Button {
                        record(task, as: .absent)
                    } label: {
                        Label("Absent", systemImage: "xmark.circle")
                    }
                    .tint(.red)
                }
            }
            .contextMenu {
                if task.kind == .attendance {
                    ForEach(AttendanceOutcome.allCases) { outcome in
                        Button {
                            record(task, as: outcome)
                        } label: {
                            Label(outcome.title, systemImage: outcome.symbolName)
                        }
                    }
                }
            }
    }

    private var noCoursesState: some View {
        ContentUnavailableView {
            Label("No Courses Yet", systemImage: "square.grid.3x3")
        } description: {
            Text("Add courses to your timetable and attendance, FS, and assignment reminders will appear here automatically.")
        }
    }

    // MARK: - 操作

    private func record(_ task: TaskItem, as outcome: AttendanceOutcome) {
        withAnimation {
            task.record(outcome)
        }
        try? context.save()
        Task { await TaskSyncCoordinator.shared.refreshNotifications(context: context) }
    }

    private func toggle(_ task: TaskItem) {
        withAnimation {
            task.markDone(!task.isDone)
        }
        try? context.save()
        Task { await TaskSyncCoordinator.shared.refreshNotifications(context: context) }
    }

    private func delete(_ task: TaskItem) {
        withAnimation {
            context.delete(task)
        }
        try? context.save()
        Task { await TaskSyncCoordinator.shared.refreshNotifications(context: context) }
    }
}

#Preview {
    TaskListView()
        .modelContainer(PreviewData.container)
}
