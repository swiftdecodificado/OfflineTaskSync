import SwiftUI

struct TaskListView: View {
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingSettings = false
    @State private var selection: TaskCollection = .today
    @State private var composerDraft: TaskDraft?
    @State private var scheduledDraft: TaskDraft?
    @State private var editorStorageReady = false
    @State private var selectedUpcomingDay: Date?
    @State private var categoryFilter: TaskCategoryFilter = .all
    @State private var celebrationID: UUID?
    @State private var showingCelebration = false
    @State private var successFeedback = 0

    var body: some View {
        tabs
            .id(preferences.language)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomNavigation
                    .background(Theme.background)
            }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .top) {
            if showingCelebration {
                DayCompletionCelebration()
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.top, Theme.Spacing.xs)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    .allowsHitTesting(false)
            }
        }
        .sensoryFeedback(.success, trigger: successFeedback)
        .onChange(of: viewModel.tasks) { previous, current in
            updateCelebration(previous: previous, current: current)
        }
        .task(id: celebrationID) {
            guard celebrationID != nil else { return }
            do {
                try await Task.sleep(for: .seconds(Theme.Home.progressFillDuration + 0.05))
                try Task.checkCancellation()
                withAnimation(Theme.Feedback.stateChange) { showingCelebration = true }
                successFeedback += 1
                AccessibilityNotification.Announcement(AppLocalization.string("Por hoje, tá feito.")).post()
                try await Task.sleep(for: .seconds(2))
                try Task.checkCancellation()
                withAnimation(Theme.Feedback.stateChange) { showingCelebration = false }
                try await Task.sleep(for: .milliseconds(200))
                try Task.checkCancellation()
                celebrationID = nil
            } catch is CancellationError {
                // A reopened task cancels the celebration.
            } catch {
                celebrationID = nil
                showingCelebration = false
            }
        }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .sheet(item: $scheduledDraft) { draft in ScheduledTaskEditor(draft: draft, mediaStore: viewModel.mediaStore) }
        .sheet(item: $composerDraft) { draft in Composer(draft: draft, mediaStore: viewModel.mediaStore) }
        .tint(Theme.accent)
        .disabled(!editorStorageReady)
        .task {
            await viewModel.prepareEditorStorage()
            await viewModel.refresh()
            editorStorageReady = true
        }
    }
    private var tabs: some View {
        TabView(selection: $selection) {
            ForEach([TaskCollection.today, .upcoming, .all]) { collection in
                Tab(value: collection) {
                    TaskCollectionView(collection: collection, selectedCollection: $selection,
                                       selectedUpcomingDay: $selectedUpcomingDay, categoryFilter: $categoryFilter,
                                       onCreate: presentComposer, onCreateAtTime: presentScheduledComposer, onSettings: { showingSettings = true })
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label(LocalizedStringKey(collection.rawValue), systemImage: collection.symbol)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var bottomNavigation: some View {
        VStack(spacing: Theme.Spacing.xs) {
            completionUndoBanner
            HStack(spacing: Theme.Spacing.sm) {
                AppNavigationBar(selection: $selection, onProfile: { showingSettings = true })
                NewTaskButton {
                    presentComposer(for: selection,
                                    suggestedDate: selection == .upcoming ? selectedUpcomingDay : nil)
                }
            }
            .frame(maxWidth: Theme.Home.navigationMaxWidth + Theme.Spacing.sm + Theme.Metrics.floatingActionSize)
        }
        .padding(.horizontal, Theme.pageMargin)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func updateCelebration(previous: [TaskSnapshot], current: [TaskSnapshot]) {
        let now = Date.now
        let today = current.filter { task in
            task.dueDate.map { calendar.isDate($0, inSameDayAs: now) } == true
        }
        guard !today.isEmpty, today.allSatisfy(\.isDone) else {
            celebrationID = nil
            showingCelebration = false
            return
        }
        let completedIDs = Set(today.map(\.id))
        let completedTask = previous.contains { task in
            !task.isDone && completedIDs.contains(task.id)
                && task.dueDate.map { calendar.isDate($0, inSameDayAs: now) } == true
        }
        guard completedTask else { return }
        celebrationID = UUID()
    }

    private func presentScheduledComposer(_ start: Date) {
        var draft = TaskDraft()
        draft.dueDate = calendar.startOfDay(for: start)
        draft.dueTime = start
        draft.dueEndTime = AgendaTimeGrid(day: start, calendar: calendar).ends(after: start).first
        if case .category(let category) = categoryFilter { draft.icon = category }
        scheduledDraft = draft
    }

    private func presentComposer(for collection: TaskCollection, suggestedDate: Date?) {
        var draft = TaskDraft()
        if case .category(let category) = categoryFilter { draft.icon = category }
        if collection == .upcoming, let suggestedDate { draft.dueDate = suggestedDate }
        composerDraft = draft
    }

    @ViewBuilder
    private var completionUndoBanner: some View {
        if let task = viewModel.completionUndo {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("Completed: \(task.title)")
                    .font(Theme.Typography.metadataEmphasis)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Theme.Spacing.md) {
                    Button {
                        Task { await viewModel.undoCompletion() }
                    } label: {
                        Text("Undo").frame(minHeight: Theme.Metrics.minTouchTarget)
                    }
                        .accessibilityIdentifier("task.undoCompletion")
                        .disabled(viewModel.isChangingCompletion)
                    Spacer(minLength: 0)
                    Button(action: viewModel.dismissCompletionUndo) {
                        Text("Dismiss").frame(minHeight: Theme.Metrics.minTouchTarget)
                    }
                }
                .font(Theme.Typography.body)
                .buttonStyle(.borderless)
                .frame(minHeight: Theme.Metrics.minTouchTarget)
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(Theme.Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
        }
    }
}

private struct TaskCollectionView: View {
    private enum Status: String, CaseIterable, Identifiable {
        case active = "Pending", completed = "Completed", all = "All"
        var id: Self { self }
    }
    let collection: TaskCollection
    @Binding var selectedCollection: TaskCollection
    @Binding var selectedUpcomingDay: Date?
    @Binding var categoryFilter: TaskCategoryFilter
    let onCreate: (TaskCollection, Date?) -> Void
    let onCreateAtTime: (Date) -> Void
    let onSettings: () -> Void
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var editingTask: TaskSnapshot?
    @State private var showingReminders = false
    @State private var filter: TaskFilter = .any
    @State private var search = ""
    @State private var status: Status = .active
    @State private var groupByCategory = true
    @State private var collapsedCategories: Set<TaskCategoryFilter> = []
    @State private var export: TaskExport?
    @State private var preparingExport = false
    @State private var deadlineTask: TaskSnapshot?
    @State private var showingDatePicker = false

    var body: some View {
        NavigationStack() {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if collection == .today {
                    TodayHomeView(now: context.date, onViewAll: {
                        categoryFilter = .all
                        selectedUpcomingDay = TaskQuery(collection: .upcoming)
                            .results(in: viewModel.tasks, now: context.date, calendar: calendar)
                            .first?.dueDate
                        selectedCollection = .upcoming
                    }, onViewTasks: {
                        categoryFilter = .all
                        selectedCollection = .all
                    }, onReminders: { showingReminders = true }, onProfile: onSettings,
                                  onEdit: { openEditor($0) }) { deadlineTask = $0 }
                } else if collection == .upcoming {
                    UpcomingView(now: context.date, selectedDay: $selectedUpcomingDay,
                                 showingDatePicker: $showingDatePicker, categoryFilter: $categoryFilter, onCreateAtTime: onCreateAtTime, onReminders: { showingReminders = true },
                                 onEdit: { openEditor($0) }) { deadlineTask = $0 }
                } else {
                    collectionList(now: context.date)
                }
            }
            .safeAreaBar(edge: .top, spacing: 0) {
                if collection == .all {
                    categoryControls
                        .padding(.horizontal, Theme.pageMargin)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(Theme.background)
                }
            }
            .onChange(of: categoryFilter) { _, category in
                collapsedCategories.remove(category)
            }
            .modifier(CollectionSearch(enabled: collection == .all, search: $search))
            .navigationTitle(collection == .today ? Text("") : Text(LocalizedStringKey(collection.rawValue)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                if collection != .today {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Ajustes", systemImage: "gearshape", action: onSettings)
                            Button {
                                preparingExport = true
                                Task {
                                    export = await viewModel.prepareExport()
                                    preparingExport = false
                                }
                            } label: { Label("Export tasks", systemImage: "square.and.arrow.up") }
                            .disabled(preparingExport || !viewModel.hasLoadedTasks)
                            if collection == .all {
                                Picker("Deadline", selection: $filter) {
                                    ForEach(TaskFilter.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                                }
                            }
                        } label: {
                            Label("More", systemImage: "ellipsis")
                                .labelStyle(.iconOnly)
                                .font(Theme.Typography.toolbarIcon)
                                .foregroundStyle(Theme.textPrimary)
                                .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                        }
                    }
                }
            }
            .toolbar(collection == .all ? .visible : .hidden, for: .navigationBar)
            .sheet(isPresented: $showingReminders) { ReminderListSheet() }
            .sheet(item: $export) { archive in
                NavigationStack {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.lg) {
                            Text("Export all tasks")
                                .font(Theme.Typography.sectionTitle)
                            Text("O JSON inclui tarefas, texto formatado, prazos e referências dos anexos. Fotos, vídeos e arquivos não são incluídos.")
                                .font(Theme.Typography.body)
                            ShareLink(item: archive, preview: SharePreview("OfflineTaskSync tasks")) {
                                Label("Share JSON", systemImage: "square.and.arrow.up")
                                    .frame(minHeight: Theme.Metrics.minTouchTarget)
                            }
                        }
                        .padding(Theme.Spacing.lg)
                        .foregroundStyle(Theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.background)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close", systemImage: "xmark") { export = nil }
                                .labelStyle(.iconOnly)
                                .tint(Theme.textPrimary)
                        }
                    }
                }
            }
            .sheet(item: $deadlineTask) { task in
                NavigationStack {
                    Form {
                        PersistenceErrorBanner()
                            .listRowBackground(Theme.surface)
                        DeadlineEditor(taskID: task.id)
                            .listRowBackground(Theme.surface)
                    }
                        .scrollContentBackground(.hidden)
                        .background(Theme.background)
                        .navigationTitle("Deadline")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done", systemImage: "checkmark") { deadlineTask = nil }
                                    .labelStyle(.iconOnly)
                                    .tint(Theme.textPrimary)
                            }
                        }
                }
            }
            .fullScreenCover(item: $editingTask) { task in
                TaskDetailView(taskID: task.id)
            }
        }
    }

    private func openEditor(_ id: UUID) {
        editingTask = viewModel.task(id: id)
    }

    private func collectionList(now: Date) -> some View {
        let pending = TaskQuery(collection: .all, filter: filter, category: categoryFilter, search: search)
            .results(in: viewModel.tasks, now: now)
        let completed = TaskQuery(collection: .completed, filter: filter, category: categoryFilter, search: search)
            .results(in: viewModel.tasks, now: now)
        let tasks = status == .all ? pending + completed : status == .completed ? completed : pending
        return List {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    statusPicker.pickerStyle(.menu)
                } else {
                    statusPicker.pickerStyle(.segmented)
                }
            }
            .listRowInsets(EdgeInsets())
            .accessibilityIdentifier("tasks.status")
            .listRowBackground(Theme.background)
            .listRowSeparator(.hidden)

            if filter != .any || !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
                    : AnyLayout(HStackLayout(spacing: Theme.Spacing.sm))
                layout {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("\(tasks.count) resultados")
                                .font(Theme.Typography.metadataEmphasis)
                                .accessibilityIdentifier("tasks.searchCount")
                        }
                        if filter != .any {
                            Label(LocalizedStringKey(filter.rawValue), systemImage: "line.3.horizontal.decrease")
                                .font(Theme.Typography.footnote)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Clear filters") {
                        filter = .any
                        search = ""
                        categoryFilter = .all
                    }
                    .font(Theme.Typography.metadata)
                    .frame(minHeight: Theme.Metrics.minTouchTarget)
                    .accessibilityIdentifier("tasks.clearFilters")
                }
                .foregroundStyle(Theme.textPrimary)
                .listRowBackground(Theme.background)
            }
            PersistenceErrorBanner()
                .listRowInsets(EdgeInsets(top: Theme.Spacing.xs, leading: 0, bottom: Theme.Spacing.xs, trailing: 0))
                .listRowSeparator(.hidden)
                .listRowBackground(Theme.background)
            if viewModel.hasLoadedTasks {
                if tasks.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Image(systemName: collection.symbol)
                            .font(Theme.Typography.sectionTitle)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityHidden(true)
                        Text(search.isEmpty && filter == .any && categoryFilter == .all ? "No tasks here" : "No matching tasks")
                            .font(Theme.Typography.sectionTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .accessibilityAddTraits(.isHeader)
                        Text(search.isEmpty && filter == .any && categoryFilter == .all
                            ? "Tap New task. A title is all you need."
                            : "Tente outra busca ou categoria.")
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, Theme.Spacing.md)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Theme.background)
                } else {
                    if groupByCategory {
                        categoryRows(tasks, now: now)
                    } else if status == .all {
                        if !pending.isEmpty {
                            Section("Pending") { taskRows(pending, now: now) }
                        }
                        if !completed.isEmpty {
                            Section("Completed") { taskRows(completed, now: now) }
                        }
                    } else {
                        taskRows(tasks, now: now)
                    }
                }
            } else {
                ProgressView("Loading tasks")
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .listRowInsets(Theme.contentRowInsets)
        .listRowSeparator(.hidden)
        .listRowSpacing(Theme.Layout.rowSpacing)
        .contentMargins(.horizontal, Theme.pageMargin, for: .scrollContent)
        .contentMargins(.top, Theme.Spacing.md, for: .scrollContent)
        .contentMargins(.bottom, Theme.Spacing.md, for: .scrollContent)
        .listSectionSpacing(.custom(Theme.Spacing.md))
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
    }

    private var categoryControls: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.xs) {
            TaskCategoryStrip(selection: $categoryFilter)
            if collection == .all {
                Menu {
                    Picker("Agrupar tarefas", selection: $groupByCategory) {
                        Text("Por categoria").tag(true)
                        Text("Por status").tag(false)
                    }
                } label: {
                    Label("Agrupar", systemImage: "rectangle.3.group")
                        .labelStyle(.iconOnly)
                        .font(Theme.Typography.toolbarIcon)
                        .foregroundStyle(Theme.textPrimary)
                        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                        .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                }
                .accessibilityValue(groupByCategory ? Text("Por categoria") : Text("Por status"))
                .accessibilityIdentifier("tasks.grouping")
            }
        }
    }

    private func categoryRows(_ tasks: [TaskSnapshot], now: Date) -> some View {
        ForEach(TaskCategoryFilter.allCases.filter { $0 != .all }) { category in
            let grouped = tasks.filter(category.includes)
            if !grouped.isEmpty {
                let searching = !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Section {
                    if searching || !collapsedCategories.contains(category) {
                        taskRows(grouped, now: now, showsCategory: false)
                    }
                } header: {
                    if searching {
                        HStack(spacing: Theme.Spacing.xs) {
                            Label(category.title, systemImage: category.symbol)
                            Text(grouped.count, format: .number)
                                .font(Theme.Typography.numeric)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .font(Theme.Typography.homeSectionTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .textCase(nil)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(.isHeader)
                    } else {
                        TaskSectionHeader(title: category.title, count: grouped.count, symbol: category.symbol,
                                          isExpanded: Binding(get: { !collapsedCategories.contains(category) },
                                                              set: { expanded in
                            if expanded { collapsedCategories.remove(category) }
                            else { collapsedCategories.insert(category) }
                        }))
                        .listRowInsets(EdgeInsets())
                        .accessibilityIdentifier("tasks.section.\(category.symbol)")
                    }
                }
            }
        }
    }

    private var statusPicker: some View {
        Picker("Task status", selection: $status) {
            ForEach(Status.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
        }
        .frame(minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
    }

    private func taskRows(_ tasks: [TaskSnapshot], now: Date, showsCategory: Bool = true) -> some View {
        ForEach(tasks) { task in
            TaskRow(task: task, now: now, showsCategory: showsCategory, search: search, onDeadline: { deadlineTask = task },
                    onEdit: { openEditor(task.id) })
            .listRowInsets(Theme.contentRowInsets)
            .listRowSeparator(.hidden)
            .listRowBackground(Theme.background)
        }
    }

}

private struct CollectionSearch: ViewModifier {
    let enabled: Bool
    @Binding var search: String

    func body(content: Content) -> some View {
        if enabled {
            content.searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search")
        } else {
            content
        }
    }
}

#Preview {
    PreviewHost(seedTasks: [PreviewHost.SeedTask(title: "Pay the invoice")])
}
