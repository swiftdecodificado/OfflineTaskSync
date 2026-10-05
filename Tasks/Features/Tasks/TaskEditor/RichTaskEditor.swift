import SwiftUI
import UIKit
import Observation

private extension NSAttributedString.Key {
    static let taskAttachment = Self("TaskAttachmentID")
    static let taskTextBlock = Self("TaskTextBlockID")
}

@MainActor
private final class TaskDocumentTextView: UITextView {
    private let documentUndoManager = UndoManager()
    override var undoManager: UndoManager? { documentUndoManager }
    var onContentWidthChange: ((CGFloat) -> Void)?
    private var previousContentWidth: CGFloat = 0
    private var caretRevealTask: Task<Void, Never>?

    override func scrollRangeToVisible(_ range: NSRange) {
        caretRevealTask?.cancel()
        guard !isScrollEnabled, range.length == 0 else {
            super.scrollRangeToVisible(range)
            return
        }
        caretRevealTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(30))
                guard let self, isFirstResponder, selectedRange.length == 0,
                      let selection = selectedTextRange else { return }
                window?.layoutIfNeeded()
                let caret = caretRect(for: selection.end).insetBy(dx: 0, dy: -Theme.Spacing.md)
                var ancestor = superview
                while let view = ancestor {
                    if let scrollView = view as? UIScrollView, scrollView.isScrollEnabled {
                        scrollView.scrollRectToVisible(convert(caret, to: scrollView), animated: false)
                        return
                    }
                    ancestor = view.superview
                }
            } catch {}
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let width = bounds.width - textContainerInset.left - textContainerInset.right - textContainer.lineFragmentPadding * 2
        if width > 0, width != previousContentWidth {
            previousContentWidth = width
            onContentWidthChange?(width)
        }
    }
}

@MainActor
@Observable
final class RichTaskEditorState: NSObject, UITextViewDelegate {
    private(set) var revision = 0
    private(set) var isEditing = false
    @ObservationIgnored private weak var keyboardToolbar: TaskKeyboardToolbar?
    var selectedAttachment: TaskAttachment?
    var errorMessage: String?
    private(set) var bold = false
    private(set) var italic = false
    private(set) var underlined = false
    @ObservationIgnored private var catalog: [UUID: TaskAttachment] = [:]
    @ObservationIgnored private var thumbnailData: [UUID: Data] = [:]
    @ObservationIgnored private var hydration: Task<Void, Never>?
    @ObservationIgnored private var attachmentWidth = Theme.Editor.mediaWidth
    @ObservationIgnored let textView: UITextView = TaskDocumentTextView(usingTextLayoutManager: true)

    init(document: TaskDocument?, notes: String) {
        super.init()
        textView.delegate = self
        (textView as? TaskDocumentTextView)?.onContentWidthChange = { [weak self] width in
            self?.resizeAttachments(to: width)
        }
        textView.backgroundColor = .clear
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = UIColor(Theme.textPrimary)
        textView.tintColor = UIColor(Theme.accent)
        textView.adjustsFontForContentSizeCategory = true
        textView.allowsEditingTextAttributes = true
        textView.isScrollEnabled = false
        textView.keyboardDismissMode = .interactive
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainerInset = UIEdgeInsets(top: Theme.Spacing.md, left: Theme.pageMargin,
                                                  bottom: Theme.Spacing.xxl, right: Theme.pageMargin)
        textView.accessibilityLabel = AppLocalization.string("Conteúdo da tarefa")
        textView.accessibilityHint = AppLocalization.string("Escreva notas e insira mídia na posição do cursor.")
        textView.accessibilityIdentifier = "task.document"
        do {
            textView.attributedText = try decode(document, notes: notes)
        } catch {
            errorMessage = AppLocalization.string("Não foi possível abrir este documento.")
        }
        textView.typingAttributes = defaultAttributes
        updateTextSize()
        textView.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { [weak self] (_: UITextView, _: UITraitCollection) in
            self?.updateTextSize()
            self?.refreshAttachmentAppearance()
        }
        textView.registerForTraitChanges([UITraitUserInterfaceStyle.self, UITraitAccessibilityContrast.self]) { [weak self] (_: UITextView, _: UITraitCollection) in
            self?.refreshAttachmentAppearance()
        }
    }

    func installKeyboardToolbar(onAction: @escaping (TaskKeyboardAction) -> Void) {
        let toolbar = TaskKeyboardToolbar(editor: self, onAction: onAction)
        keyboardToolbar = toolbar
        textView.inputAccessoryView = toolbar
        if textView.isFirstResponder { textView.reloadInputViews() }
    }

    func removeKeyboardToolbar() {
        textView.inputAccessoryView = nil
        keyboardToolbar = nil
    }

    private func updateTextSize() {
        let storage = textView.textStorage
        let selection = textView.selectedRange
        let preferredSize = UIFont.preferredFont(forTextStyle: .body, compatibleWith: textView.traitCollection).pointSize
        storage.beginEditing()
        storage.enumerateAttribute(.font, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            let font = value as? UIFont ?? .preferredFont(forTextStyle: .body)
            storage.addAttribute(.font, value: UIFont(descriptor: font.fontDescriptor, size: preferredSize), range: range)
        }
        storage.endEditing()
        var typing = textView.typingAttributes
        let font = typing[.font] as? UIFont ?? .preferredFont(forTextStyle: .body)
        typing[.font] = UIFont(descriptor: font.fontDescriptor, size: preferredSize)
        textView.typingAttributes = typing
        textView.selectedRange = selection
        textView.invalidateIntrinsicContentSize()
    }

    var isEmpty: Bool {
        _ = revision
        return textView.textStorage.length == 0
    }

    var attachments: [TaskAttachment] {
        _ = revision
        var result: [TaskAttachment] = []
        textView.textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textView.textStorage.length)) { value, range, _ in
            guard value != nil else { return }
            if let raw = textView.textStorage.attribute(.taskAttachment, at: range.location, effectiveRange: nil) as? String,
               let id = UUID(uuidString: raw), let attachment = catalog[id] { result.append(attachment) }
        }
        return result
    }

    private var defaultAttributes: [NSAttributedString.Key: Any] {
        [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor(Theme.textPrimary)]
    }

    func document() throws -> TaskDocument {
        let source = textView.attributedText ?? NSAttributedString(string: "")
        var blocks: [TaskContentBlock] = []
        var start = 0
        var textIDs: Set<UUID> = []
        func appendText(until end: Int) throws {
            guard end > start else { return }
            let text = NSMutableAttributedString(attributedString: source.attributedSubstring(from: NSRange(location: start, length: end - start)))
            var id = (text.attribute(.taskTextBlock, at: 0, effectiveRange: nil) as? String).flatMap(UUID.init(uuidString:)) ?? UUID()
            if !textIDs.insert(id).inserted { id = UUID(); textIDs.insert(id) }
            textView.textStorage.addAttribute(.taskTextBlock, value: id.uuidString, range: NSRange(location: start, length: end - start))
            text.removeAttribute(.taskTextBlock, range: NSRange(location: 0, length: text.length))
            let rtf = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            blocks.append(.text(TaskRichText(id: id, rtf: rtf, plainText: text.string)))
        }
        var attachmentRanges: [(NSRange, UUID)] = []
        var unknownAttachment = false
        source.enumerateAttribute(.attachment, in: NSRange(location: 0, length: source.length)) { value, range, _ in
            guard value != nil else { return }
            guard let rawID = source.attribute(.taskAttachment, at: range.location, effectiveRange: nil) as? String,
                  let id = UUID(uuidString: rawID), catalog[id] != nil else { unknownAttachment = true; return }
            attachmentRanges.append((range, id))
        }
        guard !unknownAttachment else { throw TaskMediaError.unsupportedDocument }
        for (range, id) in attachmentRanges {
            try appendText(until: range.location)
            if let attachment = catalog[id] { blocks.append(.attachment(attachment)) }
            start = NSMaxRange(range)
        }
        try appendText(until: source.length)
        return TaskDocument(blocks: blocks)
    }

    private func decode(_ document: TaskDocument?, notes: String) throws -> NSAttributedString {
        guard let document else { return NSAttributedString(string: notes, attributes: defaultAttributes) }
        guard document.version == TaskDocument.currentVersion else { throw TaskMediaError.unsupportedDocument }
        let result = NSMutableAttributedString(string: "")
        for block in document.blocks {
            switch block {
            case .text(let text):
                let value = try NSMutableAttributedString(data: text.rtf, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil)
                value.addAttribute(.taskTextBlock, value: text.id.uuidString, range: NSRange(location: 0, length: value.length))
                value.addAttribute(.foregroundColor, value: UIColor(Theme.textPrimary), range: NSRange(location: 0, length: value.length))
                result.append(value)
            case .attachment(let attachment):
                catalog[attachment.id] = attachment
                result.append(attachmentString(attachment))
            }
        }
        return result
    }

    func hydrate(sessionID: UUID, mediaStore: TaskMediaStore) {
        hydration?.cancel()
        let attachments = Array(catalog.values)
        hydration = Task { [weak self] in
            for attachment in attachments {
                guard !Task.isCancelled, let self else { return }
                do {
                    if let data = try await mediaStore.thumbnail(attachment, sessionID: sessionID) {
                        thumbnailData[attachment.id] = data
                        refreshAttachment(attachment)
                    }
                } catch { /* The preview reports a missing original when opened. */ }
            }
        }
    }

    func insert(_ attachment: TaskAttachment, thumbnail: Data?) {
        catalog[attachment.id] = attachment
        thumbnailData[attachment.id] = thumbnail
        let value = NSMutableAttributedString(string: "\n", attributes: defaultAttributes)
        value.append(attachmentString(attachment))
        value.append(NSAttributedString(string: "\n", attributes: defaultAttributes))
        replace(textView.selectedRange, with: value)
        textView.typingAttributes = defaultAttributes
    }

    func remove(_ attachment: TaskAttachment) {
        var ranges: [NSRange] = []
        textView.textStorage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: textView.textStorage.length)) { value, range, _ in
            guard value != nil else { return }
            if textView.textStorage.attribute(.taskAttachment, at: range.location, effectiveRange: nil) as? String == attachment.id.uuidString {
                ranges.append(range)
            }
        }
        for range in ranges.reversed() { replace(range, with: NSAttributedString(string: "")) }
        selectedAttachment = nil
    }

    func toggleFont(_ trait: UIFontDescriptor.SymbolicTraits) {
        let remove = hasTrait(trait)
        mutateAttributes { attributes in
            let font = attributes[.font] as? UIFont ?? .preferredFont(forTextStyle: .body)
            var traits = font.fontDescriptor.symbolicTraits
            if remove { traits.remove(trait) } else { traits.insert(trait) }
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                attributes[.font] = UIFont(descriptor: descriptor, size: font.pointSize)
            }
        }
    }

    func toggleUnderline() {
        let remove = underlined
        mutateAttributes { attributes in
            attributes[.underlineStyle] = remove ? 0 : NSUnderlineStyle.single.rawValue
        }
    }

    private func hasTrait(_ trait: UIFontDescriptor.SymbolicTraits) -> Bool {
        guard textView.selectedRange.length > 0 else {
            return (textView.typingAttributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits.contains(trait) == true
        }
        var result = true
        textView.textStorage.enumerateAttributes(in: textView.selectedRange) { attributes, _, _ in
            if attributes[.attachment] == nil {
                let font = attributes[.font] as? UIFont ?? .preferredFont(forTextStyle: .body)
                result = result && font.fontDescriptor.symbolicTraits.contains(trait)
            }
        }
        return result
    }

    private func mutateAttributes(_ transform: (inout [NSAttributedString.Key: Any]) -> Void) {
        let range = textView.selectedRange
        if range.length == 0 {
            var attributes = textView.typingAttributes
            transform(&attributes)
            textView.typingAttributes = attributes
        } else {
            let value = NSMutableAttributedString(attributedString: textView.textStorage.attributedSubstring(from: range))
            value.enumerateAttributes(in: NSRange(location: 0, length: value.length)) { attributes, subrange, _ in
                guard attributes[.attachment] == nil else { return }
                var updated = attributes
                transform(&updated)
                value.setAttributes(updated, range: subrange)
            }
            replace(range, with: value, selection: range)
        }
        updateSelection()
        textView.becomeFirstResponder()
    }

    func insertLink(_ raw: String) -> Bool {
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(), ["https", "http", "mailto", "tel"].contains(scheme) else { return false }
        if ["http", "https"].contains(scheme), url.host?.isEmpty != false { return false }
        if ["mailto", "tel"].contains(scheme), url.path.isEmpty { return false }
        let range = textView.selectedRange
        let value: NSMutableAttributedString
        if range.length > 0 {
            value = NSMutableAttributedString(attributedString: textView.textStorage.attributedSubstring(from: range))
        } else {
            value = NSMutableAttributedString(string: url.absoluteString, attributes: textView.typingAttributes)
        }
        value.addAttribute(.link, value: url, range: NSRange(location: 0, length: value.length))
        replace(range, with: value, selection: range.length > 0 ? range : nil)
        textView.typingAttributes = defaultAttributes
        textView.becomeFirstResponder()
        return true
    }

    func list(numbered: Bool) {
        let string = textView.textStorage.string as NSString
        let selection = textView.selectedRange
        let range = string.paragraphRange(for: selection)
        let value = NSMutableAttributedString(attributedString: textView.textStorage.attributedSubstring(from: range))
        let paragraphs = value.string.components(separatedBy: "\n")
        var offset = 0
        var number = 1
        var edits: [(NSRange, String)] = []
        let pattern = numbered ? #"^\d+\.\s"# : #"^•\s"#
        let regex = try? NSRegularExpression(pattern: pattern)
        let nonempty = paragraphs.enumerated().filter { $0.offset < paragraphs.count - 1 || !$0.element.isEmpty || paragraphs.count == 1 }
        let remove = !nonempty.isEmpty && nonempty.allSatisfy { part in
            regex?.firstMatch(in: part.element, range: NSRange(location: 0, length: (part.element as NSString).length)) != nil
        }
        for part in nonempty {
            let length = (part.element as NSString).length
            let existing = part.element.range(of: #"^(• |\d+\. )"#, options: .regularExpression)
            let old = existing.map { (String(part.element[$0]) as NSString).length } ?? 0
            edits.append((NSRange(location: offset, length: old), remove ? "" : (numbered ? "\(number). " : "• ")))
            offset += length + 1
            number += 1
        }
        for (edit, prefix) in edits.reversed() { value.replaceCharacters(in: edit, with: NSAttributedString(string: prefix, attributes: defaultAttributes)) }
        func mapped(_ index: Int) -> Int {
            var result = index
            for (edit, prefix) in edits {
                let location = range.location + edit.location
                if index >= location {
                    result += (prefix as NSString).length - min(edit.length, index - location)
                }
            }
            return result
        }
        let location = mapped(selection.location)
        let end = mapped(NSMaxRange(selection))
        replace(range, with: value, selection: NSRange(location: location, length: max(0, end - location)))
        textView.becomeFirstResponder()
    }

    func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
        guard text == "\n", range.length == 0 else { return true }
        let source = textView.textStorage.string as NSString
        let paragraph = source.paragraphRange(for: NSRange(location: range.location, length: 0))
        let line = source.substring(with: NSRange(location: paragraph.location, length: range.location - paragraph.location))
        guard let match = line.range(of: #"^(• |\d+\. )"#, options: .regularExpression) else { return true }
        let prefix = String(line[match])
        if line == prefix {
            replace(NSRange(location: paragraph.location, length: (prefix as NSString).length), with: NSAttributedString(string: ""))
        } else {
            let next = prefix.hasPrefix("•") ? "• " : "\((Int(prefix.dropLast(2)) ?? 0) + 1). "
            replace(range, with: NSAttributedString(string: "\n" + next, attributes: textView.typingAttributes))
        }
        return false
    }

    func textViewDidBeginEditing(_ textView: UITextView) { isEditing = true }
    func textViewDidEndEditing(_ textView: UITextView) { isEditing = false }

    func textViewDidChange(_ textView: UITextView) {
        revision += 1
        updateSelection()
        textView.invalidateIntrinsicContentSize()
        textView.scrollRangeToVisible(textView.selectedRange)
    }

    func textViewDidChangeSelection(_ textView: UITextView) {
        updateSelection()
        textView.scrollRangeToVisible(textView.selectedRange)
    }

    private func updateSelection() {
        var attributes = textView.typingAttributes
        if attributes[.taskAttachment] != nil || attributes[.attachment] != nil {
            attributes.removeValue(forKey: .taskAttachment)
            attributes.removeValue(forKey: .attachment)
            textView.typingAttributes = attributes
        }
        bold = hasTrait(.traitBold)
        italic = hasTrait(.traitItalic)
        underlined = (attributes[.underlineStyle] as? Int ?? 0) != 0
        keyboardToolbar?.updateFormatting()
    }

    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        if case .textAttachment = textItem.content,
           textItem.range.location < textView.textStorage.length,
           let raw = textView.textStorage.attribute(.taskAttachment, at: textItem.range.location, effectiveRange: nil) as? String,
           let id = UUID(uuidString: raw), let attachment = catalog[id] {
            return UIAction(title: AppLocalization.string("Abrir anexo")) { [weak self] _ in self?.selectedAttachment = attachment }
        }
        return defaultAction
    }

    private func replace(_ range: NSRange, with value: NSAttributedString, selection: NSRange? = nil) {
        guard NSMaxRange(range) <= textView.textStorage.length else { return }
        let old = textView.textStorage.attributedSubstring(from: range)
        let previousSelection = textView.selectedRange
        let inverse = NSRange(location: range.location, length: value.length)
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.replace(inverse, with: old, selection: previousSelection)
        }
        textView.textStorage.replaceCharacters(in: range, with: value)
        textView.selectedRange = selection ?? NSRange(location: range.location + value.length, length: 0)
        textView.scrollRangeToVisible(textView.selectedRange)
        revision += 1
        updateSelection()
    }

    private func attachmentString(_ attachment: TaskAttachment) -> NSAttributedString {
        let item = NSTextAttachment()
        item.image = attachmentImage(attachment)
        item.bounds = attachmentBounds(for: attachment, image: item.image)
        let value = NSMutableAttributedString(attachment: item)
        value.addAttribute(.taskAttachment, value: attachment.id.uuidString, range: NSRange(location: 0, length: value.length))
        return value
    }

    private func refreshAttachment(_ attachment: TaskAttachment) {
        textView.textStorage.enumerateAttribute(.taskAttachment, in: NSRange(location: 0, length: textView.textStorage.length)) { value, range, _ in
            guard value as? String == attachment.id.uuidString,
                  let item = textView.textStorage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment else { return }
            item.image = attachmentImage(attachment)
            item.bounds = attachmentBounds(for: attachment, image: item.image)
            textView.textStorage.addAttribute(.attachment, value: item, range: range)
        }
        textView.invalidateIntrinsicContentSize()
    }

    private func refreshAttachmentAppearance() {
        textView.traitCollection.performAsCurrent {
            for attachment in catalog.values { refreshAttachment(attachment) }
        }
    }

    private func attachmentBounds(for attachment: TaskAttachment, image: UIImage?) -> CGRect {
        let maximumWidth = attachment.kind == .file ? Theme.Editor.mediaWidth : Theme.Editor.mediaMaximumWidth
        let width = min(attachmentWidth, maximumWidth)
        let imageSize = image?.size ?? CGSize(width: Theme.Editor.mediaWidth, height: Theme.Editor.mediaHeight)
        return CGRect(x: 0, y: 0, width: width, height: width * imageSize.height / max(imageSize.width, 1))
    }

    private func resizeAttachments(to width: CGFloat) {
        attachmentWidth = width
        let storage = textView.textStorage
        storage.beginEditing()
        storage.enumerateAttribute(.attachment, in: NSRange(location: 0, length: storage.length)) { value, range, _ in
            guard let item = value as? NSTextAttachment,
                  let raw = storage.attribute(.taskAttachment, at: range.location, effectiveRange: nil) as? String,
                  let id = UUID(uuidString: raw), let attachment = catalog[id] else { return }
            let bounds = attachmentBounds(for: attachment, image: item.image)
            if item.bounds != bounds {
                item.bounds = bounds
                storage.addAttribute(.attachment, value: item, range: range)
            }
        }
        storage.endEditing()
        textView.invalidateIntrinsicContentSize()
    }

    private func attachmentImage(_ attachment: TaskAttachment) -> UIImage {
        if attachment.kind != .file {
            guard let data = thumbnailData[attachment.id], let preview = UIImage(data: data) else {
                return UIImage(systemName: attachment.kind == .image ? "photo" : "video")?
                    .withTintColor(UIColor(Theme.textSecondary), renderingMode: .alwaysOriginal) ?? UIImage()
            }
            if attachment.kind == .image { return preview }
            return videoPreview(preview, duration: attachment.duration)
        }
        let size = CGSize(width: Theme.Editor.mediaWidth, height: Theme.Editor.mediaHeight)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(Theme.surface).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIImage(systemName: "doc")?.withTintColor(UIColor(Theme.textSecondary), renderingMode: .alwaysOriginal)
                .draw(in: CGRect(x: Theme.Spacing.md, y: Theme.Spacing.md, width: Theme.Metrics.minTouchTarget, height: Theme.Metrics.minTouchTarget))
            (attachment.filename as NSString).draw(in: CGRect(x: Theme.Spacing.xs, y: size.height - Theme.Editor.captionHeight,
                                              width: size.width - Theme.Spacing.md, height: Theme.Editor.captionHeight),
                                    withAttributes: [.font: UIFont.preferredFont(forTextStyle: .caption1), .foregroundColor: UIColor(Theme.textPrimary)])
        }
    }

    private func videoPreview(_ image: UIImage, duration: Double?) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
            let side = min(Theme.Metrics.minTouchTarget, min(image.size.width, image.size.height))
            let button = CGRect(x: (image.size.width - side) / 2, y: (image.size.height - side) / 2, width: side, height: side)
            UIColor(Theme.surface).setFill()
            UIBezierPath(ovalIn: button).fill()
            UIImage(systemName: "play.fill")?.withTintColor(UIColor(Theme.textPrimary), renderingMode: .alwaysOriginal)
                .draw(in: button.insetBy(dx: Theme.Spacing.sm, dy: Theme.Spacing.sm))
            if let duration {
                let label = "\(Int(duration) / 60):\(String(format: "%02d", Int(duration) % 60))" as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.preferredFont(forTextStyle: .caption1), .foregroundColor: UIColor(Theme.textPrimary)]
                let measured = label.size(withAttributes: attributes)
                let pill = CGRect(x: max(0, image.size.width - measured.width - Theme.Spacing.xl),
                                  y: max(0, image.size.height - measured.height - Theme.Spacing.xl),
                                  width: measured.width + Theme.Spacing.md, height: measured.height + Theme.Spacing.md)
                UIBezierPath(roundedRect: pill, cornerRadius: Theme.Radius.banner).fill()
                label.draw(at: CGPoint(x: pill.minX + Theme.Spacing.xs, y: pill.minY + Theme.Spacing.xs), withAttributes: attributes)
            }
        }
    }

}

struct RichTaskEditor: UIViewRepresentable {
    let state: RichTaskEditorState

    func makeUIView(context: Context) -> UITextView { state.textView }
    func updateUIView(_ uiView: UITextView, context: Context) {
        _ = state.revision
        uiView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(ceil(size.height), proposal.height ?? 0))
    }
}
