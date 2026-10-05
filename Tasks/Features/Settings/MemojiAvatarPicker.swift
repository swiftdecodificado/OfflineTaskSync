import SwiftUI
import UIKit

struct MemojiAvatarPicker: View {
    let onSelect: (Data) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Data?
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.md) {
                    Text("Abra o teclado Emoji e escolha seu Memoji nos adesivos.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    MemojiInput { selection = $0 }
                        .frame(height: 160)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card))
                    if let selection, let image = UIImage(data: selection) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 80, height: 80)
                            .accessibilityLabel("Avatar selecionado")
                    }
                }
                .padding(Theme.pageMargin)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background)
            .navigationTitle("Memoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Usar Memoji") {
                        guard let selection else { return }
                        do { try onSelect(selection); dismiss() }
                        catch { failed = true }
                    }
                    .disabled(selection == nil)
                }
            }
            .alert("Não foi possível atualizar o avatar.", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
        }
        .tint(Theme.accent)
        .presentationDetents([.large])
    }
}

private struct MemojiInput: UIViewRepresentable {
    let onSelect: (Data?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeUIView(context: Context) -> UITextView {
        let view = MemojiTextView()
        view.delegate = context.coordinator
        view.font = .systemFont(ofSize: 100)
        view.textAlignment = .center
        view.backgroundColor = .clear
        view.textColor = UIColor(Theme.textPrimary)
        view.tintColor = UIColor(Theme.accent)
        view.supportsAdaptiveImageGlyph = true
        view.allowsEditingTextAttributes = true
        view.pasteConfiguration = UIPasteConfiguration(forAccepting: UIImage.self)
        view.accessibilityLabel = AppLocalization.string("Escolher adesivo Memoji")
        return view
    }

    func updateUIView(_ uiView: UITextView, context: Context) {}

    final class Coordinator: NSObject, UITextViewDelegate {
        let onSelect: (Data?) -> Void
        init(onSelect: @escaping (Data?) -> Void) { self.onSelect = onSelect }

        func textViewDidChange(_ textView: UITextView) {
            let text = textView.attributedText ?? NSAttributedString(string: "")
            var selected: Data?
            text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, _ in
                if let glyph = attributes[.adaptiveImageGlyph] as? NSAdaptiveImageGlyph {
                    selected = glyph.imageContent
                } else if let attachment = attributes[.attachment] as? NSTextAttachment {
                    selected = attachment.image?.pngData() ?? attachment.contents ?? attachment.fileWrapper?.regularFileContents
                }
            }
            onSelect(selected)
        }
    }
}

private final class MemojiTextView: UITextView {
    private var didFocus = false

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil, !didFocus else { return }
        didFocus = true
        becomeFirstResponder()
    }
}
