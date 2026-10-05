import AVKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

struct TaskAttachmentPreview: View {
    let attachment: TaskAttachment
    let sessionID: UUID
    let mediaStore: TaskMediaStore
    let onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url: URL?
    @State private var player: AVPlayer?
    @State private var failure: String?
    @State private var confirmingRemoval = false

    var body: some View {
        NavigationStack {
            Group {
                if let failure {
                    ContentUnavailableView(failure, systemImage: "doc.questionmark")
                } else if let url {
                    if attachment.kind == .video {
                        VideoPlayer(player: player)
                    } else {
                        TaskQuickLook(url: url)
                    }
                } else {
                    ProgressView("Abrindo arquivo")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .navigationTitle(attachment.filename)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fechar") { dismiss() } }
                ToolbarItem(placement: .destructiveAction) {
                    Button("Remover anexo", systemImage: "trash", role: .destructive) { confirmingRemoval = true }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Text("\(UTType(attachment.contentType)?.localizedDescription ?? attachment.contentType) · \(ByteCountFormatter.string(fromByteCount: attachment.byteCount, countStyle: .file))")
                    .font(Theme.Typography.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, Theme.pageMargin)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.background)
            }
        }
        .tint(Theme.accent)
        .task {
            do {
                let file = try await mediaStore.resolve(attachment, sessionID: sessionID)
                url = file
                if attachment.kind == .video { player = AVPlayer(url: file) }
            } catch { failure = AppLocalization.string("Arquivo indisponível") }
        }
        .onDisappear { player?.pause() }
        .alert("Remover anexo?", isPresented: $confirmingRemoval) {
            Button("Remover", role: .destructive) { onRemove(); dismiss() }
            Button("Cancelar", role: .cancel) {}
        }
    }
}

private struct TaskQuickLook: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem { url as NSURL }
    }
}
