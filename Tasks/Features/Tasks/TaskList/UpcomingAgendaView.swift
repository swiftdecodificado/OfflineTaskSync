import SwiftUI

struct UpcomingAgendaView: View {
    let tasks: [TaskSnapshot]
    let day: Date
    let now: Date
    let onEdit: (UUID) -> Void
    let onDeadline: (TaskSnapshot) -> Void
    let onCreateAtTime: (Date) -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var quarterHeight = Theme.Metrics.minTouchTarget
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth = Theme.Planner.timeColumnWidth

    var body: some View {
        let plan = AgendaTimelinePlan(tasks: tasks, day: day, calendar: calendar, now: now)
        if dynamicTypeSize.isAccessibilitySize {
            linearRows(plan)
        } else {
            let grid = plan.grid
            let height = max(grid.interval.duration / 900 * quarterHeight + quarterHeight / 2,
                             plan.placements.map { offset($0.start, grid: grid) + blockHeight($0) }.max() ?? 0)
            ViewThatFits(in: .horizontal) {
            GeometryReader { geometry in
                ZStack(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        ForEach(grid.starts, id: \.self) { date in
                            timeLine(date).frame(height: quarterHeight)
                        }
                    }
                    ForEach(plan.placements) { placement in
                        let available = max(Theme.Metrics.minTouchTarget,
                                            geometry.size.width - timeWidth - Theme.Spacing.xs)
                        let width = max(Theme.Metrics.minTouchTarget,
                                        (available - CGFloat(placement.columns - 1) * Theme.Spacing.xxs) / CGFloat(placement.columns))
                        TaskRow(task: placement.task, now: now, showNotes: false, showsCategory: false,
                                isTimeline: true, minimumHeight: blockHeight(placement), showsTime: false,
                                showsDate: false, showsReminder: false,
                                onDeadline: { onDeadline(placement.task) }, onEdit: { onEdit(placement.task.id) })
                            .frame(width: width, height: blockHeight(placement), alignment: .topLeading)
                            .offset(x: timeWidth + Theme.Spacing.xs + CGFloat(placement.column) * (width + Theme.Spacing.xxs),
                                    y: offset(placement.start, grid: grid))
                    }
                }
            }
            .frame(minWidth: timeWidth + Theme.Spacing.xs
                   + CGFloat(plan.placements.map(\.columns).max() ?? 1) * Theme.Planner.taskColumnMinWidth
                   + CGFloat(max(0, (plan.placements.map(\.columns).max() ?? 1) - 1)) * Theme.Spacing.xxs)
            .frame(height: height)
            linearRows(plan)
            }
        }
    }

    private func linearRows(_ plan: AgendaTimelinePlan) -> some View {
            ForEach(plan.entries) { entry in
                switch entry.content {
                case .time(let date): timeLine(date)
                case .task(let task):
                    TaskRow(task: task, now: now, showNotes: false, showsCategory: false,
                            showsDate: false, showsReminder: false,
                            onDeadline: { onDeadline(task) }, onEdit: { onEdit(task.id) })
                }
            }
    }

    private func offset(_ date: Date, grid: AgendaTimeGrid) -> CGFloat {
        max(0, date.timeIntervalSince(grid.interval.start) / 900 * quarterHeight) + quarterHeight / 2
    }

    private func blockHeight(_ placement: TaskTimelinePlacement) -> CGFloat {
        max(quarterHeight, placement.end.timeIntervalSince(placement.start) / 900 * quarterHeight)
    }

    private func timeLine(_ date: Date) -> some View {
        let format = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).hour().minute()
        return HStack(spacing: Theme.Spacing.xs) {
            Button { onCreateAtTime(date) } label: {
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(date, format: format)
                    if calendar.dateInterval(of: .day, for: date)?.duration ?? 0 > 24 * 60 * 60 {
                        Text(calendar.timeZone.abbreviation(for: date) ?? "")
                    }
                }
                .font(Theme.Typography.numeric)
                .foregroundStyle(Theme.textPrimary)
                .frame(width: timeWidth, alignment: .leading)
                .frame(minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Add task at \(date.formatted(format))"))
            .accessibilityValue(Text(date, format: format.day().month().timeZone()))
            .accessibilityIdentifier("agenda.slot.\(calendar.component(.hour, from: date)).\(calendar.component(.minute, from: date))")
            Button { onCreateAtTime(date) } label: {
                Rectangle().fill(Theme.background)
                    .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget)
                    .overlay {
                        Rectangle().fill(Theme.plannerLine).frame(height: Theme.Metrics.borderStroke)
                            .accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
        }
    }
}
