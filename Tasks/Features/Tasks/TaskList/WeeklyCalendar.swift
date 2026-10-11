import SwiftUI

struct WeeklyCalendar: View {
    let now: Date
    let anchor: Date
    let selectedDay: Date?
    let tasks: [TaskSnapshot]
    let onSelect: (Date) -> Void
    let onMoveWeek: (Int) -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private let dayWidth = Theme.Metrics.minTouchTarget

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private var days: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? calendar.startOfDay(for: anchor)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        let pendingDays = Dictionary(grouping: tasks.filter { !$0.isDone && $0.dueDate != nil }) {
            calendar.startOfDay(for: $0.dueDate!)
        }.mapValues(\.count)
        ViewThatFits(in: .horizontal) {
            weekStrip(pendingDays: pendingDays)
                .simultaneousGesture(weekSwipe)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    weekStrip(pendingDays: pendingDays)
                        .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollIndicators(.visible)
                .accessibilityIdentifier("upcoming.week")
                .onAppear { proxy.scrollTo(selectedDay ?? anchor, anchor: .center) }
                .onChange(of: selectedDay) { _, day in
                    if let day { proxy.scrollTo(day, anchor: .center) }
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .contentShape(Rectangle())
        .foregroundStyle(Theme.textPrimary)
    }

    private var weekSwipe: some Gesture {
        DragGesture(minimumDistance: Theme.Spacing.xl).onEnded { value in
            let horizontal = value.translation.width
            guard abs(horizontal) > Theme.Metrics.minTouchTarget,
                  abs(horizontal) > abs(value.translation.height) * 2 else { return }
            onMoveWeek(horizontal < 0 ? 1 : -1)
        }
    }

    private func weekStrip(pendingDays: [Date: Int]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: dayWidth), spacing: Theme.Spacing.xxs), count: 7)) {
            ForEach(days, id: \.self) { day in
                dayButton(day, taskCount: pendingDays[calendar.startOfDay(for: day), default: 0])
                    .id(day)
            }
        }
        .frame(minWidth: dayWidth * 7 + Theme.Spacing.xxs * 6)
    }

    private func dayButton(_ day: Date, taskCount: Int) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let isSelected = selectedDay.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
        return Button { onSelect(day) } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Text(day, format: dateFormat.weekday(.abbreviated))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()

                Text(day, format: dateFormat.day())
                    .font(Theme.Typography.numeric.weight(isSelected ? .semibold : .regular))
                    .underline(isSelected && differentiateWithoutColor)
                    .foregroundStyle(isSelected ? Theme.Planner.selectedDayContent : Theme.textPrimary)
                    .frame(width: dayWidth - Theme.Spacing.xs, height: dayWidth - Theme.Spacing.xs)
                    .background(isSelected ? Theme.Planner.selectedDay : Color.clear, in: Circle())
                    .overlay {
                        if isToday {
                            Circle().strokeBorder(isSelected ? Theme.Planner.selectedDayContent : Theme.textPrimary, lineWidth: Theme.Metrics.checkboxStroke)
                        }
                    }

                Circle()
                    .fill(taskCount > 0 ? Theme.accent : Color.clear)
                    .frame(width: Theme.Spacing.xxs, height: Theme.Spacing.xxs)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(day, format: dateFormat.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue(Text(verbatim: [
            isToday ? AppLocalization.string("Today") : nil,
            AppLocalization.string("\(taskCount) tasks")
        ].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("upcoming.day.\(calendar.component(.weekday, from: day))")
        .accessibilityHint("Shows tasks for this day.")
        .accessibilityShowsLargeContentViewer {
            VStack {
                Text(day, format: dateFormat.weekday(.wide).day().month(.wide))
                Text("\(taskCount) tasks")
            }
        }
    }
}
