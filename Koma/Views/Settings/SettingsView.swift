import SwiftData
import SwiftUI
import UIKit

/// 設定タブ。学期・コマの時間・通知の3つをまとめている。
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL

    @Query(sort: \Semester.startDate, order: .reverse) private var semesters: [Semester]

    @State private var notifications = NotificationManager.shared
    @State private var isAddingSemester = false
    @State private var semesterPendingDeletion: Semester?

    private var currentSemester: Semester? { SemesterPicker.current(from: semesters) }

    var body: some View {
        NavigationStack {
            List {
                semesterSection
                if let currentSemester {
                    timetableSection(for: currentSemester)
                }
                notificationSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .sheet(isPresented: $isAddingSemester) {
                SemesterEditView(mode: .create)
            }
            .confirmationDialog(
                "Delete “\(semesterPendingDeletion?.name ?? "")”?",
                isPresented: Binding(
                    get: { semesterPendingDeletion != nil },
                    set: { if !$0 { semesterPendingDeletion = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let semester = semesterPendingDeletion { delete(semester) }
                }
                Button("Cancel", role: .cancel) { semesterPendingDeletion = nil }
            } message: {
                Text("Its courses and to-dos will be deleted too.")
            }
            .task {
                await notifications.refreshAuthorizationStatus()
            }
        }
    }

    // MARK: - セクション

    private var semesterSection: some View {
        Section {
            ForEach(semesters) { semester in
                NavigationLink {
                    SemesterEditView(mode: .edit(semester))
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(semester.name)
                            Text(semester.dateRangeText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if semester.persistentModelID == currentSemester?.persistentModelID {
                            Text("Showing")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        semesterPendingDeletion = semester
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    Button {
                        duplicate(semester)
                    } label: {
                        Label("Duplicate", systemImage: "plus.square.on.square")
                    }
                    .tint(.indigo)
                }
            }

            Button {
                isAddingSemester = true
            } label: {
                Label("Add Semester", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Semesters")
        } footer: {
            Text("Timetables are saved per semester. Switching semesters shows only that semester's courses. Swipe a semester to duplicate it, which copies its courses and slots but not its to-dos.")
        }
    }

    private func timetableSection(for semester: Semester) -> some View {
        Section {
            NavigationLink {
                PeriodEditView(semester: semester)
            } label: {
                LabeledContent("Period Times") {
                    Text("\(semester.periods.count) periods")
                }
            }

            Toggle("Show Saturday", isOn: Binding(
                get: { semester.showsSaturday },
                set: { semester.showsSaturday = $0; try? context.save() }
            ))
            Toggle("Show Sunday", isOn: Binding(
                get: { semester.showsSunday },
                set: { semester.showsSunday = $0; try? context.save() }
            ))
        } header: {
            Text("Timetable · \(semester.name)")
        } footer: {
            Text("Period start times are the basis for class dates and reminders.")
        }
    }

    private var notificationSection: some View {
        Section {
            LabeledContent("Notifications") {
                Text(statusText)
                    .foregroundStyle(statusColor)
            }

            switch notifications.authorizationStatus {
            case .notDetermined:
                Button("Allow Notifications") {
                    Task {
                        await notifications.requestAuthorizationIfNeeded()
                        await TaskSyncCoordinator.shared.refreshNotifications(context: context)
                    }
                }
            case .denied:
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            default:
                Button("Rebuild Reminders") {
                    Task { await TaskSyncCoordinator.shared.sync(context: context) }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text("Attendance, FS, and assignment notifications are created automatically from each course's settings. The next 60 are registered on this device.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version") {
                Text(appVersion)
            }
            Text("Keep track of your university timetable, attendance check-ins, FS, and assignments.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var statusText: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied: return "Off"
        case .notDetermined: return "Not set"
        @unknown default: return "Unknown"
        }
    }

    private var statusColor: Color {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .secondary
        case .denied: return .red
        default: return .secondary
        }
    }

    /// 授業とコマを引き継いだ学期を作る。日付と名前はあとから直す前提。
    private func duplicate(_ semester: Semester) {
        withAnimation {
            SemesterDuplicator.duplicate(semester, in: context)
        }
        Task { await TaskSyncCoordinator.shared.sync(context: context) }
    }

    private func delete(_ semester: Semester) {
        let wasCurrent = semester.persistentModelID == currentSemester?.persistentModelID
        context.delete(semester)
        try? context.save()
        semesterPendingDeletion = nil

        if wasCurrent, let next = SemesterPicker.current(from: semesters.filter { $0.persistentModelID != semester.persistentModelID }) {
            SemesterPicker.makeCurrent(next, among: semesters)
            try? context.save()
        }

        Task { await TaskSyncCoordinator.shared.refreshNotifications(context: context) }
    }
}

#Preview {
    SettingsView()
        .modelContainer(PreviewData.container)
}
