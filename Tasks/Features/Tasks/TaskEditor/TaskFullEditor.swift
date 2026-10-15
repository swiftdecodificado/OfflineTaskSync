import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct TaskFullEditor: View {
    @Bindable var session: TaskEditingSession
    var isReadOnly = false
    var onEdit: (() -> Void)? = nil
    let onSaved: () -> Void
    @Environment(TasksViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
            .navigationTitle(isReadOnly ? Text("Tarefa") : session.original == nil ? Text("Nova tarefa") : Text("Editar tarefa"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isReadOnly {
                    ToolbarItem(placement: .bottomBar) {
                        toolStrip { compactTools }
                    }
                    ToolbarItem(placement: .keyboard) {
                        if !session.editor.isEditing { toolStrip { keyboardTools } }
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: close) { Label("Fechar", systemImage: "xmark") }
                        .labelStyle(.iconOnly)
                        .tint(Theme.textPrimary)
                        .disabled(session.isSaving)
                }
                if !isReadOnly {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        reminderButton
                        calendarButton
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isReadOnly {
                        Button("Edit Task", systemImage: "pencil") { onEdit?() }
                            .accessibilityIdentifier("task.editDocument")
                    } else {
                        Button {
                            endEditing()
                            Task { if await session.save(using: viewModel) { onSaved() } }
                        } label: {
                            if session.isSaving {
                                ProgressView().tint(Theme.textSecondary)
                            } else {
                                Text("Salvar")
                                    .padding(.horizontal, Theme.Spacing.sm)
                                    .frame(minHeight: Theme.Editor.toolbarTouchTarget)
                            }
                        }
                        .buttonStyle(PrimaryActionStyle())
                        .disabled(!session.canSave)
                        .accessibilityLabel("Salvar")
                        .accessibilityIdentifier("task.saveDocument")
                    }
                }
            }
            .toolbar(isReadOnly || keyboardVisible || session.editor.isEditing || titleFocused ? .hidden : .visible, for: .bottomBar)
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
            TaskAttachmentPreview(attachment: attachment, sessionID: session.id, mediaStore: session.mediaStore,
                                  allowsRemoval: !isReadOnly) {
                if !isReadOnly { session.editor.remove(attachment) }
            }
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
        .onChange(of: isReadOnly, initial: true) { _, reading in
            if reading {
                endEditing()
                session.editor.removeKeyboardToolbar()
            } else {
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
                if session.original != nil { titleFocused = true }
            }
        }
        .onDisappear { session.editor.removeKeyboardToolbar() }
        .task {
            session.editor.hydrate(sessionID: session.id, mediaStore: session.mediaStore)
            if !isReadOnly && session.original == nil && session.draft.title.isEmpty { titleFocused = true }
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Group {
                if isReadOnly {
                    Text(session.draft.title)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("task.readTitle")
                } else {
                    TextField("O que precisa ser feito?", text: $session.draft.title,
                              prompt: Text("O que precisa ser feito?").foregroundStyle(Theme.textSecondary), axis: .vertical)
                        .lineLimit(1...4)
                        .focused($titleFocused)
                        .accessibilityIdentifier("task.title")
                }
            }
            .font(Theme.Typography.editorTitle)
            .padding(.horizontal, Theme.pageMargin)
            .padding(.top, Theme.Spacing.sm)
            if let error = session.editor.errorMessage {
                Text(error)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.error)
                    .padding(.horizontal, Theme.pageMargin)
            }
            taskProperties
                .padding(.horizontal, Theme.pageMargin)
            Divider().padding(.horizontal, Theme.pageMargin)
            ZStack(alignment: .topLeading) {
                RichTaskEditor(state: session.editor, isEditable: !isReadOnly)
                    .frame(minHeight: minimumDocumentHeight, alignment: .top)
                    .allowsHitTesting(!session.isImporting)
                if session.editor.isEmpty {
                    Text(isReadOnly ? LocalizedStringKey("Sem descrição") : LocalizedStringKey("Escreva suas notas…"))
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
    }

    @ViewBuilder
    private var keyboardTools: some View {
        compactTools
        tool("Ocultar teclado", symbol: "keyboard.chevron.compact.down", action: endEditing)
    }

    private var taskProperties: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.xs))
        return ScrollView(.horizontal) {
            layout {
                propertyChip("Categoria", value: session.draft.icon?.title ?? AppLocalization.string("Sem categoria"),
                             symbol: session.draft.icon?.rawValue ?? "tag", panel: .category, id: "task.iconPicker")
                propertyChip("Data", value: session.draft.dueDate?.formatted(dateFormat.day().month(.abbreviated)) ?? AppLocalization.string("Data"),
                             symbol: "calendar", panel: .date, id: "task.editor.date")
                propertyChip("Horário", value: session.draft.dueTime?.formatted(dateFormat.hour().minute()) ?? AppLocalization.string("Horário"),
                             symbol: "clock", panel: .time, id: "task.editor.time")
            }
        }
        .scrollIndicators(.hidden)
    }

    private var dateFormat: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }

    private func propertyChip(_ title: LocalizedStringKey, value: String, symbol: String, panel: Panel, id: String) -> some View {
        Group {
            if isReadOnly {
                propertyLabel(value, symbol: symbol)
            } else {
                Button { showPanel(panel) } label: {
                    propertyLabel(value, symbol: symbol)
                }
                .buttonStyle(.plain)
                .disabled(session.isImporting)
            }
        }
        .accessibilityLabel(Text(title))
        .accessibilityValue(value)
        .accessibilityIdentifier(id)
    }

    private func propertyLabel(_ value: String, symbol: String) -> some View {
        Label(value, systemImage: symbol)
            .font(Theme.Typography.footnote)
            .fixedSize(horizontal: true, vertical: true)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(minHeight: Theme.Metrics.minTouchTarget)
            .foregroundStyle(Theme.textPrimary)
            .background(Theme.surfaceSecondary, in: Capsule())
    }

    private var hasCalendarEvent: Bool {
        session.original?.calendarEventID?.isEmpty == false
    }

    private var calendarButton: some View {
        let selected = hasCalendarEvent || session.draft.addToCalendar
        return Button {
            if hasCalendarEvent { viewModel.checkCalendarLink(id: session.draft.id) }
            else { session.draft.addToCalendar.toggle() }
        } label: {
            Label("Adicionar ao calendário", systemImage: selected ? "calendar.badge.checkmark" : "calendar.badge.plus")
                .labelStyle(.iconOnly)
                .font(Theme.Typography.toolbarIcon)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                .foregroundStyle(selected ? Theme.onAccent : Theme.textPrimary)
                .background(selected ? Theme.actionBackground : Color.clear, in: Circle())
        }
        .disabled(session.isImporting || session.draft.dueDate == nil)
        .accessibilityValue(hasCalendarEvent ? Text("Linked to Calendar")
                             : session.draft.addToCalendar ? Text("Será adicionado ao salvar") : Text("Não adicionado"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu {
            if hasCalendarEvent {
                Button("Check Calendar link", systemImage: "arrow.clockwise") {
                    viewModel.checkCalendarLink(id: session.draft.id)
                }
            } else {
                Button("Escolher calendário", systemImage: "calendar") { showPanel(.calendar) }
            }
        }
        .accessibilityLabel(hasCalendarEvent ? Text("Check Calendar link")
                            : selected ? Text("Não adicionar ao calendário") : Text("Adicionar ao calendário"))
        .accessibilityIdentifier("task.editor.calendar")
    }

    private var reminderButton: some View {
        Button { showPanel(.reminder) } label: {
            Label("Lembrete", systemImage: session.draft.reminderDate == nil ? "bell" : "bell.badge.fill")
                .labelStyle(.iconOnly)
                .font(Theme.Typography.toolbarIcon)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .frame(minWidth: Theme.Metrics.minTouchTarget, minHeight: Theme.Metrics.minTouchTarget)
                .foregroundStyle(session.draft.reminderDate == nil ? Theme.textPrimary : Theme.accent)
        }
        .disabled(session.isImporting)
        .accessibilityValue(session.draft.reminderDate?.formatted(dateFormat.day().month(.abbreviated).hour().minute())
                            ?? AppLocalization.string("Não definido"))
        .accessibilityIdentifier("task.editor.reminder")
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
        } label: { toolLabel("Texto", symbol: "textformat") }
        .accessibilityIdentifier("task.editor.formatting")
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
        } label: { toolLabel("Anexos", symbol: "paperclip") }
        .accessibilityIdentifier("task.editor.attachments")
    }

    private func toolLabel(_ label: LocalizedStringKey, symbol: String) -> some View {
        Label(label, systemImage: symbol)
            .labelStyle(.titleAndIcon)
            .font(Theme.Typography.metadata)
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
        if !isReadOnly && (session.hasChanges || session.isImporting) { showingDiscard = true }
        else { Task { await session.discard(); dismiss() } }
    }
}
