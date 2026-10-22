import SwiftUI

/// 学期の途中の休み（冬休みなど）を1件編集する。
struct TermBreakEditView: View {
    @Environment(\.dismiss) private var dismiss

    let existing: TermBreak?
    let onSave: (TermBreak) -> Void
    let onDelete: (() -> Void)?

    @State private var name: String
    @State private var start: Date
    @State private var end: Date

    init(existing: TermBreak?, onSave: @escaping (TermBreak) -> Void, onDelete: (() -> Void)? = nil) {
        self.existing = existing
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: existing?.name ?? "")
        _start = State(initialValue: existing?.start ?? .now)
        _end = State(initialValue: existing?.end ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Winter break)", text: $name)
                    DatePicker("First day off", selection: $start, displayedComponents: .date)
                    DatePicker("Last day off", selection: $end, in: start..., displayedComponents: .date)
                } footer: {
                    Text("No classes are held on these days, for any course in the semester. Both days are included.")
                }

                if let onDelete {
                    Section {
                        Button("Delete", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(existing == nil ? "Add break" : "Edit break")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save") {
                        onSave(TermBreak(
                            id: existing?.id ?? UUID(),
                            name: name.trimmingCharacters(in: .whitespaces),
                            start: start,
                            end: end
                        ))
                        dismiss()
                    }
                    .disabled(start > end)
                }
            }
        }
    }
}
