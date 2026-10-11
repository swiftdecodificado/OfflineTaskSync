import SwiftUI

struct UpcomingAgendaView: View {
    let tasks: [TaskSnapshot]
    let day: Date
    let now: Date
    var showsTimeGrid = false
    var showsPlanningActions = true
    let onOpen: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onDeadline: (TaskSnapshot) -> Void
    let onCreateAtTime: (Date) -> Void
    let onCreateOnDay: () -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingTimeGrid = false
    @State private var pendingGridAction: GridAction?

    private enum GridAction {
        case open(UUID), edit(UUID), deadline(TaskSnapshot), create(Date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            let untimed = tasks.filter { $0.dueTime == nil }
            let timed = tasks.filter { $0.dueTime != nil }
            let schedule = CalendarDaySchedule(tasks: tasks, day: day, calendar: calendar)
            if showsPlanningActions && schedule.scheduledDuration > 0 {
                Text("\(Int(schedule.scheduledDuration / 60)) min agendados")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !untimed.isEmpty {
                Text("Sem horário")
                    .font(Theme.Typography.sectionLabel)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                ForEach(untimed) { task in taskRow(task) }
            }
            if !timed.isEmpty {
                ForEach(timed) { task in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        if schedule.overlappingTaskIDs.contains(task.id) {
                            Label("Horários sobrepostos", systemImage: "exclamationmark.circle")
                                .font(Theme.Typography.footnote)
                                .foregroundStyle(Theme.error)
                        }
                        taskRow(task)
                    }
                }
            }
            if tasks.isEmpty {
                Text("No tasks for this date")
                    .font(Theme.Typography.body)
                    .foregroundStyle(Theme.textSecondary)
            }
            if showsPlanningActions {
                let actionLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                    : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))
                actionLayout {
                    Button(action: onCreateOnDay) {
                        Label("New task", systemImage: "plus")
                            .frame(minHeight: Theme.Metrics.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("upcoming.addDay.\(day.timeIntervalSince1970)")
                    if showsTimeGrid {
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        Button { showingTimeGrid = true } label: {
                            Label("Grade de horários", systemImage: "clock")
                                .frame(minHeight: Theme.Metrics.minTouchTarget)
                                .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("upcoming.timeGrid")
                    }
                }
                .font(Theme.Typography.metadataEmphasis)
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)
            }
        }
        .sheet(isPresented: $showingTimeGrid, onDismiss: performGridAction) {
            NavigationStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        AgendaTimeGridView(tasks: tasks, day: day, now: now, onOpen: { id in
                            pendingGridAction = .open(id)
                            showingTimeGrid = false
                        }, onEdit: { id in
                            pendingGridAction = .edit(id)
                            showingTimeGrid = false
                        }, onDeadline: { task in
                            pendingGridAction = .deadline(task)
                            showingTimeGrid = false
                        }, onCreateAtTime: { date in
                            pendingGridAction = .create(date)
                            showingTimeGrid = false
                        })
                        .padding(Theme.pageMargin)
                    }
                    .swipeActionsContainer()
                    .onAppear {
                        if calendar.isDate(day, inSameDayAs: now),
                           let hour = calendar.dateInterval(of: .hour, for: now)?.start {
                            proxy.scrollTo(hour, anchor: .top)
                        }
                    }
                }
                .background(Theme.background)
                .navigationTitle("Grade de horários")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingTimeGrid = false }
                    }
                }
            }
        }
    }

    private func performGridAction() {
        let action = pendingGridAction
        pendingGridAction = nil
        switch action {
        case .open(let id): onOpen(id)
        case .edit(let id): onEdit(id)
        case .deadline(let task): onDeadline(task)
        case .create(let date): onCreateAtTime(date)
        case nil: break
        }
    }

    private func taskRow(_ task: TaskSnapshot) -> some View {
        TaskRow(task: task, now: now, showNotes: false, usesCompletionCircle: true, showsCategory: false,
                showsDate: false, showsReminder: false, onOpen: { onOpen(task.id) },
                onDeadline: { onDeadline(task) }, onEdit: { onEdit(task.id) })
    }
}

struct AgendaTimeGridView: View {
    let tasks: [TaskSnapshot]
    let day: Date
    let now: Date
    let onOpen: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onDeadline: (TaskSnapshot) -> Void
    let onCreateAtTime: (Date) -> Void
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var quarterHeight = Theme.Metrics.minTouchTarget
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth = Theme.Planner.timeColumnWidth

    var body: some View {
        let plan = AgendaTimelinePlan(tasks: tasks, day: day, calendar: calendar)
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
                            timeLine(date).frame(height: quarterHeight).id(date)
                        }
                    }
                    ForEach(plan.placements) { placement in
                        let available = max(Theme.Metrics.minTouchTarget,
                                            geometry.size.width - timeWidth - Theme.Spacing.xs)
                        let width = max(Theme.Metrics.minTouchTarget,
                                        (available - CGFloat(placement.columns - 1) * Theme.Spacing.xxs) / CGFloat(placement.columns))
                        TaskRow(task: placement.task, now: now, showNotes: false, usesCompletionCircle: true, showsCategory: false,
                                isTimeline: true, minimumHeight: blockHeight(placement), showsTime: false,
                                showsDate: false, showsReminder: false, onOpen: { onOpen(placement.task.id) },
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
                case .time(let date): timeLine(date).id(date)
                case .task(let task):
                    TaskRow(task: task, now: now, showNotes: false, usesCompletionCircle: true, showsCategory: false,
                            showsDate: false, showsReminder: false, onOpen: { onOpen(task.id) },
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
