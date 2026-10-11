import SwiftUI

struct MonthlyCalendar: View {
    let now: Date
    let anchor: Date
    let tasks: [TaskSnapshot]
    let onSelect: (Date) -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private var format: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private var dates: [Date] {
        guard let month = calendar.dateInterval(of: .month, for: anchor),
              let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start),
              let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end),
              let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay) else { return [] }
        let count = calendar.dateComponents([.day], from: firstWeek.start, to: lastWeek.end).day ?? 0
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: firstWeek.start) }
    }

    var body: some View {
        let dates = dates
        let pendingDays = Dictionary(grouping: tasks.filter { !$0.isDone && $0.dueDate != nil }) {
            calendar.startOfDay(for: $0.dueDate!)
        }.mapValues(\.count)
        ViewThatFits(in: .horizontal) {
            grid(dates, pendingDays: pendingDays)
            ScrollView(.horizontal) {
                grid(dates, pendingDays: pendingDays)
            }
            .scrollIndicators(.visible)
            .accessibilityIdentifier("upcoming.month")
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func grid(_ dates: [Date], pendingDays: [Date: Int]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: Theme.Metrics.minTouchTarget),
                                                   spacing: Theme.Spacing.xxs), count: 7),
                  spacing: Theme.Spacing.xxs) {
            ForEach(Array(dates.prefix(7)), id: \.self) { date in
                Text(date, format: format.weekday(.narrow))
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityHidden(true)
            }
            ForEach(dates, id: \.self) { date in
                if calendar.isDate(date, equalTo: anchor, toGranularity: .month) {
                    dayButton(date, taskCount: pendingDays[calendar.startOfDay(for: date), default: 0])
                } else {
                    Color.clear.frame(height: Theme.Metrics.minTouchTarget).accessibilityHidden(true)
                }
            }
        }
        .frame(minWidth: Theme.Metrics.minTouchTarget * 7 + Theme.Spacing.xxs * 6)
    }

    private func dayButton(_ date: Date, taskCount: Int) -> some View {
        let isToday = calendar.isDate(date, inSameDayAs: now)
        let isSelected = calendar.isDate(date, inSameDayAs: anchor)
        return Button { onSelect(date) } label: {
            VStack(spacing: Theme.Spacing.xxs) {
                Text(date, format: format.day())
                    .font(Theme.Typography.body)
                    .fontWeight(isToday || isSelected ? .semibold : .regular)
                    .underline(isSelected && differentiateWithoutColor)
                    .frame(width: Theme.Metrics.minTouchTarget - Theme.Spacing.xs,
                           height: Theme.Metrics.minTouchTarget - Theme.Spacing.xs)
                    .foregroundStyle(isSelected ? Theme.Planner.selectedDayContent : Theme.textPrimary)
                    .background(isSelected ? Theme.Planner.selectedDay : Color.clear, in: Circle())
                    .overlay {
                        if isToday {
                            Circle().strokeBorder(isSelected ? Theme.Planner.selectedDayContent : Theme.accent,
                                                  lineWidth: Theme.Metrics.borderStroke)
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
        .accessibilityLabel(Text(date, format: format.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue(Text("\(taskCount) tasks"))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Shows tasks for this day.")
        .accessibilityIdentifier("upcoming.monthDay.\(calendar.component(.day, from: date))")
        .accessibilityShowsLargeContentViewer {
            VStack {
                Text(date, format: format.weekday(.wide).day().month(.wide))
                Text("\(taskCount) tasks")
            }
        }
    }
}
