import SwiftUI

struct UpcomingView: View {
    let now: Date
    @Binding var selectedDay: Date?
    @Binding var showingDatePicker: Bool
    let onCreateAtTime: (Date) -> Void
    let onCreateOnDay: (Date) -> Void
    let onProfile: () -> Void
    let onReminders: () -> Void
    let onOpen: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onDeadline: (TaskSnapshot) -> Void
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var period: CalendarPeriod = .week
    @State private var pickerDate = Date.now

    private var day: Date { calendar.startOfDay(for: selectedDay ?? now) }
    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    var body: some View {
        let plan = CalendarPlan(tasks: viewModel.tasks, day: day, period: period, calendar: calendar)
        let scheduledDays = plan.days.filter { !$0.tasks.isEmpty }
        let dailyTasks = TaskQuery(collection: .upcoming, selectedDay: day)
            .results(in: viewModel.tasks, now: now, calendar: calendar)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                periodPicker
                calendarNavigation
                if period == .month {
                    MonthlyCalendar(now: now, anchor: day, tasks: viewModel.tasks, onSelect: selectDay)
                } else if period == .week {
                    WeeklyCalendar(now: now, anchor: day, selectedDay: day, tasks: viewModel.tasks,
                                   onSelect: openDay, onMoveWeek: { move(.week, by: $0) })
                }
                PersistenceErrorBanner()
                if !viewModel.hasLoadedTasks {
                    ProgressView("Loading tasks")
                } else if period == .week {
                    if scheduledDays.isEmpty {
                        emptyWeek
                    } else {
                        ForEach(scheduledDays) { group in
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                weekDayHeading(group.date, count: group.tasks.count)
                                compactAgenda(group.tasks, on: group.date, showsPlanningActions: false)
                            }
                        }
                    }
                } else {
                    dayHeading(count: dailyTasks.count)
                    compactAgenda(dailyTasks, on: day, showsTimeGrid: period == .day)
                }
            }
        }
        .swipeActionsContainer()
        .scrollEdgeEffectStyle(.hard, for: .top)
        .contentMargins(.horizontal, Theme.pageMargin, for: .scrollContent)
        .contentMargins(.vertical, Theme.Spacing.md, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .onAppear { if selectedDay == nil { selectDay(now) } }
        .sheet(isPresented: $showingDatePicker) {
            NavigationStack {
                ScrollView {
                    DatePicker("Calendário", selection: $pickerDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .tint(Theme.nativeSelection)
                        .padding(Theme.pageMargin)
                }
                .background(Theme.background)
                .navigationTitle("Calendário")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingDatePicker = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            selectDay(pickerDate)
                            showingDatePicker = false
                        }
                        .accessibilityIdentifier("upcoming.confirmDate")
                    }
                }
            }
        }
        .onChange(of: showingDatePicker) { _, showing in
            if showing { pickerDate = day }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Calendário")
                .font(Theme.Typography.screenTitle)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                Button("Ajustes e perfil", systemImage: "person.crop.circle", action: onProfile)
                    .accessibilityIdentifier("settings.open")
                Button("Reminders", systemImage: "bell", action: onReminders)
            } label: {
                Label("Planning options", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(Theme.Typography.toolbarIcon)
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityValue(Text(LocalizedStringKey(period.rawValue)))
            .accessibilityIdentifier("upcoming.options")
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var calendarNavigation: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xxs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
        return layout {
            dateButton
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.xs) }
            periodControls
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private var periodDate: Text {
        switch period {
        case .day:
            Text(day, format: dateFormat.weekday(.abbreviated).day().month(.abbreviated))
        case .week:
            if let interval = calendar.dateInterval(of: .weekOfYear, for: day),
               let end = calendar.date(byAdding: .day, value: -1, to: interval.end) {
                Text("\(Text(interval.start, format: dateFormat.day().month(.abbreviated))) – \(Text(end, format: dateFormat.day().month(.abbreviated)))")
            } else {
                Text(day, format: dateFormat.month(.wide).year())
            }
        case .month:
            Text(day, format: dateFormat.month(.wide).year())
        }
    }

    private var dateButton: some View {
        Button { showingDatePicker = true } label: {
            HStack(spacing: Theme.Spacing.xs) {
                periodDate
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(Theme.Typography.footnote)
                    .accessibilityHidden(true)
            }
            .font(Theme.Typography.metadataEmphasis)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .accessibilityLabel("Choose date")
        .accessibilityValue(periodDate)
        .accessibilityIdentifier("upcoming.chooseDate")
    }

    private var periodControls: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button { selectDay(now) } label: {
                Text("Today")
                    .font(Theme.Typography.metadataEmphasis)
                    .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("upcoming.today")
            periodButton(previous: true)
            periodButton(previous: false)
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private func periodButton(previous: Bool) -> some View {
        Button { move(period, by: previous ? -1 : 1) } label: {
            Label(previous ? "Período anterior" : "Próximo período",
                  systemImage: previous ? "chevron.backward" : "chevron.forward")
                .labelStyle(.iconOnly)
                .font(Theme.Typography.toolbarIcon)
                .frame(width: Theme.Metrics.minTouchTarget, height: Theme.Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(LocalizedStringKey(period.rawValue)))
        .accessibilityIdentifier(previous ? "upcoming.previousPeriod" : "upcoming.nextPeriod")
    }

    private var periodPicker: some View {
        Picker("Período", selection: $period) {
            ForEach(CalendarPeriod.allCases) { period in
                Text(LocalizedStringKey(period.rawValue)).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("upcoming.period")
    }

    private func dayHeading(count: Int) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm))
        return layout {
            if period == .month {
                Text(day, format: dateFormat.weekday(.wide).day().month(.wide))
                    .font(Theme.Typography.headline)
                    .accessibilityIdentifier("upcoming.selectedDate")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Tasks").font(Theme.Typography.headline)
            }
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
            Text("\(count) tasks")
                .font(Theme.Typography.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityAddTraits(.isHeader)
        .foregroundStyle(Theme.textPrimary)
    }

    private func weekDayHeading(_ date: Date, count: Int) -> some View {
        Button { openDay(date) } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Text(date, format: dateFormat.weekday(.wide).day().month(.abbreviated))
                    .font(Theme.Typography.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: Theme.Spacing.xs)
                Text(count, format: .number).font(Theme.Typography.numeric)
                Image(systemName: "chevron.forward")
                    .font(Theme.Typography.footnote)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: Theme.Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textPrimary)
        .accessibilityValue(Text("\(count) tasks"))
        .accessibilityHint("Shows tasks for this day.")
        .accessibilityIdentifier("upcoming.openDay.\(date.timeIntervalSince1970)")
    }

    private var emptyWeek: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("No tasks this week")
                .font(Theme.Typography.headline)
            Text("Choose a day to plan a task.")
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Theme.Spacing.lg)
        .foregroundStyle(Theme.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("upcoming.emptyWeek")
    }

    private func compactAgenda(_ tasks: [TaskSnapshot], on date: Date, showsTimeGrid: Bool = false,
                               showsPlanningActions: Bool = true) -> some View {
        UpcomingAgendaView(tasks: tasks, day: date, now: now, showsTimeGrid: showsTimeGrid,
                           showsPlanningActions: showsPlanningActions,
                           onOpen: onOpen, onEdit: onEdit, onDeadline: onDeadline, onCreateAtTime: onCreateAtTime,
                           onCreateOnDay: { selectDay(date); onCreateOnDay(date) })
    }

    private func openDay(_ date: Date) {
        selectDay(date)
        period = .day
    }

    private func selectDay(_ date: Date) { selectedDay = calendar.startOfDay(for: date) }
    private func move(_ period: CalendarPeriod, by offset: Int) {
        if let date = calendar.date(byAdding: period.component, value: offset, to: day) { selectDay(date) }
    }
}
