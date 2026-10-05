import ImageIO
import SwiftUI
import UIKit

struct AvatarCropDraft: Identifiable {
    let id = UUID()
    let image: UIImage

    init(data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2048
              ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
        self.image = UIImage(cgImage: image)
    }
}

struct AvatarCropView: View {
    let image: UIImage
    let onSave: (Data) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @State private var offset = CGSize.zero
    @GestureState private var drag = CGSize.zero
    @GestureState private var magnification: CGFloat = 1
    @State private var failed = false

    private let maximumZoom: CGFloat = 4
    private var imageWidth: CGFloat { image.size.width / min(image.size.width, image.size.height) }
    private var imageHeight: CGFloat { image.size.height / min(image.size.width, image.size.height) }
    private var currentZoom: CGFloat { min(max(zoom * magnification, 1), maximumZoom) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    Text("Mova a foto e ajuste o zoom para escolher o enquadramento.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    cropPreview
                        .aspectRatio(1, contentMode: .fit)
                        .frame(maxWidth: 360)
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label("Zoom", systemImage: "plus.magnifyingglass")
                            .font(Theme.Typography.metadata)
                        Slider(value: $zoom, in: 1...maximumZoom)
                            .frame(minHeight: Theme.Metrics.minTouchTarget)
                            .accessibilityLabel("Zoom da foto")
                    }
                    Button("Redefinir enquadramento") { zoom = 1; offset = .zero }
                        .frame(minHeight: Theme.Metrics.minTouchTarget)
                }
                .padding(Theme.pageMargin)
                .frame(maxWidth: .infinity)
            }
            .background(Theme.background)
            .foregroundStyle(Theme.textPrimary)
            .navigationTitle("Ajustar foto")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Usar foto") {
                        do { try onSave(croppedImage()); dismiss() }
                        catch { failed = true }
                    }
                }
            }
            .onChange(of: zoom) { offset = clamped(offset, zoom: zoom) }
            .alert("Não foi possível atualizar o avatar.", isPresented: $failed) {
                Button("OK", role: .cancel) {}
            }
        }
        .tint(Theme.accent)
        .presentationDetents([.large])
    }

    private var cropPreview: some View {
        GeometryReader { geometry in
            let side = geometry.size.width
            let position = clamped(CGSize(width: offset.width + drag.width / side,
                                          height: offset.height + drag.height / side), zoom: currentZoom)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .frame(width: imageWidth * side * currentZoom, height: imageHeight * side * currentZoom)
                    .offset(x: position.width * side, y: position.height * side)
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    path.addEllipse(in: CGRect(origin: .zero, size: geometry.size))
                }
                .fill(Theme.background.opacity(0.8), style: FillStyle(eoFill: true))
                .allowsHitTesting(false)
                Circle()
                    .strokeBorder(Theme.textPrimary, lineWidth: Theme.Metrics.borderStroke)
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .clipped()
            .contentShape(Rectangle())
            .gesture(DragGesture()
                .updating($drag) { value, state, _ in state = value.translation }
                .onEnded { value in
                    offset = clamped(CGSize(width: offset.width + value.translation.width / side,
                                            height: offset.height + value.translation.height / side), zoom: currentZoom)
                })
            .simultaneousGesture(MagnifyGesture()
                .updating($magnification) { value, state, _ in state = value.magnification }
                .onEnded { value in
                    zoom = min(max(zoom * value.magnification, 1), maximumZoom)
                    offset = clamped(offset, zoom: zoom)
                })
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Prévia do avatar")
        .accessibilityAction(named: Text("Mover para a esquerda")) { move(x: -0.05, y: 0) }
        .accessibilityAction(named: Text("Mover para a direita")) { move(x: 0.05, y: 0) }
        .accessibilityAction(named: Text("Mover para cima")) { move(x: 0, y: -0.05) }
        .accessibilityAction(named: Text("Mover para baixo")) { move(x: 0, y: 0.05) }
    }

    private func move(x: CGFloat, y: CGFloat) {
        offset = clamped(CGSize(width: offset.width + x, height: offset.height + y), zoom: zoom)
    }

    private func clamped(_ offset: CGSize, zoom: CGFloat) -> CGSize {
        let horizontalLimit = max(0, (imageWidth * zoom - 1) / 2)
        let verticalLimit = max(0, (imageHeight * zoom - 1) / 2)
        return CGSize(width: min(max(offset.width, -horizontalLimit), horizontalLimit),
                      height: min(max(offset.height, -verticalLimit), verticalLimit))
    }

    private func croppedImage() throws -> Data {
        let side: CGFloat = 512
        let size = CGSize(width: imageWidth * side * zoom, height: imageHeight * side * zoom)
        let position = clamped(offset, zoom: zoom)
        let rect = CGRect(x: (side - size.width) / 2 + position.width * side,
                          y: (side - size.height) / 2 + position.height * side,
                          width: size.width, height: size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let cropped = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format)
            .image { _ in image.draw(in: rect) }
        guard let data = cropped.pngData() else { throw CocoaError(.fileWriteUnknown) }
        return data
    }
}
