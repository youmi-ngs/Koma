import SwiftData
import SwiftUI

/// 時間割の空きコマ。授業追加シートに渡す。
struct TimetableSlot: Identifiable, Hashable {
    var weekday: Int
    var period: Int

    var id: String { "\(weekday)-\(period)" }
}

/// 時間割タブ。学期ごとの表と、今日の授業の要約を表示する。
struct TimetableView: View {
    /// シートはひとつの状態にまとめ、同時に複数開かないようにする。
    private enum SheetRoute: Identifiable {
        case newCourse(TimetableSlot?)
        case newSemester
        case importImage

        var id: String {
            switch self {
            case let .newCourse(slot): return "course-\(slot?.id ?? "any")"
            case .newSemester: return "semester"
            case .importImage: return "import"
            }
        }
    }

    @Environment(\.modelContext) private var context
    @Query(sort: \Semester.startDate, order: .reverse) private var semesters: [Semester]

    @State private var selectedCourse: Course?
    @State private var route: SheetRoute?

    private var semester: Semester? { SemesterPicker.current(from: semesters) }

    var body: some View {
        NavigationStack {
            Group {
                if let semester {
                    content(for: semester)
                } else {
                    ContentUnavailableView {
                        Label("No Semester Yet", systemImage: "calendar.badge.plus")
                    } description: {
                        Text("Create a semester to start building your timetable.")
                    } actions: {
                        Button("Add Semester") { route = .newSemester }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle(semester?.name ?? "Timetable")
            .toolbar { toolbarContent }
            .navigationDestination(item: $selectedCourse) { course in
                CourseDetailView(course: course)
            }
            .sheet(item: $route) { route in
                switch route {
                case let .newCourse(slot):
                    if let semester {
                        CourseEditView(mode: .create(semester: semester, slot: slot))
                    }
                case .newSemester:
                    SemesterEditView(mode: .create)
                case .importImage:
                    if let semester {
                        TimetableImportView(semester: semester)
                    }
                }
            }
        }
    }

    private func content(for semester: Semester) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                TodayClassesSection(
                    semester: semester,
                    onSelectCourse: { course in selectedCourse = course },
                    onToggleCancelled: toggleCancelledToday,
                    onRecord: recordAttendance
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("This Week")
                        .font(.headline)
                        .padding(.horizontal, 4)

                    TimetableGrid(
                        semester: semester,
                        onSelectCourse: { course in selectedCourse = course },
                        onSelectEmptySlot: { slot in route = .newCourse(slot) }
                    )
                    // 表だけは左右の余白を詰めて、1コマぶんの幅を稼ぐ。
                    .padding(.horizontal, -6)
                }

                if semester.courses.isEmpty {
                    Text("Tap an empty slot to add a course.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal, 4)
                }
            }
            .padding(16)
        }
        // 中身の高さが確定したあとも先頭を保つ。
        .defaultScrollAnchor(.top)
        .background(Color(.systemGroupedBackground))
    }

    /// 今日のその回の出席を記録する。連続コマはまとめて付けられる。
    private func recordAttendance(_ course: Course, periods: [Int], as outcome: AttendanceOutcome) {
        let calendar = Calendar.current
        let targets = course.tasks.filter {
            $0.kind == .attendance
                && calendar.isDateInToday($0.classDate)
                && periods.contains($0.period)
        }
        guard !targets.isEmpty else { return }
        for task in targets { task.record(outcome) }
        try? context.save()
        Task { await TaskSyncCoordinator.shared.refreshNotifications(context: context) }
    }

    /// 今日の回を休講にする／戻す。
    private func toggleCancelledToday(_ course: Course) {
        let today = Date.now
        course.setCancelled(!course.isCancelled(on: today), on: today)
        try? context.save()
        Task { await TaskSyncCoordinator.shared.sync(context: context) }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Menu {
                if !semesters.isEmpty {
                    Section("Switch Semester") {
                        ForEach(semesters) { item in
                            Button {
                                SemesterPicker.makeCurrent(item, among: semesters)
                                try? context.save()
                            } label: {
                                if item.persistentModelID == semester?.persistentModelID {
                                    Label(item.name, systemImage: "checkmark")
                                } else {
                                    Text(item.name)
                                }
                            }
                        }
                    }
                }
                Button {
                    route = .newSemester
                } label: {
                    Label("Add Semester", systemImage: "plus")
                }
            } label: {
                Label("Semester", systemImage: "calendar")
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button {
                    route = .newCourse(nil)
                } label: {
                    Label("Add Course", systemImage: "plus")
                }
                Button {
                    route = .importImage
                } label: {
                    Label("Import from Image", systemImage: "text.viewfinder")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .disabled(semester == nil)
        }
    }
}

#Preview {
    TimetableView()
        .modelContainer(PreviewData.container)
}
