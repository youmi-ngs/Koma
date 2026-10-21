import PhotosUI
import SwiftData
import SwiftUI

/// 時間割のスクリーンショットからコマを読み取って取り込む。
/// 読み取りは端末内で完結し、画像はどこにも送らない。
struct TimetableImportView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    let semester: Semester

    @State private var pickerItem: PhotosPickerItem?
    @State private var isReading = false
    @State private var errorMessage: String?
    @State private var detected: [DetectedCourse] = []
    @State private var excluded: Set<UUID> = []

    private var chosen: [DetectedCourse] {
        detected.filter { !excluded.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isReading {
                    ProgressView("Reading the image…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if detected.isEmpty {
                    startState
                } else {
                    resultList
                }
            }
            .navigationTitle("Import timetable")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !detected.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(chosen.count)") { addChosen() }
                            .disabled(chosen.isEmpty)
                    }
                }
            }
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                read(item)
            }
            .alert("Could not read it", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private var startState: some View {
        ContentUnavailableView {
            Label("Pick a screenshot", systemImage: "text.viewfinder")
        } description: {
            Text("A screenshot of your portal's timetable table works best. The weekday row and the period numbers down the side are what the grid is read from.")
        } actions: {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Text("Choose Image")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var resultList: some View {
        List {
            Section {
                ForEach($detected) { $course in
                    HStack(spacing: 12) {
                        Button {
                            toggle(course.id)
                        } label: {
                            Image(systemName: excluded.contains(course.id) ? "circle" : "checkmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(excluded.contains(course.id) ? Color.secondary : Color.accentColor)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Course name", text: $course.name)
                            Text(course.slotSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("Found \(detected.count)")
            } footer: {
                Text("Names come from the screenshot, so anything the portal cut off is cut off here too. Fix them now or edit the course later.")
            }

            Section {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Choose a different image", systemImage: "photo")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 操作

    private func toggle(_ id: UUID) {
        if excluded.contains(id) {
            excluded.remove(id)
        } else {
            excluded.insert(id)
        }
    }

    private func read(_ item: PhotosPickerItem) {
        isReading = true
        detected = []
        excluded = []

        Task {
            defer { isReading = false }
            do {
                guard
                    let data = try await item.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else {
                    errorMessage = TimetableImporter.ImportError.unreadableImage.localizedDescription
                    return
                }
                detected = try await TimetableImporter.detect(in: image)
                if detected.isEmpty {
                    errorMessage = TimetableImporter.ImportError.noGridFound.localizedDescription
                }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func addChosen() {
        var colorIndex = semester.courses.count
        for detectedCourse in chosen {
            let name = detectedCourse.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }

            let course = Course(name: name, colorIndex: colorIndex, semester: semester)
            context.insert(course)
            colorIndex += 1

            for slot in detectedCourse.slots {
                let meeting = Meeting(weekday: slot.weekday, period: slot.period)
                meeting.course = course
                context.insert(meeting)
            }
        }

        try? context.save()
        dismiss()

        Task {
            await NotificationManager.shared.requestAuthorizationIfNeeded()
            await TaskSyncCoordinator.shared.sync(context: context)
        }
    }
}
