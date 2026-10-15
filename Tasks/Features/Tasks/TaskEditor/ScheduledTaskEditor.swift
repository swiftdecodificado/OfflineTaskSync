import SwiftUI

struct ScheduledTaskEditor: View {
    @State private var session: TaskEditingSession
    @State private var showingDiscard = false
    @FocusState private var titleFocused: Bool
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.calendar) private var calendar
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    init(draft: TaskDraft, mediaStore: TaskMediaStore) {
        _session = State(initialValue: TaskEditingSession(draft: draft, mediaStore: mediaStore))
    }

    var body: some View {
        @Bindable var session = session
        NavigationStack {
            Form {
                if let error = session.errorMessage {
                    Text(error).foregroundStyle(Theme.error)
                        .accessibilityIdentifier("task.schedule.error")
                }
                if let start = session.draft.dueTime {
                    Section("Starts") {
                        Text(start, format: Date.FormatStyle(locale: locale, calendar: calendar,
                                                            timeZone: calendar.timeZone).day().month(.wide).hour().minute())
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityIdentifier("task.schedule.start")
                    }
                    .listRowBackground(Theme.surface)
                    Section {
                        TextField("O que precisa ser feito?", text: $session.draft.title, axis: .vertical)
                            .lineLimit(1...8)
                            .frame(minHeight: Theme.Metrics.minTouchTarget)
                            .focused($titleFocused)
                            .accessibilityIdentifier("task.schedule.title")
                        TaskEndTimePicker(end: $session.draft.dueEndTime, start: start, allowsNone: false,
                                          accessibilityID: "task.schedule.end")
                        TaskIconPicker(selection: $session.draft.icon) { titleFocused = false }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .font(Theme.Typography.body)
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .contentMargins(.horizontal, Theme.pageMargin, for: .scrollContent)
            .listRowInsets(Theme.listRowInsets)
            .environment(\.defaultMinListRowHeight, Theme.Metrics.rowMinHeight)
            .scrollContentBackground(.hidden)
            .background(Theme.background)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Nova tarefa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { titleFocused = false }
                        .accessibilityIdentifier("task.schedule.dismissKeyboard")
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if session.hasChanges { showingDiscard = true }
                        else { Task { await session.discard(); dismiss() } }
                    }
                    .tint(Theme.textPrimary)
                    .accessibilityIdentifier("task.schedule.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        titleFocused = false
                        Task { if await session.save(using: viewModel) { dismiss() } }
                    }
                    .tint(Theme.textPrimary)
                    .disabled(!session.canSave)
                    .accessibilityIdentifier("task.schedule.save")
                }
            }
            .disabled(session.isSaving)
            .alert("Descartar alterações?", isPresented: $showingDiscard) {
                Button("Descartar", role: .destructive) { Task { await session.discard(); dismiss() } }
                Button("Continuar editando", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(session.hasChanges || session.isSaving)
        .task { titleFocused = true }
    }
}
