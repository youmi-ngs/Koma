import SwiftUI

/// 曜日 × 限の表。各マスは授業への入口、空きマスは追加への入口になる。
struct TimetableGrid: View {
    let semester: Semester
    let onSelectCourse: (Course) -> Void
    let onSelectEmptySlot: (TimetableSlot) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var weekdays: [Int] { semester.visibleWeekdays }
    private var periods: [PeriodSlot] { semester.sortedPeriods }

    /// 曜日と限から授業を引けるようにしておく。
    /// 今週に入っている振替も、その曜日のマスに出す。
    private var placements: [String: (course: Course, meeting: Meeting, isMakeup: Bool)] {
        var result: [String: (course: Course, meeting: Meeting, isMakeup: Bool)] = [:]
        for course in semester.courses {
            for meeting in course.meetings {
                result["\(meeting.weekday)-\(meeting.period)"] = (course, meeting, false)
            }
        }

        let calendar = Calendar.current
        for course in semester.courses {
            for makeup in course.makeups {
                guard let weekday = weekdayThisWeek(for: makeup.date, calendar: calendar) else { continue }
                guard let meeting = course.meetings.first else { continue }
                result["\(weekday)-\(makeup.period)"] = (course, meeting, true)
            }
        }
        return result
    }

    /// 今週に入っている日なら、その曜日を返す。
    private func weekdayThisWeek(for date: Date, calendar: Calendar) -> Int? {
        let today = calendar.startOfDay(for: .now)
        let day = calendar.startOfDay(for: date)
        guard let start = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: today) - 1), to: today),
              let end = calendar.date(byAdding: .day, value: 7, to: start)
        else { return nil }
        guard day >= start, day < end else { return nil }
        return calendar.component(.weekday, from: day)
    }

    private var gutterWidth: CGFloat {
        dynamicTypeSize >= .accessibility1 ? 58 : 34
    }

    /// 表は今週ぶんを出しているので、その曜日の実日付で休講を見る。
    private func dateThisWeek(for weekday: Int) -> Date? {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let offset = weekday - calendar.component(.weekday, from: today)
        return calendar.date(byAdding: .day, value: offset, to: today)
    }

    private var cellMinHeight: CGFloat {
        dynamicTypeSize >= .accessibility1 ? 120 : 84
    }

    var body: some View {
        let placements = placements

        VStack(spacing: 4) {
            headerRow

            ForEach(periods) { slot in
                HStack(alignment: .top, spacing: 4) {
                    timeGutter(for: slot)

                    ForEach(weekdays, id: \.self) { weekday in
                        if let placement = placements["\(weekday)-\(slot.index)"] {
                            courseCell(
                                course: placement.course,
                                meeting: placement.meeting,
                                slot: slot,
                                weekday: weekday,
                                isMakeup: placement.isMakeup
                            )
                        } else {
                            emptyCell(weekday: weekday, slot: slot)
                        }
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 4) {
            Color.clear
                .frame(width: gutterWidth, height: 1)

            ForEach(weekdays, id: \.self) { weekday in
                let isToday = weekday == Calendar.current.component(.weekday, from: .now)
                Text(WeekdayText.short(weekday))
                    .font(.subheadline.weight(isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? Color.accentColor : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background {
                        if isToday {
                            Capsule(style: .continuous)
                                .fill(Color.accentColor.opacity(0.14))
                        }
                    }
                    .accessibilityLabel(isToday ? "\(WeekdayText.full(weekday)), today" : WeekdayText.full(weekday))
            }
        }
    }

    private func timeGutter(for slot: PeriodSlot) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(slot.shortLabel)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
            Text(slot.startText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(slot.endText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: gutterWidth, alignment: .leading)
        .frame(minHeight: cellMinHeight, alignment: .top)
        .padding(.top, 6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(slot.label) \(slot.accessibilityRangeText)")
    }

    private func courseCell(
        course: Course,
        meeting: Meeting,
        slot: PeriodSlot,
        weekday: Int,
        isMakeup: Bool
    ) -> some View {
        let isCancelled = dateThisWeek(for: weekday).map { course.isCancelled(on: $0) } ?? false

        return Button {
            onSelectCourse(course)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.displayName)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isCancelled ? .secondary : .primary)
                    .strikethrough(isCancelled, color: .secondary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .minimumScaleFactor(0.7)
                    .allowsTightening(true)

                if isMakeup {
                    Text("Make-up")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.indigo)
                }

                let room = course.room(for: meeting)
                if !room.isEmpty {
                    // マスが狭いので、アイコンは置かず教室名に幅をすべて使う。
                    Text(room)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .minimumScaleFactor(0.7)
                        .allowsTightening(true)
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 5)
            .padding(.top, 9)
            .padding(.bottom, 5)
            .frame(minHeight: cellMinHeight, maxHeight: .infinity, alignment: .topLeading)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(course.color.opacity(isCancelled ? 0.07 : 0.16))
            }
            .overlay(alignment: .top) {
                // 色は横幅を食わないよう上端の帯にする。色だけに頼らない区別も兼ねる。
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(course.color.opacity(isCancelled ? 0.3 : 1))
                    .frame(height: 3)
                    .padding(.horizontal, 5)
                    .padding(.top, 4)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(WeekdayText.full(weekday)), \(slot.label), \(course.displayName)\(isCancelled ? ", cancelled" : "")")
        .accessibilityValue(course.room(for: meeting))
        .accessibilityHint("Opens course details")
    }

    private func emptyCell(weekday: Int, slot: PeriodSlot) -> some View {
        Button {
            onSelectEmptySlot(TimetableSlot(weekday: weekday, period: slot.index))
        } label: {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
                .frame(maxWidth: .infinity, minHeight: cellMinHeight, maxHeight: .infinity)
                .overlay {
                    Image(systemName: "plus")
                        .font(.footnote)
                        .foregroundStyle(.quaternary)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(WeekdayText.full(weekday)), \(slot.label), empty")
        .accessibilityHint("Adds a course")
    }
}
