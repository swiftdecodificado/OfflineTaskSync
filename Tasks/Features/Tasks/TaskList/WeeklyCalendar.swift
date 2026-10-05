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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    @ScaledMetric(relativeTo: .footnote) private var dayWidth = Theme.Metrics.minTouchTarget

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private var days: [Date] {
        let start = calendar.dateInterval(of: .weekOfYear, for: anchor)?.start ?? calendar.startOfDay(for: anchor)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    var body: some View {
        let pendingDays = Set(tasks.compactMap { task in
            task.isDone ? nil : task.dueDate.map { calendar.startOfDay(for: $0) }
        })
        VStack(spacing: Theme.Spacing.sm) {
            ViewThatFits(in: .horizontal) {
                weekStrip(pendingDays: pendingDays)
                    .simultaneousGesture(weekSwipe)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        weekStrip(pendingDays: pendingDays)
                            .fixedSize(horizontal: true, vertical: false)
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
        }
        .padding(.top, Theme.Spacing.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: Text("Previous week")) { onMoveWeek(-1) }
        .accessibilityAction(named: Text("Next week")) { onMoveWeek(1) }
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

    private func weekStrip(pendingDays: Set<Date>) -> some View {
        HStack(alignment: .top, spacing: dynamicTypeSize.isAccessibilitySize ? Theme.Spacing.md : Theme.Spacing.xxs) {
            ForEach(days, id: \.self) { day in
                dayButton(day, hasTasks: pendingDays.contains(calendar.startOfDay(for: day)))
                    .frame(minWidth: dayWidth, maxWidth: .infinity)
                    .id(day)
            }
        }
    }

    private func dayButton(_ day: Date, hasTasks: Bool) -> some View {
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let isSelected = selectedDay.map { calendar.isDate(day, inSameDayAs: $0) } ?? false
        return Button { onSelect(day) } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Text(day, format: dynamicTypeSize.isAccessibilitySize
                     ? dateFormat.weekday(.wide) : dateFormat.weekday(.abbreviated))
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize()

                Text(day, format: dateFormat.day())
                    .font(Theme.Typography.numeric.weight(isSelected ? .semibold : .regular))
                    .underline(isSelected && differentiateWithoutColor)
                    .foregroundStyle(isSelected ? Theme.Planner.selectedDayContent : Theme.textPrimary)
                    .frame(width: dayWidth, height: dayWidth)
                    .background(isSelected ? Theme.Planner.selectedDay : Theme.surfaceSecondary, in: Circle())
                    .overlay {
                        if isToday {
                            Circle().strokeBorder(isSelected ? Theme.Planner.selectedDayContent : Theme.textPrimary, lineWidth: Theme.Metrics.checkboxStroke)
                        }
                    }

                Circle()
                    .fill(Theme.textSecondary)
                    .frame(width: Theme.Spacing.xxs, height: Theme.Spacing.xxs)
                    .opacity(hasTasks ? 1 : 0)
            }
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(day, format: dateFormat.weekday(.wide).day().month(.wide).year()))
        .accessibilityValue(Text(verbatim: [
            isToday ? AppLocalization.string("Today") : nil,
            hasTasks ? AppLocalization.string("Has tasks") : AppLocalization.string("No tasks")
        ].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("upcoming.day.\(calendar.component(.weekday, from: day))")
    }
}
