import SwiftData
import SwiftUI

/// 2つの授業をひとつにまとめる。
/// 取り込みで別々に読まれたものや、分けすぎたものを戻すのに使う。
/// 追加済みの授業は名前を揃えても勝手にはまとまらないので、ここで明示的に行う。
struct CourseMergeView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Bindable var course: Course

    @State private var selected: Course?

    private var candidates: [Course] {
        (course.semester?.courses ?? [])
            .filter { $0.persistentModelID != course.persistentModelID }
            .sorted { $0.displayName < $1.displayName }
    }

    /// 取り込んだときに分かれてしまったものを見つけやすいよう、似た名前を先に出す。
    private var suggested: [Course] {
        candidates.filter { other in
            let a = course.displayName, b = other.displayName
            return a.hasPrefix(b) || b.hasPrefix(a)
        }
    }

    private var others: [Course] {
        let ids = Set(suggested.map(\.persistentModelID))
        return candidates.filter { !ids.contains($0.persistentModelID) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if candidates.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to Merge", systemImage: "square.on.square")
                    } description: {
                        Text("This semester has no other course to merge into \(course.displayName).")
                    }
                } else {
                    list
                }
            }
            .navigationTitle("Merge into \(course.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Merge") { merge() }
                        .disabled(selected == nil)
                }
            }
        }
    }

    private var list: some View {
        List {
            if !suggested.isEmpty {
                Section("Similar name") {
                    ForEach(suggested) { other in row(other) }
                }
            }
            Section {
                ForEach(others) { other in row(other) }
            } header: {
                Text(suggested.isEmpty ? "Courses" : "Other courses")
            } footer: {
                Text("The course you pick is absorbed into \(course.displayName): its slots and exams move over and it is removed. Its finished to-dos go with it, and the to-dos for the combined slots are rebuilt.")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func row(_ other: Course) -> some View {
        Button {
            selected = (selected?.persistentModelID == other.persistentModelID) ? nil : other
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected?.persistentModelID == other.persistentModelID
                      ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected?.persistentModelID == other.persistentModelID
                                     ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(other.displayName)
                        .foregroundStyle(.primary)
                    Text(other.scheduleSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func merge() {
        guard let other = selected else { return }

        // 同じ曜日・限がすでにあるぶんは持ってこない。
        var taken = Set(course.meetings.map { "\($0.weekday)-\($0.period)" })
        for meeting in other.meetings {
            let key = "\(meeting.weekday)-\(meeting.period)"
            guard taken.insert(key).inserted else { continue }
            meeting.course = course
        }
        for exam in other.exams {
            exam.course = course
        }

        context.delete(other)
        try? context.save()
        dismiss()
        Task { await TaskSyncCoordinator.shared.sync(context: context) }
    }
}
