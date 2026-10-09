import SwiftUI

struct AllTasksView: View {
    private enum Status: String, CaseIterable, Identifiable {
        case all = "All", pending = "Pending", completed = "Completed"
        var id: Self { self }
    }
    private enum Grouping: String, CaseIterable, Identifiable {
        case none = "No grouping", category = "Por categoria", status = "Por status"
        var id: Self { self }
    }

    let now: Date
    @Binding var categoryFilter: TaskCategoryFilter
    let isExporting: Bool
    let onCreate: () -> Void
    let onOpen: (UUID) -> Void
    let onEdit: (UUID) -> Void
    let onDeadline: (TaskSnapshot) -> Void
    let onSettings: () -> Void
    let onReminders: () -> Void
    let onExport: () -> Void
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var searchFocused: Bool
    @State private var search = ""
    @State private var status: Status = .all
    @State private var filter: TaskFilter = .any
    @State private var dateScope: TaskDateScope = .any
    @State private var grouping: Grouping = .none
    @State private var sort: TaskListSort = .deadline
    @State private var showingFilters = false
    @State private var collapsedCategories: Set<TaskCategoryFilter> = []

    private var searchText: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasFilters: Bool { filter != .any || categoryFilter != .all || dateScope != .any }
    private var filterCount: Int { (filter != .any ? 1 : 0) + (categoryFilter != .all ? 1 : 0) + (dateScope != .any ? 1 : 0) }

    var body: some View {
        let pending = matching(.all)
        let completed = matching(.completed)
        let tasks = sort.ordered(status == .all ? pending + completed : status == .completed ? completed : pending,
                                 calendar: calendar)
        List {
            header.modifier(LibrarySurface())
            if viewModel.hasLoadedTasks {
                dailySummary.modifier(LibrarySurface())
                if dateScope == .today {
                    let progress = DayProgress(tasks: viewModel.tasks, date: now, calendar: calendar)
                    if progress.totalCount > 0 {
                        HomeProgressView(progress: progress).modifier(LibrarySurface())
                    }
                }
            }
            searchControls.modifier(LibrarySurface())
            statusPicker.modifier(LibrarySurface())
            if hasFilters { activeFilters.modifier(LibrarySurface()) }
            if !searchText.isEmpty {
                Text("\(tasks.count) resultados")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityIdentifier("tasks.searchCount")
                    .modifier(LibrarySurface())
            }
            PersistenceErrorBanner().modifier(LibrarySurface())
            if !viewModel.hasLoadedTasks {
                ProgressView("Loading tasks").modifier(LibrarySurface())
            } else if tasks.isEmpty {
                emptyState.modifier(LibrarySurface())
            } else if grouping == .category && searchText.isEmpty {
                categoryRows(tasks)
            } else if grouping == .status && status == .all && searchText.isEmpty {
                if !pending.isEmpty {
                    Section("Pending") { taskRows(sort.ordered(pending, calendar: calendar)) }
                }
                if !completed.isEmpty {
                    Section("Completed") { taskRows(sort.ordered(completed, calendar: calendar)) }
                }
            } else {
                taskRows(tasks)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .listSectionSeparator(.hidden)
        .listRowSpacing(Theme.Layout.rowSpacing)
        .listSectionSpacing(.custom(Theme.Spacing.md))
        .contentMargins(.horizontal, Theme.pageMargin, for: .scrollContent)
        .contentMargins(.vertical, Theme.Spacing.md, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .sheet(isPresented: $showingFilters) { filterSheet }
        .onChange(of: categoryFilter) { _, category in collapsedCategories.remove(category) }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text("Tasks")
                .font(Theme.Typography.screenTitle)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
            Menu {
                Picker("Sort tasks", selection: $sort) {
                    ForEach(TaskListSort.allCases) { order in
                        Text(LocalizedStringKey(order.rawValue)).tag(order)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("tasks.sort")
                Picker("Agrupar tarefas", selection: $grouping) {
                    ForEach(Grouping.allCases) { group in
                        Text(LocalizedStringKey(group.rawValue)).tag(group)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("tasks.grouping")
                Button("Reminders", systemImage: "bell", action: onReminders)
                    .accessibilityIdentifier("tasks.reminders")
                Button("Export tasks", systemImage: "square.and.arrow.up", action: onExport)
                    .disabled(isExporting || !viewModel.hasLoadedTasks)
                Button("Ajustes", systemImage: "gearshape", action: onSettings)
                    .accessibilityIdentifier("settings.open")
            } label: {
                Label("More", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .font(Theme.Typography.toolbarIcon)
                    .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("collection.options")
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var dailySummary: some View {
        let progress = DayProgress(tasks: viewModel.tasks, date: now, calendar: calendar)
        let overdueCount = viewModel.tasks.filter { TaskDateScope.overdue.includes($0, now: now, calendar: calendar) }.count
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xxs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))
        return layout {
            summaryButton(progress.pendingCount == 0 ? Text("No pending tasks today") : Text("\(progress.pendingCount) pending today"),
                          scope: .today, id: "tasks.focus.today")
            summaryButton(overdueCount == 0 ? Text("No overdue tasks") : Text("\(overdueCount) overdue"),
                          scope: .overdue, id: "tasks.focus.overdue")
        }
        .font(Theme.Typography.metadata)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tasks.summary")
    }

    private func summaryButton(_ title: Text, scope: TaskDateScope, id: String) -> some View {
        Button { show(scope) } label: {
            title
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(dateScope == scope ? Theme.accent : Theme.textSecondary)
                .underline(dateScope == scope)
                .frame(minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(dateScope == scope ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func show(_ scope: TaskDateScope) {
        searchFocused = false
        search = ""
        clearFilters()
        status = .pending
        dateScope = scope
    }

    private var searchControls: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
        return layout {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "magnifyingglass").accessibilityHidden(true)
                TextField("Search tasks", text: $search,
                          prompt: Text("Search tasks").foregroundStyle(Theme.textSecondary))
                    .foregroundStyle(Theme.textPrimary)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($searchFocused)
                    .onSubmit { searchFocused = false }
                    .accessibilityIdentifier("tasks.search")
                if !search.isEmpty {
                    Button { search = "" } label: {
                        Label("Clear search", systemImage: "xmark.circle.fill")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tasks.clearSearch")
                }
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xxs)
            .frame(minHeight: Theme.Metrics.minTouchTarget)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
            Button {
                searchFocused = false
                showingFilters = true
            } label: {
                HStack(spacing: Theme.Spacing.xxs) {
                    Label("Filters", systemImage: "line.3.horizontal.decrease")
                    if hasFilters { Text(filterCount, format: .number).monospacedDigit() }
                }
                .font(Theme.Typography.metadataEmphasis)
                .frame(minHeight: Theme.Metrics.minTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .accessibilityIdentifier("tasks.filters")
        }
    }

    private var statusPicker: some View {
        Picker("Task status", selection: $status) {
            ForEach(Status.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("tasks.status")
    }

    private var activeFilters: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xxs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
        return layout {
            if categoryFilter != .all {
                filterChip(Text(verbatim: categoryFilter.title), identifier: "tasks.clearCategory") { categoryFilter = .all }
            }
            if dateScope != .any {
                filterChip(Text(LocalizedStringKey(dateScope.rawValue)), identifier: "tasks.clearDateScope") { dateScope = .any }
            }
            if filter != .any {
                filterChip(Text(LocalizedStringKey(filter.rawValue)), identifier: "tasks.clearDeadline") { filter = .any }
            }
            emptyAction("Clear filters", id: "tasks.clearFilters", action: clearFilters)
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private func filterChip(_ title: Text, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                title
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "xmark").accessibilityHidden(true)
            }
            .font(Theme.Typography.footnote)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(minHeight: Theme.Metrics.minTouchTarget)
            .background(Theme.surfaceSecondary, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Remove this filter")
        .accessibilityIdentifier(identifier)
    }

    private var filterSheet: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    ForEach(TaskCategoryFilter.allCases) { category in
                        Button { categoryFilter = category } label: {
                            HStack {
                                Label(category.title, systemImage: category.symbol)
                                Spacer(minLength: Theme.Spacing.xs)
                                if categoryFilter == category {
                                    Image(systemName: "checkmark").accessibilityHidden(true)
                                }
                            }
                            .frame(minHeight: Theme.Metrics.minTouchTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(categoryFilter == category ? .isSelected : [])
                        .accessibilityIdentifier("tasks.category.\(categoryID(category))")
                    }
                }
                .listRowBackground(Theme.surface)
                Section("Date") {
                    Picker("Date", selection: $dateScope) {
                        ForEach(TaskDateScope.allCases) { scope in Text(LocalizedStringKey(scope.rawValue)).tag(scope) }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("tasks.dateScope")
                }
                .listRowBackground(Theme.surface)
                Section("Deadline") {
                    Picker("Deadline", selection: $filter) {
                        ForEach(TaskFilter.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .accessibilityIdentifier("tasks.deadlineFilter")
                }
                .listRowBackground(Theme.surface)
            }
            .foregroundStyle(Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear filters", action: clearFilters).disabled(!hasFilters)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingFilters = false }
                        .accessibilityIdentifier("tasks.filters.done")
                }
            }
        }
        .tint(Theme.accent)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if dateScope == .today && status == .pending && filter == .any && categoryFilter == .all && searchText.isEmpty {
                let progress = DayProgress(tasks: viewModel.tasks, date: now, calendar: calendar)
                if progress.totalCount > 0 {
                    DayCompletionSummary()
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("tasks.dayComplete")
                } else {
                    Text("No tasks planned").font(Theme.Typography.headline)
                    emptyAction("New task", id: "tasks.empty.create", action: onCreate)
                }
            } else if hasFilters || !searchText.isEmpty {
                Text("No matching tasks").font(Theme.Typography.headline)
                Text("Try another search or remove a filter.")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.textSecondary)
                if hasFilters { emptyAction("Clear filters", id: "tasks.empty.clearFilters", action: clearFilters) }
                if !searchText.isEmpty && (status != .all || hasFilters) {
                    emptyAction("Search all tasks", id: "tasks.searchAll") {
                        clearFilters()
                        status = .all
                    }
                }
            } else if status == .completed {
                Text("No completed tasks yet").font(Theme.Typography.headline)
                Text("Tasks you complete will appear here.")
                    .font(Theme.Typography.metadata)
                    .foregroundStyle(Theme.textSecondary)
            } else {
                Text(status == .pending ? LocalizedStringKey("No pending tasks") : LocalizedStringKey("No tasks here"))
                    .font(Theme.Typography.headline)
                emptyAction("New task", id: "tasks.empty.create", action: onCreate)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, Theme.Spacing.lg)
        .foregroundStyle(Theme.textPrimary)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tasks.empty")
    }

    private func emptyAction(_ title: LocalizedStringKey, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.metadataEmphasis)
                .frame(minHeight: Theme.Metrics.minTouchTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func matching(_ collection: TaskCollection) -> [TaskSnapshot] {
        TaskQuery(collection: collection, filter: filter, category: categoryFilter, search: search, dateScope: dateScope)
            .results(in: viewModel.tasks, now: now, calendar: calendar)
    }

    private func clearFilters() {
        filter = .any
        categoryFilter = .all
        dateScope = .any
    }

    private func categoryRows(_ tasks: [TaskSnapshot]) -> some View {
        ForEach(TaskCategoryFilter.allCases.filter { $0 != .all }) { category in
            let grouped = tasks.filter(category.includes)
            if !grouped.isEmpty {
                Section {
                    if !collapsedCategories.contains(category) { taskRows(grouped, showsCategory: false) }
                } header: {
                    TaskSectionHeader(title: category.title, count: grouped.count, symbol: category.symbol,
                                      isExpanded: Binding(get: { !collapsedCategories.contains(category) }, set: { expanded in
                        if expanded { collapsedCategories.remove(category) }
                        else { collapsedCategories.insert(category) }
                    }))
                    .accessibilityIdentifier("tasks.section.\(category.symbol)")
                }
            }
        }
    }

    private func taskRows(_ tasks: [TaskSnapshot], showsCategory: Bool = true) -> some View {
        ForEach(tasks) { task in
            TaskRow(task: task, now: now,
                    showNotes: !searchText.isEmpty && task.notes.localizedStandardContains(searchText),
                    usesCompletionCircle: true, showsCategory: showsCategory, compactMetadata: true,
                    search: search, onOpen: { onOpen(task.id) }, onDeadline: { onDeadline(task) }, onEdit: { onEdit(task.id) })
                .modifier(LibrarySurface())
        }
    }

    private func categoryID(_ category: TaskCategoryFilter) -> String {
        switch category {
        case .all: "all"
        case .uncategorized: "none"
        case .category(let icon): icon.rawValue
        }
    }
}

private struct LibrarySurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.background)
    }
}
