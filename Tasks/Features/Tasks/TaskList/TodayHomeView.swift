import SwiftUI

struct TodayHomeView: View {
    let now: Date
    let onViewAll: () -> Void
    let onCreate: () -> Void
    let onReminders: () -> Void
    let onProfile: () -> Void
    let onOpen: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onDeadline: (TaskSnapshot) -> Void
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @State private var showingOverdue = false
    @State private var showingCompleted = false

    var body: some View {
        let plan = TodayPlan(tasks: viewModel.tasks, now: now, calendar: calendar)
        let pending = plan.today.filter { !$0.isDone }
        let completed = plan.today.filter(\.isDone)
        let progress = DayProgress(tasks: viewModel.tasks, date: now, calendar: calendar)
        List {
            header
                .modifier(HomeTaskSurface())
            PersistenceErrorBanner()
                .modifier(HomeTaskSurface())

            if viewModel.hasLoadedTasks {
                if progress.totalCount > 0 {
                    HomeProgressView(progress: progress)
                        .modifier(HomeTaskSurface())
                }

                if !plan.overdue.isEmpty {
                    disclosure("Overdue", count: plan.overdue.count, expanded: $showingOverdue,
                               identifier: "home.overdue", overdue: true)
                    if showingOverdue { taskRows(plan.overdue) }
                }

                if pending.isEmpty {
                    emptyState(completed: !completed.isEmpty)
                        .modifier(HomeTaskSurface())
                } else {
                    taskRows(pending)
                }

                if !completed.isEmpty {
                    disclosure("Completed", count: completed.count, expanded: $showingCompleted,
                               identifier: "home.completed")
                    if showingCompleted { taskRows(completed) }
                }

                Button(action: onViewAll) {
                    Label("View calendar", systemImage: "calendar")
                        .font(Theme.Typography.metadataEmphasis)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textSecondary)
                .accessibilityIdentifier("home.calendar")
                .modifier(HomeTaskSurface())
            } else {
                ProgressView("Loading tasks")
                    .modifier(HomeTaskSurface())
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .listSectionSeparator(.hidden)
        .contentMargins(.horizontal, Theme.pageMargin, for: .scrollContent)
        .contentMargins(.top, Theme.Spacing.md, for: .scrollContent)
        .contentMargins(.bottom, Theme.Spacing.lg, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                Text("Today")
                    .font(Theme.Typography.screenTitle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)
                Menu {
                    Button("Reminders", systemImage: "bell", action: onReminders)
                        .accessibilityIdentifier("home.reminders")
                } label: {
                    Label("More", systemImage: "ellipsis")
                        .labelStyle(.iconOnly)
                        .font(Theme.Typography.toolbarIcon)
                        .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                }
                .accessibilityIdentifier("home.options")
                Button(action: onProfile) {
                    ProfileAvatar(size: Theme.Metrics.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes e perfil")
                .accessibilityIdentifier("settings.open")
            }
            Text(now, format: Date.FormatStyle(locale: locale, calendar: calendar,
                                               timeZone: calendar.timeZone).weekday(.wide).day().month(.wide))
                .font(Theme.Typography.metadata)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.bottom, Theme.Spacing.xs)
    }

    private func disclosure(_ title: LocalizedStringKey, count: Int, expanded: Binding<Bool>,
                            identifier: String, overdue: Bool = false) -> some View {
        Button { expanded.wrappedValue.toggle() } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Text(title)
                Text(count, format: .number).monospacedDigit()
                Spacer(minLength: Theme.Spacing.xs)
                Image(systemName: expanded.wrappedValue ? "chevron.up" : "chevron.down")
                    .font(Theme.Typography.footnote)
                    .accessibilityHidden(true)
            }
            .font(Theme.Typography.metadataEmphasis)
            .foregroundStyle(overdue ? Theme.error : Theme.textSecondary)
            .frame(minHeight: Theme.Metrics.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(expanded.wrappedValue ? Text("Expandida") : Text("Recolhida"))
        .accessibilityIdentifier(identifier)
        .modifier(HomeTaskSurface())
    }

    private func emptyState(completed: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if completed {
                DayCompletionSummary()
            } else {
                Text("No tasks planned")
                    .font(Theme.Typography.headline)
                Text("Add a task for today or plan another day in Calendar.")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onCreate) {
                    Label("New task", systemImage: "plus")
                        .font(Theme.Typography.metadataEmphasis)
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.empty.create")
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.vertical, Theme.Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(completed ? "home.allCompleted" : "home.empty")
    }

    private func taskRows(_ tasks: [TaskSnapshot]) -> some View {
        ForEach(tasks) { task in
            TaskRow(task: task, now: now, showNotes: false, isHomeRow: true, showsCategory: false,
                    onOpen: { onOpen(task.id) }, onDeadline: { onDeadline(task) }, onEdit: { onEdit(task.id) })
                .modifier(HomeTaskSurface())
        }
    }
}

private struct HomeTaskSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, Theme.Spacing.xxs)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.background)
    }
}
