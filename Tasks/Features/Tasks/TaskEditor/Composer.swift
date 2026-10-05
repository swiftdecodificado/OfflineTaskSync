import SwiftUI

struct Composer: View {
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.dismiss) private var dismiss
    @State private var session: TaskEditingSession
    @State private var showingFullEditor = false
    @State private var showingDiscard = false
    @FocusState private var titleFocused: Bool

    init(draft: TaskDraft = TaskDraft(), mediaStore: TaskMediaStore) {
        _session = State(initialValue: TaskEditingSession(draft: draft, mediaStore: mediaStore))
    }

    var body: some View {
        Group {
            if showingFullEditor {
                TaskFullEditor(session: session, returnsToQuickCreation: true,
                               onBack: { showingFullEditor = false }) { dismiss() }
            } else {
                quickCreation
            }
        }
        .interactiveDismissDisabled(session.hasChanges || session.isImporting || session.isSaving)
        .presentationDetents(showingFullEditor || dynamicTypeSize.isAccessibilitySize
            ? [.large] : [.height(Theme.Editor.quickSheetHeight), .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var quickCreation: some View {
        @Bindable var session = session
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    TextField("O que precisa ser feito?", text: $session.draft.title,
                              prompt: Text("O que precisa ser feito?").foregroundStyle(Theme.textSecondary),
                              axis: .vertical)
                        .font(Theme.Typography.body)
                        .lineLimit(1...3)
                        .focused($titleFocused)
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xxs)
                        .foregroundStyle(Theme.textPrimary)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
                        .accessibilityIdentifier("task.newTitle")
                    TaskIconPicker(selection: $session.draft.icon) { titleFocused = false }
                    TaskPropertiesView(session: session)
                    Button {
                        titleFocused = false
                        showingFullEditor = true
                    } label: {
                        HStack(spacing: Theme.Spacing.sm) {
                            Image(systemName: "doc.richtext").font(Theme.Typography.sectionTitle)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text("Abrir editor completo").font(Theme.Typography.headline)
                                Text("Texto, fotos, vídeos e arquivos").font(Theme.Typography.footnote).foregroundStyle(Theme.highlightContent)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        .padding(Theme.pageMargin)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget, alignment: .leading)
                        .foregroundStyle(Theme.highlightContent)
                        .background(Theme.secondaryGradient, in: RoundedRectangle(cornerRadius: Theme.Radius.banner))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("task.openFullEditor")
                }
                .padding(Theme.pageMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Nova tarefa")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar", systemImage: "xmark") { close() }.labelStyle(.iconOnly)
                        .tint(Theme.textPrimary)
                        .disabled(session.isSaving)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    titleFocused = false
                    Task { if await session.save(using: viewModel) { dismiss() } }
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        if session.isSaving { ProgressView().tint(Theme.textSecondary) }
                        Text("Salvar tarefa")
                    }
                        .font(Theme.Typography.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.Metrics.minTouchTarget)
                        .padding(.horizontal, Theme.Layout.cardInset)
                        .padding(.vertical, Theme.Spacing.xxs)
                }
                .buttonStyle(PrimaryActionStyle())
                .disabled(!session.canSave)
                .accessibilityIdentifier("task.create")
                .padding(Theme.pageMargin)
                .background(Theme.background)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .disabled(session.isSaving)
        .alert("Descartar alterações?", isPresented: $showingDiscard) {
            Button("Descartar", role: .destructive) { Task { await session.discard(); dismiss() } }
            Button("Continuar editando", role: .cancel) {}
        }
        .alert("Erro ao salvar", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK", role: .cancel) { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .task { titleFocused = true }
    }

    private func close() {
        titleFocused = false
        if session.hasChanges || session.isImporting { showingDiscard = true }
        else { Task { await session.discard(); dismiss() } }
    }
}
