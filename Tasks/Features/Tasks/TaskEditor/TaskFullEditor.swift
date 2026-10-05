import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TaskFullEditor: View {
    @Bindable var session: TaskEditingSession
    var returnsToQuickCreation = false
    var onBack: (() -> Void)? = nil
    let onSaved: () -> Void
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .body) private var minimumDocumentHeight: CGFloat = 200
    @FocusState private var titleFocused: Bool
    @State private var keyboardVisible = false
    @State private var panel: Panel?
    private enum Panel: String, Identifiable {
        case category, date, time, reminder, calendar
        var id: Self { self }
    }
    @State private var showingDiscard = false
    @State private var showingPhotos = false
    @State private var showingVideos = false
    @State private var showingFiles = false
    @State private var showingLink = false
    @State private var link = "https://"
    @State private var photos: [PhotosPickerItem] = []
    @State private var videos: [PhotosPickerItem] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                editorContent
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle(session.original == nil ? Text("Nova tarefa") : Text("Editar tarefa"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) {
                    toolStrip { compactTools }
                }
                ToolbarItem(placement: .keyboard) {
                    if !session.editor.isEditing {
                        toolStrip { keyboardTools }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: close) {
                        Label(returnsToQuickCreation ? AppLocalization.string("Voltar") : AppLocalization.string("Fechar"), systemImage: returnsToQuickCreation ? "chevron.left" : "xmark")
                    }
                        .labelStyle(.iconOnly)
                        .tint(Theme.textPrimary)
                        .disabled(session.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        endEditing()
                        Task { if await session.save(using: viewModel) { onSaved() } }
                    } label: {
                        if session.isSaving {
                            ProgressView().tint(Theme.textSecondary)
                        } else {
                            Image(systemName: Theme.Icon.checkmark)
                                .frame(minWidth: Theme.Editor.toolbarTouchTarget, minHeight: Theme.Editor.toolbarTouchTarget)
                        }
                    }
                    .buttonStyle(PrimaryActionStyle())
                    .disabled(!session.canSave)
                    .accessibilityLabel("Salvar")
                    .accessibilityIdentifier("task.saveDocument")
                }
            }
            .toolbar(keyboardVisible ? .hidden : .visible, for: .bottomBar)
        }
        .foregroundStyle(Theme.textPrimary)
        .tint(Theme.accent)
        .disabled(session.isSaving)
        .interactiveDismissDisabled(session.hasChanges || session.isImporting || session.isSaving)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in keyboardVisible = true }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in keyboardVisible = false }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
            session.editor.textView.scrollRangeToVisible(session.editor.textView.selectedRange)
        }
        .photosPicker(isPresented: $showingPhotos, selection: $photos, matching: .images, preferredItemEncoding: .current)
        .photosPicker(isPresented: $showingVideos, selection: $videos, matching: .videos, preferredItemEncoding: .current)
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            session.importPhotos(items, kind: .image)
            photos = []
        }
        .onChange(of: videos) { _, items in
            guard !items.isEmpty else { return }
            session.importPhotos(items, kind: .video)
            videos = []
        }
        .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): session.importFiles(urls)
            case .failure(let error): session.errorMessage = error.localizedDescription
            }
        }
        .sheet(item: Binding(get: { session.editor.selectedAttachment }, set: { session.editor.selectedAttachment = $0 })) { attachment in
            TaskAttachmentPreview(attachment: attachment, sessionID: session.id, mediaStore: session.mediaStore) { session.editor.remove(attachment) }
        }
        .alert("Inserir link", isPresented: $showingLink) {
            TextField("URL", text: $link).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
            Button("Inserir") {
                if !session.editor.insertLink(link) { session.errorMessage = AppLocalization.string("Digite um link válido, como https://example.com.") }
            }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Descartar alterações?", isPresented: $showingDiscard) {
            Button("Descartar", role: .destructive) { Task { await session.discard(); dismiss() } }
            Button("Continuar editando", role: .cancel) {}
        }
        .alert("Erro no editor", isPresented: Binding(get: { session.errorMessage != nil }, set: { if !$0 { session.errorMessage = nil } })) {
            Button("OK", role: .cancel) { session.errorMessage = nil }
        } message: { Text(session.errorMessage ?? "") }
        .sheet(item: $panel) { panel in
            panelContent(panel)
        }
        .onAppear {
            session.editor.installKeyboardToolbar { action in
                switch action {
                case .photo: showingPhotos = true
                case .video: showingVideos = true
                case .file: session.editor.textView.resignFirstResponder(); showingFiles = true
                case .link: showingLink = true
                case .category: showPanel(.category)
                case .date: showPanel(.date)
                case .time: showPanel(.time)
                case .reminder: showPanel(.reminder)
                case .calendar: showPanel(.calendar)
                case .preview(let attachment): session.editor.selectedAttachment = attachment
                }
            }
        }
        .onDisappear { session.editor.removeKeyboardToolbar() }
        .task { session.editor.hydrate(sessionID: session.id, mediaStore: session.mediaStore) }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            TextField("O que precisa ser feito?", text: $session.draft.title,
                      prompt: Text("O que precisa ser feito?").foregroundStyle(Theme.textSecondary),
                      axis: .vertical)
                .font(Theme.Typography.headline)
                .lineLimit(1...4)
                .padding(.horizontal, Theme.pageMargin)
                .padding(.top, Theme.Spacing.sm)
                .focused($titleFocused)
                .accessibilityIdentifier("task.title")
            if let error = session.editor.errorMessage {
                Text(error)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.error)
                    .padding(.horizontal, Theme.pageMargin)
            }
            Divider().padding(.horizontal, Theme.pageMargin)
            ZStack(alignment: .topLeading) {
                RichTaskEditor(state: session.editor)
                    .frame(minHeight: minimumDocumentHeight, alignment: .top)
                    .allowsHitTesting(!session.isImporting)
                if session.editor.isEmpty {
                    Text("Escreva suas notas…")
                        .font(Theme.Typography.body)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Theme.pageMargin)
                        .padding(.vertical, Theme.Spacing.md)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            if session.isImporting {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    ProgressView(value: Double(session.importedCount), total: Double(max(session.importCount, 1)))
                    Text("Importando arquivos").font(Theme.Typography.footnote)
                    Button("Cancelar") { session.cancelImport() }
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                }
                .padding(.horizontal, Theme.pageMargin)
            }
            PersistenceErrorBanner()
                .padding(.horizontal, Theme.pageMargin)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func panelContent(_ panel: Panel) -> some View {
        @Bindable var session = session
        switch panel {
        case .category:
            TaskIconSelectionSheet(selection: $session.draft.icon)
        case .date:
            TaskPropertiesView(session: session, editingProperty: .date)
        case .time:
            TaskPropertiesView(session: session, editingProperty: .time)
        case .reminder:
            TaskPropertiesView(session: session, editingProperty: .reminder)
        case .calendar:
            NavigationStack {
                ScrollView {
                    TaskCalendarOptions(session: session)
                        .padding(Theme.pageMargin)
                }
                .accessibilityIdentifier("task.editor.calendarPanel")
                .background(Theme.background)
                .navigationTitle("Calendar")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { self.panel = nil }
                            .tint(Theme.textPrimary)
                            .accessibilityIdentifier("task.property.done")
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private func showPanel(_ panel: Panel) {
        endEditing()
        self.panel = panel
    }

    private func endEditing() {
        titleFocused = false
        session.editor.textView.resignFirstResponder()
    }

    private func toolStrip<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: Theme.Spacing.xxs, content: content)
        }
        .scrollIndicators(.visible)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var compactTools: some View {
        formattingMenu
        attachmentMenu.disabled(session.isImporting)
        categoryTool
        tool("Data", symbol: "calendar") { showPanel(.date) }
            .accessibilityIdentifier("task.editor.date")
        tool("Horário", symbol: "clock") { showPanel(.time) }
            .accessibilityIdentifier("task.editor.time")
        tool("Lembrete", symbol: "bell") { showPanel(.reminder) }
            .accessibilityIdentifier("task.editor.reminder")
        tool("Adicionar ao calendário", symbol: "calendar.badge.plus") { showPanel(.calendar) }
            .accessibilityIdentifier("task.editor.calendar")
    }

    @ViewBuilder
    private var keyboardTools: some View {
        compactTools
        tool("Ocultar teclado", symbol: "keyboard.chevron.compact.down", action: endEditing)
    }

    private var categoryTool: some View {
        tool("Categoria", symbol: session.draft.icon?.rawValue ?? "tag") { showPanel(.category) }
            .accessibilityValue(session.draft.icon?.title ?? AppLocalization.string("Sem categoria"))
            .accessibilityIdentifier("task.iconPicker")
    }

    private var formattingMenu: some View {
        Menu {
            Toggle("Negrito", isOn: Binding(get: { session.editor.bold }, set: { _ in session.editor.toggleFont(.traitBold) }))
            Toggle("Itálico", isOn: Binding(get: { session.editor.italic }, set: { _ in session.editor.toggleFont(.traitItalic) }))
            Toggle("Sublinhado", isOn: Binding(get: { session.editor.underlined }, set: { _ in session.editor.toggleUnderline() }))
            Button("Lista com marcadores", systemImage: "list.bullet") { session.editor.list(numbered: false) }
            Button("Lista numerada", systemImage: "list.number") { session.editor.list(numbered: true) }
            Button("Desfazer", systemImage: "arrow.uturn.backward") { session.editor.textView.undoManager?.undo() }
            Button("Refazer", systemImage: "arrow.uturn.forward") { session.editor.textView.undoManager?.redo() }
        } label: { toolLabel("Formatação", symbol: "textformat") }
        .disabled(session.isImporting)
    }

    private var attachmentMenu: some View {
        Menu {
            Button("Adicionar foto", systemImage: "photo") { showingPhotos = true }
            Button("Adicionar vídeo", systemImage: "video") { showingVideos = true }
            Button("Adicionar arquivo", systemImage: "doc") { session.editor.textView.resignFirstResponder(); showingFiles = true }
            Button("Inserir link", systemImage: "link") { showingLink = true }
            if !session.editor.attachments.isEmpty {
                Section("Anexos") {
                    ForEach(session.editor.attachments) { attachment in
                        Button(attachment.filename) { session.editor.selectedAttachment = attachment }
                    }
                }
            }
        } label: { toolLabel("Adicionar anexo", symbol: "paperclip") }
    }

    private func toolLabel(_ label: LocalizedStringKey, symbol: String) -> some View {
        Label(label, systemImage: symbol)
            .labelStyle(.iconOnly)
            .font(Theme.Typography.toolbarIcon)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(minWidth: Theme.Editor.toolbarTouchTarget, minHeight: Theme.Editor.toolbarTouchTarget)
            .foregroundStyle(Theme.textPrimary)
            .contentShape(Rectangle())
            .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
    }

    private func tool(_ label: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(Theme.Typography.toolbarIcon)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(minWidth: Theme.Editor.toolbarTouchTarget, minHeight: Theme.Editor.toolbarTouchTarget)
                .foregroundStyle(Theme.textPrimary)
                .contentShape(Rectangle())
        }
        .disabled(session.isImporting)
        .accessibilityLabel(Text(label))
        .accessibilityShowsLargeContentViewer { Label(label, systemImage: symbol) }
    }

    private func close() {
        endEditing()
        if returnsToQuickCreation {
            if let onBack { onBack() } else { dismiss() }
        } else if session.hasChanges || session.isImporting { showingDiscard = true }
        else { Task { await session.discard(); dismiss() } }
    }
}
