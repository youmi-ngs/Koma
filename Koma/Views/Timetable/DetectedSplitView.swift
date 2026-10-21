import SwiftUI

/// 読み取った1件を、コマを選んで分ける。
/// ポータルが名前を切り詰めるせいで、別々の授業が同じ名前の1件になることがある
/// （「Core En…」が6コマあって、実は3授業ということが起きる）。
struct DetectedSplitView: View {
    @Environment(\.dismiss) private var dismiss

    let course: DetectedCourse
    let onSplit: (_ slots: [TimetableSlot], _ name: String) -> Void

    @State private var selected: Set<String> = []
    @State private var name: String = ""

    private var chosen: [TimetableSlot] {
        course.slots.filter { selected.contains($0.id) }
    }

    private var canSplit: Bool {
        !chosen.isEmpty
            && chosen.count < course.slots.count
            && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("New name", text: $name)
                } header: {
                    Text("Split off as")
                } footer: {
                    Text("The slots you pick move to a row of their own. The rest stay as \(course.name). Repeat this to separate a third course.")
                }

                Section("Slots") {
                    ForEach(course.slots) { slot in
                        Button {
                            toggle(slot)
                        } label: {
                            HStack {
                                Image(systemName: selected.contains(slot.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selected.contains(slot.id) ? Color.accentColor : .secondary)
                                Text("\(WeekdayText.short(slot.weekday)) · P\(slot.period)")
                                    .foregroundStyle(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .navigationTitle("Split \(course.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Split") {
                        onSplit(chosen, name.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(!canSplit)
                }
            }
            .onAppear {
                if name.isEmpty { name = course.name }
            }
        }
    }

    private func toggle(_ slot: TimetableSlot) {
        if selected.contains(slot.id) {
            selected.remove(slot.id)
        } else {
            selected.insert(slot.id)
        }
    }
}
