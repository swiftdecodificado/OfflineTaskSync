import SwiftUI

enum UpcomingDisplayMode: String, CaseIterable, Identifiable {
    case agenda = "Agenda"
    case list = "Lista"
    case overview = "All upcoming tasks"
    var id: Self { self }
}

struct UpcomingView: View {
    let now: Date
    @Binding var selectedDay: Date?
    @Binding var showingDatePicker: Bool
    @Binding var categoryFilter: TaskCategoryFilter
    let onCreateAtTime: (Date) -> Void
    let onReminders: () -> Void
    let onEdit: (UUID) -> Void
    let onDeadline: (TaskSnapshot) -> Void
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var mode: UpcomingDisplayMode = .agenda
    @State private var pickerDate = Date.now

    private var day: Date { calendar.startOfDay(for: selectedDay ?? now) }
    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    var body: some View {
        let dailyTasks = TaskQuery(collection: .upcoming, category: categoryFilter, selectedDay: day)
            .results(in: viewModel.tasks, now: now, calendar: calendar).filter { $0.dueTime != nil }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
                header
                TaskCategoryStrip(selection: $categoryFilter)
                if mode != .overview {
                    calendarNavigation
                    WeeklyCalendar(now: now, anchor: day, selectedDay: day, tasks: viewModel.tasks.filter { categoryFilter.includes($0) && $0.dueTime != nil },
                               onSelect: selectDay, onMoveWeek: { moveDay($0 * 7) })
                    dayHeading
                }
                PersistenceErrorBanner()
                if !viewModel.hasLoadedTasks {
                    ProgressView("Loading tasks")
                } else if mode == .agenda {
                    Text("Tap a time to plan a task.")
                        .font(Theme.Typography.metadata)
                        .foregroundStyle(Theme.textSecondary)
                    UpcomingAgendaView(tasks: dailyTasks, day: day, now: now,
                                       onEdit: onEdit, onDeadline: onDeadline, onCreateAtTime: onCreateAtTime)
                } else if mode == .list {
                    if dailyTasks.isEmpty { emptyState("Nothing planned for this day.") }
                    else { planningRows(dailyTasks) }
                } else {
                    futureList
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.sm))
        return layout {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Próximas tarefas")
                    .font(Theme.Typography.sectionTitle)
                    .accessibilityAddTraits(.isHeader)
                Text(LocalizedStringKey(mode.rawValue))
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.textSecondary)
                if mode == .overview && categoryFilter != .all {
                    Text(categoryFilter.title)
                        .font(Theme.Typography.metadata)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
                displayModePicker
                Button("Today") { selectDay(now); mode = .agenda }
                Button("Reminders", systemImage: "bell", action: onReminders)
            } label: {
                Label("Planning options", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(Theme.Typography.toolbarIcon)
                    .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
            }
            .accessibilityValue(Text("\(Text(LocalizedStringKey(mode.rawValue))), \(categoryFilter.title)"))
            .accessibilityIdentifier("upcoming.options")
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var calendarNavigation: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
        return layout {
            dateButton
            if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: Theme.Spacing.xs) }
            weekControls
        }
    }

    private var dateButton: some View {
        Button { showingDatePicker = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.xs) {
                Image(systemName: "calendar")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text(day, format: dateFormat.month(.wide).year())
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(Theme.Typography.metadataEmphasis)
            .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Calendário")
        .accessibilityValue(Text(day, format: dateFormat.month(.wide).year()))
        .accessibilityIdentifier("upcoming.chooseDate")
    }

    private var weekControls: some View {
        HStack(spacing: Theme.Spacing.xs) {
            weekButton("Previous week", symbol: "chevron.backward", offset: -1)
                .accessibilityIdentifier("upcoming.previousWeek")
            weekButton("Next week", symbol: "chevron.forward", offset: 1)
                .accessibilityIdentifier("upcoming.nextWeek")
        }
    }

    private func weekButton(_ title: LocalizedStringKey, symbol: String, offset: Int) -> some View {
        Button { moveDay(offset * 7) } label: {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .frame(width: Theme.Metrics.minTouchTarget, height: Theme.Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(Theme.Typography.toolbarIcon)
        .foregroundStyle(Theme.textPrimary)
    }

    private var displayModePicker: some View {
        Picker("Upcoming view", selection: $mode) {
            ForEach(UpcomingDisplayMode.allCases) { mode in
                Text(LocalizedStringKey(mode.rawValue)).tag(mode)
            }
        }
        .frame(minHeight: Theme.Metrics.minTouchTarget)
    }

    private var dayHeading: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(day, format: dateFormat.weekday(.wide).day().month(.wide))
                .font(Theme.Typography.headline)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("upcoming.selectedDate")
            if categoryFilter != .all {
                Text(categoryFilter.title)
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Theme.textPrimary)
    }

    private func planningRows(_ tasks: [TaskSnapshot]) -> some View {
        ForEach(tasks) { task in
            TaskRow(task: task, now: now, showNotes: false, showsCategory: false,
                    showsDate: false, showsReminder: false,
                    onDeadline: { onDeadline(task) }, onEdit: { onEdit(task.id) })
        }
    }

    @ViewBuilder private var futureList: some View {
        let plan = UpcomingPlan(tasks: viewModel.tasks.filter { categoryFilter.includes($0) && $0.dueTime != nil }, now: now, calendar: calendar)
        let days = plan.days
        if days.isEmpty {
            emptyState(categoryFilter == .all ? "No Upcoming Tasks" : "Nenhuma tarefa futura nesta categoria.")
        } else {
            ForEach(days) { group in
                Section {
                    ForEach(group.tasks) { task in
                        TaskRow(task: task, now: now, onDeadline: { onDeadline(task) },
                                onEdit: { onEdit(task.id) })
                        .listRowBackground(Theme.background)
                    }
                } header: {
                    Text(group.date, format: dateFormat.weekday(.wide).day().month(.wide).year())
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .textCase(nil)
                }
            }
        }
    }

    private func emptyState(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.textSecondary)
            .padding(.vertical, Theme.Spacing.lg)
    }

    private func selectDay(_ date: Date) { selectedDay = calendar.startOfDay(for: date) }
    private func moveDay(_ offset: Int) {
        if let date = calendar.date(byAdding: .day, value: offset, to: day) { selectDay(date) }
    }
}
