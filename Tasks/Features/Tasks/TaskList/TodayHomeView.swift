import SwiftUI

struct TodayHomeView: View {
    let now: Date
    let onViewAll: () -> Void
    let onViewTasks: () -> Void
    let onReminders: () -> Void
    let onProfile: () -> Void
    let onEdit: (UUID) -> Void
    let onDeadline: (TaskSnapshot) -> Void
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let plan = TodayPlan(tasks: viewModel.tasks, now: now, calendar: calendar)
        let pendingToday = plan.today.filter { !$0.isDone }
        let progress = DayProgress(tasks: viewModel.tasks, date: now, calendar: calendar)
        List {
            header(count: plan.today.count)
                .padding(.bottom, Theme.Spacing.md)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.background)

            if viewModel.hasLoadedTasks {
                HomeProgressView(progress: progress)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.background)
            }

            PersistenceErrorBanner()
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.background)

            if viewModel.hasLoadedTasks {
                if !pendingToday.isEmpty {
                    todayCards(pendingToday)
                }

                if !plan.overdue.isEmpty {
                    sectionTitle("Overdue", count: plan.overdue.count, overdue: true)
                        .modifier(HomeSectionHeading())
                    taskRows(plan.overdue)
                }

                if !plan.next.isEmpty {
                    nextTasks(plan.next)
                        .padding(.top, Theme.Layout.sectionSpacing)
                        .modifier(HomeTaskSurface())
                }
            } else {
                ProgressView("Loading tasks")
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.background)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .contentMargins(.horizontal, Theme.pageMargin, for: .scrollContent)
        .contentMargins(.top, Theme.Spacing.md, for: .scrollContent)
        .contentMargins(.bottom, Theme.Spacing.lg, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
    }

    private func header(count: Int) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
                : AnyLayout(HStackLayout(alignment: .center, spacing: Theme.Spacing.sm))
            layout {
                Button(action: onProfile) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ProfileAvatar(size: Theme.Metrics.minTouchTarget)
                        Text(preferences.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? AppLocalization.string("Seu perfil") : preferences.displayName)
                            .font(Theme.Typography.body)
                            .layoutPriority(1)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    }
                    .padding(Theme.Spacing.xxs)
                    .padding(.trailing, Theme.Spacing.sm)
                    .background(Theme.surface, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ajustes e perfil")
                .accessibilityIdentifier("home.profile")
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                headerButton("Reminders", symbol: "bell", action: onReminders)
                    .accessibilityIdentifier("home.reminders")
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Today")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.textSecondary)
                Text("Suas tarefas, no seu ritmo.")
                    .font(Theme.Typography.screenTitle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }
            let summaryLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
                : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.md))
            summaryLayout {
                Text(now, format: Date.FormatStyle(locale: locale, calendar: calendar,
                                                   timeZone: calendar.timeZone).weekday(.wide))
                    .font(Theme.Typography.metadataEmphasis)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button(action: onViewTasks) {
                    HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                        Text("\(count) tarefas hoje")
                            .font(Theme.Typography.headline)
                            .monospacedDigit()
                            .multilineTextAlignment(.leading)
                        Image(systemName: "arrow.up.right")
                            .font(Theme.Typography.toolbarIcon)
                    }
                    .frame(minHeight: Theme.Metrics.minTouchTarget, alignment: .top)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("home.todayTasks")
            }
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private func headerButton(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.iconOnly)
                .font(Theme.Typography.toolbarIcon)
                .frame(minWidth: Theme.Layout.headerActionSize, minHeight: Theme.Layout.headerActionSize)
                .background(Theme.surface, in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func todayCards(_ tasks: [TaskSnapshot]) -> some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                ForEach(tasks) { task in
                    TaskRow(task: task, now: now, showNotes: false, isHomeRow: true, isHomeCard: true,
                            onDeadline: { onDeadline(task) }, onEdit: { onEdit(task.id) })
                        .containerRelativeFrame(.horizontal) { width, _ in
                            min(width, Theme.Home.taskCardWidth)
                        }
                }
            }
            .scrollTargetLayout()
            .padding(.vertical, Theme.Spacing.xs)
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .fixedSize(horizontal: false, vertical: true)
        .listRowInsets(EdgeInsets())
        .listRowSeparator(.hidden)
        .listRowBackground(Theme.background)
    }

    private func sectionTitle(_ title: LocalizedStringKey, count: Int, overdue: Bool = false) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.homeSectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Text(count, format: .number)
                .font(Theme.Typography.numeric)
                .foregroundStyle(overdue ? Theme.error : Theme.textSecondary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xxs)
                .background(overdue ? Theme.errorBackground : Theme.surface, in: Capsule())
        }
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func nextTasks(_ tasks: [TaskSnapshot]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xxs))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm))
            layout {
                Text("Next tasks")
                    .font(Theme.Typography.homeSectionTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityAddTraits(.isHeader)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Button(action: onViewAll) {
                    Label("View all", systemImage: "arrow.up.right")
                        .font(Theme.Typography.metadataEmphasis)
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("home.next.viewAll")
            }
            VStack(spacing: 0) {
                ForEach(tasks) { task in
                    HighlightedTaskView(task: task, now: now) { onEdit(task.id) }
                    if task.id != tasks.last?.id {
                        Divider()
                            .overlay(Theme.border)
                            .padding(.horizontal, Theme.Spacing.md)
                    }
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.next")
    }

    private func taskRows(_ tasks: [TaskSnapshot]) -> some View {
        ForEach(tasks) { task in
            TaskRow(task: task, now: now, showNotes: false, isHomeRow: true,
                    onDeadline: { onDeadline(task) }, onEdit: { onEdit(task.id) })
            .modifier(HomeTaskSurface())
        }
    }
}

private struct HomeSectionHeading: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.top, Theme.Layout.sectionSpacing)
            .padding(.bottom, Theme.Spacing.xs)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.background)
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
