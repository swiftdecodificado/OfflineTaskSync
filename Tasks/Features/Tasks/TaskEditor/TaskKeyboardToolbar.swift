import UIKit
import SwiftUI

@MainActor
enum TaskKeyboardAction {
    case photo, video, file, link, category, date, time, reminder, calendar
    case preview(TaskAttachment)
}

@MainActor
final class TaskKeyboardToolbar: UIView {
    private weak var editor: RichTaskEditorState?
    private let onAction: (TaskKeyboardAction) -> Void
    private let tools = UIStackView()
    private let scrollView = UIScrollView()
    private var symbols: [(UIButton, String)] = []
    private var formattingButton: UIButton?
    private var attachmentButton: UIButton?
    private var menuState: MenuState?

    private struct MenuState: Equatable {
        let bold: Bool
        let italic: Bool
        let underlined: Bool
        let attachments: [TaskAttachment]
    }

    init(editor: RichTaskEditorState, onAction: @escaping (TaskKeyboardAction) -> Void) {
        self.editor = editor
        self.onAction = onAction
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: Theme.Editor.toolbarTouchTarget + Theme.Spacing.xs))
        autoresizingMask = [.flexibleWidth]
        backgroundColor = UIColor(Theme.surface)
        tintColor = UIColor(Theme.textPrimary)
        accessibilityIdentifier = "task.editor.keyboardToolbar"
        tools.axis = .horizontal
        tools.distribution = .fillEqually
        tools.spacing = Theme.Spacing.xxs
        tools.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.alwaysBounceHorizontal = false
        addSubview(scrollView)
        scrollView.addSubview(tools)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            tools.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: Theme.Spacing.xs),
            tools.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -Theme.Spacing.xs),
            tools.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Theme.Spacing.xxs),
            tools.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Theme.Spacing.xxs),
            tools.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -Theme.Spacing.xs),
            tools.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor, constant: -Theme.Spacing.md)
        ])
        formattingButton = button(AppLocalization.string("Formatação"), symbol: "textformat")
        attachmentButton = button(AppLocalization.string("Adicionar anexo"), symbol: "paperclip")
        addAction(AppLocalization.string("Categoria"), symbol: "tag", id: "task.iconPicker", event: .category)
        addAction(AppLocalization.string("Data"), symbol: "calendar", id: "task.editor.date", event: .date)
        addAction(AppLocalization.string("Horário"), symbol: "clock", id: "task.editor.time", event: .time)
        addAction(AppLocalization.string("Lembrete"), symbol: "bell", id: "task.editor.reminder", event: .reminder)
        addAction(AppLocalization.string("Adicionar ao calendário"), symbol: "calendar.badge.plus", id: "task.editor.calendar", event: .calendar)
        let hide = button(AppLocalization.string("Ocultar teclado"), symbol: "keyboard.chevron.compact.down")
        hide.addAction(UIAction { [weak editor] _ in editor?.textView.resignFirstResponder() }, for: .touchUpInside)
        updateFormatting()
        updateSymbolSizes()
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (toolbar: TaskKeyboardToolbar, _: UITraitCollection) in
            toolbar.updateSymbolSizes()
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: max(Theme.Editor.toolbarTouchTarget, UIFont.preferredFont(forTextStyle: .title3).lineHeight) + Theme.Spacing.xs)
    }

    func updateFormatting() {
        guard let editor else { return }
        let state = MenuState(bold: editor.bold, italic: editor.italic, underlined: editor.underlined,
                              attachments: editor.attachments)
        guard state != menuState else { return }
        menuState = state
        formattingButton?.menu = UIMenu(children: [
            UIAction(title: AppLocalization.string("Negrito"), image: UIImage(systemName: "bold"), state: editor.bold ? .on : .off) { [weak editor] _ in editor?.toggleFont(.traitBold) },
            UIAction(title: AppLocalization.string("Itálico"), image: UIImage(systemName: "italic"), state: editor.italic ? .on : .off) { [weak editor] _ in editor?.toggleFont(.traitItalic) },
            UIAction(title: AppLocalization.string("Sublinhado"), image: UIImage(systemName: "underline"), state: editor.underlined ? .on : .off) { [weak editor] _ in editor?.toggleUnderline() },
            UIAction(title: AppLocalization.string("Lista com marcadores"), image: UIImage(systemName: "list.bullet")) { [weak editor] _ in editor?.list(numbered: false) },
            UIAction(title: AppLocalization.string("Lista numerada"), image: UIImage(systemName: "list.number")) { [weak editor] _ in editor?.list(numbered: true) },
            UIAction(title: AppLocalization.string("Desfazer"), image: UIImage(systemName: "arrow.uturn.backward")) { [weak editor] _ in editor?.textView.undoManager?.undo() },
            UIAction(title: AppLocalization.string("Refazer"), image: UIImage(systemName: "arrow.uturn.forward")) { [weak editor] _ in editor?.textView.undoManager?.redo() }
        ])
        var attachments: [UIMenuElement] = [
            action(AppLocalization.string("Adicionar foto"), symbol: "photo", event: .photo),
            action(AppLocalization.string("Adicionar vídeo"), symbol: "video", event: .video),
            action(AppLocalization.string("Adicionar arquivo"), symbol: "doc", event: .file),
            action(AppLocalization.string("Inserir link"), symbol: "link", event: .link)
        ]
        if !editor.attachments.isEmpty {
            attachments.append(UIMenu(title: AppLocalization.string("Anexos"), children: editor.attachments.map { attachment in
                action(attachment.filename, symbol: "paperclip", event: .preview(attachment))
            }))
        }
        attachmentButton?.menu = UIMenu(children: attachments)
        formattingButton?.showsMenuAsPrimaryAction = true
        attachmentButton?.showsMenuAsPrimaryAction = true
    }

    private func button(_ title: String, symbol: String) -> UIButton {
        let button = UIButton(type: .system)
        button.accessibilityLabel = title
        button.largeContentTitle = title
        button.showsLargeContentViewer = true
        button.addInteraction(UILargeContentViewerInteraction())
        tools.addArrangedSubview(button)
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: Theme.Editor.toolbarTouchTarget).isActive = true
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: Theme.Editor.toolbarTouchTarget).isActive = true
        symbols.append((button, symbol))
        return button
    }

    private func addAction(_ title: String, symbol: String, id: String, event: TaskKeyboardAction) {
        let button = button(title, symbol: symbol)
        button.accessibilityIdentifier = id
        button.addAction(action(title, symbol: symbol, event: event), for: .touchUpInside)
    }

    private func action(_ title: String, symbol: String, event: TaskKeyboardAction) -> UIAction {
        UIAction(title: title, image: UIImage(systemName: symbol)) { [weak self] _ in self?.onAction(event) }
    }

    private func updateSymbolSizes() {
        let preferred = UIFont.preferredFont(forTextStyle: .title3, compatibleWith: traitCollection)
        let font = preferred.withSize(min(preferred.pointSize, Theme.Metrics.taskIconSize))
        let configuration = UIImage.SymbolConfiguration(font: font)
        for (button, symbol) in symbols {
            button.setImage(UIImage(systemName: symbol, withConfiguration: configuration), for: .normal)
            button.largeContentImage = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(textStyle: .largeTitle))
        }
        let height = intrinsicContentSize.height
        if frame.height != height { frame.size.height = height }
        invalidateIntrinsicContentSize()
    }
}
