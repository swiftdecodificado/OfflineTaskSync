import SwiftUI

struct TaskListView: View {
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.calendar) private var calendar
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingSettings = false
    @State private var selection: TaskCollection = .all
    @State private var composerDraft: TaskDraft?
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
            ForEach([TaskCollection.all, .upcoming]) { collection in
                Tab(value: collection) {
                    TaskCollectionView(collection: collection,
                                       selectedUpcomingDay: $selectedUpcomingDay, categoryFilter: $categoryFilter,
                                       onCreate: presentComposer, onCreateAtTime: presentScheduledComposer,
                                       onSettings: { showingSettings = true }, bottomBar: bottomNavigation)
                        .toolbar(.hidden, for: .tabBar)
                } label: {
                    Label(LocalizedStringKey(collection == .all ? "Tasks" : collection.rawValue), systemImage: collection.symbol)
                }
            }
        }
        .toolbar(.hidden, for: .tabBar)
    }

    private var bottomNavigation: some View {
        VStack(spacing: Theme.Spacing.xs) {
            completionUndoBanner
            HStack(spacing: Theme.Spacing.sm) {
                AppNavigationBar(selection: $selection)
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
        composerDraft = draft
    }

    private func presentComposer(for collection: TaskCollection, suggestedDate: Date?) {
        var draft = TaskDraft()
        if collection == .all, case .category(let category) = categoryFilter { draft.icon = category }
        if collection == .upcoming, let suggestedDate {
            draft.dueDate = calendar.startOfDay(for: suggestedDate)
            if let time = draft.dueTime {
                draft.dueTime = TaskSchedule.normalizedStart(day: suggestedDate, time: time, calendar: calendar)
            }
        }
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

private struct TaskCollectionView<BottomBar: View>: View {
    let collection: TaskCollection
    @Binding var selectedUpcomingDay: Date?
    @Binding var categoryFilter: TaskCategoryFilter
    let onCreate: (TaskCollection, Date?) -> Void
    let onCreateAtTime: (Date) -> Void
    let onSettings: () -> Void
    let bottomBar: BottomBar
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.calendar) private var calendar
    private struct TaskPresentation: Identifiable {
        let id: UUID
        let startsEditing: Bool
    }
    @State private var editingTask: TaskPresentation?
    @State private var showingReminders = false
    @State private var export: TaskExport?
    @State private var preparingExport = false
    @State private var deadlineTask: TaskSnapshot?
    @State private var showingDatePicker = false

    var body: some View {
        NavigationStack() {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                if collection == .upcoming {
                    UpcomingView(now: context.date, selectedDay: $selectedUpcomingDay,
                                 showingDatePicker: $showingDatePicker, onCreateAtTime: onCreateAtTime,
                                 onCreateOnDay: { onCreate(.upcoming, $0) }, onProfile: onSettings, onReminders: { showingReminders = true },
                                 onOpen: { openTask($0) }, onEdit: { openEditor($0) }) { deadlineTask = $0 }
                } else {
                    AllTasksView(now: context.date, categoryFilter: $categoryFilter, isExporting: preparingExport,
                                 onCreate: { onCreate(.all, nil) }, onOpen: openTask, onEdit: openEditor,
                                 onDeadline: { deadlineTask = $0 }, onSettings: onSettings,
                                 onReminders: { showingReminders = true }, onExport: prepareExport)
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                bottomBar.background(Theme.background)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingReminders) { ReminderListSheet() }
            .sheet(item: $export) { archive in
                NavigationStack {
                    ScrollView {
                        VStack(spacing: Theme.Spacing.lg) {
                            Text("Export all tasks")
                                .font(Theme.Typography.sectionTitle)
                            Text("O JSON inclui tarefas, texto formatado, prazos e referências dos anexos. Fotos, vídeos e arquivos não são incluídos.")
                                .font(Theme.Typography.body)
                            ShareLink(item: archive, preview: SharePreview("Tilo tasks")) {
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
                TaskDetailView(taskID: task.id, startsEditing: task.startsEditing)
            }
        }
    }

    private func openTask(_ id: UUID) {
        editingTask = TaskPresentation(id: id, startsEditing: false)
    }

    private func openEditor(_ id: UUID) {
        editingTask = TaskPresentation(id: id, startsEditing: true)
    }

    private func prepareExport() {
        preparingExport = true
        Task {
            export = await viewModel.prepareExport()
            preparingExport = false
        }
    }
}

#Preview {
    PreviewHost(seedTasks: [PreviewHost.SeedTask(title: "Pay the invoice")])
}
