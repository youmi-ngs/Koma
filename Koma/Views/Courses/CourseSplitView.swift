import SwiftData
import SwiftUI

/// 登録済みの授業から、選んだコマを別の授業に分ける。
/// 時間割の表記が同じで中身が別、という授業をあとから分けられるようにするため。
struct CourseSplitView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var course: Course

    @State private var selected: Set<PersistentIdentifier> = []
    @State private var name: String = ""

    private var moving: [Meeting] {
        course.sortedMeetings.filter { selected.contains($0.persistentModelID) }
    }

    private var canSplit: Bool {
        !moving.isEmpty
            && moving.count < course.meetings.count
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("New course name", text: $name)
                } header: {
                    Text("Split off as")
                } footer: {
                    Text("The slots you pick move to a new course that starts with the same settings as \(course.displayName). Its to-dos are rebuilt for the new course.")
                }

                Section("Slots") {
                    ForEach(course.sortedMeetings) { meeting in
                        Button {
                            toggle(meeting)
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(meeting.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(meeting.persistentModelID) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(meeting.slotText)
                                        .foregroundStyle(.primary)
                                    let room = course.room(for: meeting)
                                    if !room.isEmpty {
                                        Text(room)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Split course")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") { split() }
                        .disabled(!canSplit)
                }
            }
            .onAppear {
                if name.isEmpty { name = course.displayName }
            }
        }
    }

    private func toggle(_ meeting: Meeting) {
        let id = meeting.persistentModelID
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
    }

    private func split() {
        let moving = moving
        guard !moving.isEmpty, moving.count < course.meetings.count else { return }

        let newCourse = Course(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            colorIndex: course.colorIndex + 1,
            semester: course.semester
        )
        newCourse.copySettings(from: course)
        context.insert(newCourse)

        for meeting in moving {
            meeting.course = newCourse
        }

        try? context.save()
        dismiss()
        Task { await TaskSyncCoordinator.shared.sync(context: context) }
    }
}
