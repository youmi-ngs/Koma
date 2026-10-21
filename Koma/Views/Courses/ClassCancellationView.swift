import SwiftData
import SwiftUI

/// 振替の追加シートに渡す「どの休講の代わりか」。
struct MakeupRequest: Identifiable {
    var id = UUID()
    var replacing: Date?
}

/// 休講の設定。学期ぶんの回をすべて並べ、日付ごとに「この日は休み」を切り替える。
struct ClassCancellationView: View {
    @Environment(\.modelContext) private var context
    @Bindable var course: Course
    @State private var makeupRequest: MakeupRequest?

    private var calendar: Calendar { .current }

    private struct MonthGroup: Identifiable {
        var id: Date
        var title: String
        var days: [Date]
    }

    /// 学期の最初から最後までの回。序盤の休講も設定できるよう、期間を切らない。
    private var days: [Date] {
        guard let semester = course.semester else { return [] }
        let start = calendar.startOfDay(for: semester.startDate)
        let end = calendar.startOfDay(for: semester.endDate)
        guard start <= end else { return [] }
        return ClassDays.allDays(for: course, from: start, to: end, calendar: calendar)
    }

    private var groups: [MonthGroup] {
        let grouped = Dictionary(grouping: days) { day -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: day)) ?? day
        }
        return grouped.keys.sorted().map { month in
            MonthGroup(
                id: month,
                title: month.formatted(.dateTime.year().month(.wide)),
                days: (grouped[month] ?? []).sorted()
            )
        }
    }

    /// 一覧の範囲から外れた休講も消せるようにしておく。
    private var otherCancelledDays: [Date] {
        let shown = Set(days)
        return course.cancelledDays.filter { !shown.contains($0) }.sorted()
    }

    /// 開いたときにこの日まで送る。ふつうはこれからの回を触るため。
    private var anchorDay: Date? {
        let today = calendar.startOfDay(for: .now)
        return days.first { $0 >= today } ?? days.last
    }

    private func periodsText(for day: Date) -> String {
        let weekday = calendar.component(.weekday, from: day)
        let periods = course.meetings
            .filter { $0.weekday == weekday }
            .map(\.period)
            .sorted()
        guard let first = periods.first, let last = periods.last else { return "" }
        return first == last ? "P\(first)" : "P\(first)–P\(last)"
    }

    var body: some View {
        Group {
            if days.isEmpty {
                ContentUnavailableView {
                    Label("No Classes", systemImage: "calendar.badge.minus")
                } description: {
                    Text("Add a slot to the timetable first, then you can mark single dates as cancelled.")
                }
            } else {
                list
            }
        }
        .navigationTitle("Cancelled classes")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $makeupRequest) { request in
            MakeupClassEditView(mode: .create(course: course, replacing: request.replacing))
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.days, id: \.self) { day in
                            dayRow(day)
                                .id(day)
                                .swipeActions(edge: .leading) {
                                    if course.isCancelled(on: day, calendar: calendar) {
                                        Button {
                                            makeupRequest = MakeupRequest(replacing: day)
                                        } label: {
                                            Label("Make-up", systemImage: "calendar.badge.plus")
                                        }
                                        .tint(.indigo)
                                    }
                                }
                        }
                    } header: {
                        Text(group.title)
                    } footer: {
                        if group.id == groups.last?.id {
                            Text("Turn a date on to mark it cancelled. No attendance, FS, or assignment is created for that day, and it is skipped when working out the next class. Swipe a cancelled date from the left to add its make-up.")
                        }
                    }
                }

                if !otherCancelledDays.isEmpty {
                    Section("Other cancelled dates") {
                        ForEach(otherCancelledDays, id: \.self) { day in
                            Toggle(isOn: binding(for: day)) {
                                Text(day.formatted(.dateTime.year().month(.abbreviated).day().weekday(.abbreviated)))
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .onAppear {
                guard let anchorDay else { return }
                proxy.scrollTo(anchorDay, anchor: .top)
            }
        }
    }

    private func dayRow(_ day: Date) -> some View {
        let isPast = day < calendar.startOfDay(for: .now)
        return Toggle(isOn: binding(for: day)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(day.formatted(.dateTime.month(.abbreviated).day().weekday(.abbreviated)))
                    .foregroundStyle(isPast ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(periodsText(for: day))
                    if isPast {
                        Text("past")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(for day: Date) -> Binding<Bool> {
        Binding(
            get: { course.isCancelled(on: day, calendar: calendar) },
            set: { isCancelled in
                course.setCancelled(isCancelled, on: day, calendar: calendar)
                try? context.save()
                Task { await TaskSyncCoordinator.shared.sync(context: context) }
            }
        )
    }
}
