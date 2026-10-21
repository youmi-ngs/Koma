import SwiftUI

/// やること1件の行。チェックは左端、内容は1行目に置く標準的なリスト行の形。
struct TaskRow: View {
    let task: TaskItem
    var showsCourseName: Bool = true
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.isDone ? Color.accentColor : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(task.isDone ? "Mark as not done" : "Mark as done")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: task.kind.symbolName)
                        .font(.caption)
                        .foregroundStyle(task.course?.color ?? .secondary)
                    Text(task.title)
                        .font(.body.weight(.medium))
                        .strikethrough(task.isDone, color: .secondary)
                        .foregroundStyle(task.isDone ? .secondary : .primary)
                    if task.attendanceOutcome == .absent {
                        Text("Absent")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.16), in: .capsule)
                            .foregroundStyle(.red)
                    }
                }

                if showsCourseName {
                    Text(task.courseName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Text(task.dueText)
                        .monospacedDigit()
                    // どのコマのぶんかは、授業を指す側に添える。
                    if task.kind == .attendance, let deadline = task.attendanceDeadline {
                        if let periodText = task.periodText {
                            Text("·")
                            Text(periodText)
                        }
                        Text("·")
                        Text("open until \(deadline.formatted(date: .omitted, time: .shortened))")
                    } else if task.kind == .exam {
                        if let room = task.exam?.room, !room.isEmpty {
                            Text("·")
                            Text(room)
                        }
                    } else if !task.isManual, task.kind.isRecurring {
                        // 試験や最終課題は授業の回に対応しないので、授業名の参照は出さない。
                        Text("·")
                        Text(classReferenceText)
                    }
                }
                .font(.caption)
                .foregroundStyle(task.isOverdue ? Color.red : .secondary)

                if !task.memo.isEmpty {
                    Text(task.memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: task.isDone ? "Mark as not done" : "Mark as done", onToggle)
    }

    /// 「Fri, Oct 9 P2 class」のように、どの回のものかを1つにまとめた文。
    private var classReferenceText: String {
        guard let periodText = task.periodText else { return "\(task.classDateText) class" }
        return "\(task.classDateText) \(periodText) class"
    }

    private var accessibilityText: String {
        var parts = [task.title]
        if let periodText = task.periodText { parts.append(periodText) }
        if showsCourseName { parts.append(task.courseName) }
        parts.append(task.dueText)
        if let outcome = task.attendanceOutcome { parts.append(outcome.title) }
        if task.isOverdue { parts.append("Overdue") }
        if task.isDone { parts.append("Completed") }
        return parts.joined(separator: ", ")
    }
}
