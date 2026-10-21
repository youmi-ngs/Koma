import SwiftUI

/// 時間割の上に出す「今日の授業」。持ち物と出席方法をひと目で確認できるようにする。
/// 2時間続きのコマは1件にまとめて「P1–P2 8:40–11:50」のように見せる。
struct TodayClassesSection: View {
    let semester: Semester
    let onSelectCourse: (Course) -> Void
    let onToggleCancelled: (Course) -> Void

    private var today: Date { .now }

    /// 同じ授業の連続したコマをひとまとまりにしたもの。
    struct Block: Identifiable {
        let id: String
        let course: Course
        /// 最初のコマ。教室などの代表として使う。
        let meeting: Meeting
        let periods: [Int]
        let slots: [PeriodSlot]
        let first: PeriodSlot?
        let last: PeriodSlot?
        /// 振替で足した回かどうか。
        let isMakeup: Bool

        var periodText: String {
            guard let firstPeriod = periods.first, let lastPeriod = periods.last else { return "" }
            return firstPeriod == lastPeriod ? "P\(firstPeriod)" : "P\(firstPeriod)–P\(lastPeriod)"
        }

        var timeText: String? {
            guard let first else { return nil }
            guard let last, last.index != first.index else { return first.rangeText }
            return "\(first.startText)–\(last.endText)"
        }
    }

    private var blocks: [Block] {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: today)
        var result: [Block] = []

        // 振替は時間割に無い回なので、今日ぶんを別に拾う。
        for course in semester.courses {
            for makeup in course.makeups where calendar.isDate(makeup.date, inSameDayAs: today) {
                guard let meeting = course.meetings.first else { continue }
                let slot = semester.period(at: makeup.period)
                result.append(Block(
                    id: "makeup-\(makeup.uid)",
                    course: course,
                    meeting: meeting,
                    periods: [makeup.period],
                    slots: [slot].compactMap { $0 },
                    first: slot,
                    last: slot,
                    isMakeup: true
                ))
            }
        }

        for course in semester.courses {
            let periods = course.meetings
                .filter { $0.weekday == weekday }
                .sorted { $0.period < $1.period }
            guard !periods.isEmpty else { continue }

            // 限が1つずつ繋がっているあいだは同じ授業時間とみなす。
            var run: [Meeting] = []
            func flush() {
                guard let head = run.first, let tail = run.last else { return }
                result.append(Block(
                    id: "\(course.persistentModelID)-\(head.period)",
                    course: course,
                    meeting: head,
                    periods: run.map(\.period),
                    slots: run.compactMap { semester.period(at: $0.period) },
                    first: semester.period(at: head.period),
                    last: semester.period(at: tail.period),
                    isMakeup: false
                ))
                run = []
            }
            for meeting in periods {
                if let previous = run.last, meeting.period != previous.period + 1 {
                    flush()
                }
                run.append(meeting)
            }
            flush()
        }

        return result.sorted { ($0.periods.first ?? 0) < ($1.periods.first ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .font(.headline)
                Spacer()
                Text(today.formatted(.dateTime.month(.abbreviated).day().weekday(.wide)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)

            if !semester.contains(today) {
                infoCard(
                    symbol: "calendar.badge.exclamationmark",
                    text: "Today is outside \(semester.name)."
                )
            } else if blocks.isEmpty {
                infoCard(symbol: "cup.and.saucer", text: "No classes today.")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                        Button {
                            onSelectCourse(block.course)
                        } label: {
                            TodayClassRow(block: block, isCancelled: isCancelledToday(block.course))
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                onToggleCancelled(block.course)
                            } label: {
                                Label(
                                    isCancelledToday(block.course) ? "Undo cancellation" : "Mark as cancelled",
                                    systemImage: isCancelledToday(block.course) ? "arrow.uturn.backward" : "calendar.badge.minus"
                                )
                            }
                        }

                        if index < blocks.count - 1 {
                            Divider().padding(.leading, 16)
                        }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private func isCancelledToday(_ course: Course) -> Bool {
        course.isCancelled(on: today)
    }

    private func infoCard(symbol: String, text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }
}

private struct TodayClassRow: View {
    let block: TodayClassesSection.Block
    let isCancelled: Bool

    private var course: Course { block.course }

    /// サイトで出席を押せる締め切り。出席はコマごとに押すので、続きのコマぶんも全部出す。
    private var checkInDeadlineText: String? {
        let window = max(1, course.attendanceWindowMinutes)
        let times = block.slots.map { slot -> String in
            let total = slot.startHour * 60 + slot.startMinute + window
            return TimeText.string(hour: (total / 60) % 24, minute: total % 60)
        }
        guard !times.isEmpty else { return nil }
        return times.joined(separator: " · ")
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(course.color.opacity(isCancelled ? 0.3 : 1))
                .frame(width: 4)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(block.periodText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(course.color)
                    if let timeText = block.timeText {
                        Text(timeText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                HStack(spacing: 8) {
                    Text(course.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isCancelled ? .secondary : .primary)
                        .strikethrough(isCancelled, color: .secondary)
                    if isCancelled {
                        Text("Cancelled")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.18), in: .capsule)
                            .foregroundStyle(.orange)
                    } else if block.isMakeup {
                        Text("Make-up")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Color.indigo.opacity(0.18), in: .capsule)
                            .foregroundStyle(.indigo)
                    }
                }

                let room = course.room(for: block.meeting)
                if !room.isEmpty || !course.teacher.isEmpty {
                    HStack(spacing: 10) {
                        if !room.isEmpty {
                            Label(room, systemImage: "mappin.and.ellipse")
                        }
                        if !course.teacher.isEmpty {
                            Label(course.teacher, systemImage: "person")
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                if !isCancelled {
                    Label(course.attendanceSummary, systemImage: "person.crop.circle.badge.checkmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !isCancelled, course.usesOnlineAttendance, let deadline = checkInDeadlineText {
                    Label(
                        block.slots.count > 1
                            ? "Check in each period by \(deadline)"
                            : "Check in by \(deadline)",
                        systemImage: "clock.badge.checkmark"
                    )
                    .font(.caption.weight(.medium))
                    .foregroundStyle(course.color)
                }

                if !course.itemList.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "shippingbox")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(course.itemList.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.top, 2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .contentShape(.rect)
    }
}
