import AVFoundation
import CoreTransferable
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct PickedTaskMedia: Transferable, Sendable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .image) { received in
            try copy(received.file)
        }
        FileRepresentation(importedContentType: .movie) { received in
            try copy(received.file)
        }
    }

    private static func copy(_ source: URL) throws -> Self {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("TaskTransfers", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: destination)
        return Self(url: destination)
    }
}

enum TaskMediaError: LocalizedError {
    case unavailable, invalidFile, unsupportedDocument

    var errorDescription: String? {
        switch self {
        case .unavailable: AppLocalization.string("Arquivo indisponível")
        case .invalidFile: AppLocalization.string("Não foi possível importar o arquivo. Verifique o espaço disponível e tente novamente.")
        case .unsupportedDocument: AppLocalization.string("Não foi possível abrir este documento.")
        }
    }
}

actor TaskMediaStore {
    static let shared = TaskMediaStore(
        root: URL.applicationSupportDirectory.appendingPathComponent("TaskMedia", isDirectory: true),
        transferCleanupDirectory: FileManager.default.temporaryDirectory.appendingPathComponent("TaskTransfers")
    )
    private let root: URL
    private let transferCleanupDirectory: URL?
    private let manager = FileManager.default

    init(root: URL, transferCleanupDirectory: URL? = nil) {
        self.root = root
        self.transferCleanupDirectory = transferCleanupDirectory
    }

    func importFile(_ source: URL, kind: TaskAttachment.Kind, sessionID: UUID) async throws -> TaskAttachment {
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let id = UUID()
        let directory = staging(sessionID).appendingPathComponent(id.uuidString, isDirectory: true)
        do {
            try Task.checkCancellation()
            try manager.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = source.lastPathComponent
            let storedName = source.pathExtension.isEmpty ? "original" : "original.\(source.pathExtension)"
            let file = directory.appendingPathComponent(storedName)
            try manager.copyItem(at: source, to: file)
            try Task.checkCancellation()
            let values = try file.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw TaskMediaError.invalidFile }
            var thumbnail: String?
            var duration: Double?
            let previewURL = directory.appendingPathComponent("preview.jpg")
            if kind == .image {
                guard let image = Self.imageThumbnail(file) else { throw TaskMediaError.invalidFile }
                try Self.writeJPEG(image, to: previewURL)
                thumbnail = "\(id.uuidString)/preview.jpg"
            } else if kind == .video {
                let asset = AVURLAsset(url: file)
                let seconds = try await asset.load(.duration).seconds
                duration = seconds.isFinite ? seconds : nil
                let generator = AVAssetImageGenerator(asset: asset)
                generator.appliesPreferredTrackTransform = true
                generator.maximumSize = CGSize(width: 640, height: 640)
                let frame = try await generator.image(at: .zero)
                try Self.writeJPEG(frame.image, to: previewURL)
                thumbnail = "\(id.uuidString)/preview.jpg"
            }
            try Task.checkCancellation()
            return TaskAttachment(id: id, kind: kind, relativePath: "\(id.uuidString)/\(storedName)",
                                  thumbnailPath: thumbnail, filename: name,
                                  contentType: values.contentType?.identifier ?? UTType.data.identifier,
                                  byteCount: Int64(values.fileSize ?? 0), duration: duration)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    func exportForSync(_ task: TaskSnapshot) throws -> RemoteTaskSnapshot {
        var snapshot = RemoteTaskSnapshot(task)
        for attachment in task.document?.attachments ?? [] {
            let data = try Data(contentsOf: resolve(attachment, sessionID: task.id))
            let thumbnail = try thumbnail(attachment, sessionID: task.id)
            snapshot.details?.attachments.append(.init(id: attachment.id, data: data, thumbnail: thumbnail))
        }
        try snapshot.validate()
        return snapshot
    }

    func stageForSync(_ snapshot: RemoteTaskSnapshot, sessionID: UUID) throws {
        try snapshot.validate()
        do {
            for reference in snapshot.details?.document?.attachments ?? [] {
                guard let payload = snapshot.details?.attachments.first(where: { $0.id == reference.id }) else {
                    throw RemoteTaskSnapshot.ContractError.invalidPayload
                }
                let base = staging(sessionID)
                try manager.createDirectory(at: base.appendingPathComponent(reference.id.uuidString), withIntermediateDirectories: true)
                try payload.data.write(to: base.appendingPathComponent(reference.relativePath), options: .atomic)
                if let path = reference.thumbnailPath, let thumbnail = payload.thumbnail {
                    try thumbnail.write(to: base.appendingPathComponent(path), options: .atomic)
                }
            }
        } catch {
            discard(sessionID: sessionID)
            throw error
        }
    }

    func removeTransfer(_ url: URL) {
        let folder = manager.temporaryDirectory.appendingPathComponent("TaskTransfers").standardizedFileURL.path + "/"
        if url.standardizedFileURL.path.hasPrefix(folder) { try? manager.removeItem(at: url.deletingLastPathComponent()) }
    }

    func resolve(_ attachment: TaskAttachment, sessionID: UUID) throws -> URL {
        try resolvePath(attachment.relativePath, sessionID: sessionID)
    }

    func thumbnail(_ attachment: TaskAttachment, sessionID: UUID) throws -> Data? {
        guard let path = attachment.thumbnailPath else { return nil }
        return try Data(contentsOf: resolvePath(path, sessionID: sessionID))
    }

    private func resolvePath(_ path: String, sessionID: UUID) throws -> URL {
        guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw TaskMediaError.unavailable }
        for base in [committed, staging(sessionID)] {
            let file = base.appendingPathComponent(path)
            if manager.fileExists(atPath: file.path) { return file }
        }
        throw TaskMediaError.unavailable
    }

    // Keep staged files until the database save succeeds.
    func prepare(_ attachments: [TaskAttachment], sessionID: UUID) throws -> [UUID] {
        var copied: [UUID] = []
        do {
            try manager.createDirectory(at: committed, withIntermediateDirectories: true)
            for attachment in attachments {
                _ = try resolve(attachment, sessionID: sessionID)
                let destination = committed.appendingPathComponent(attachment.id.uuidString, isDirectory: true)
                if !manager.fileExists(atPath: destination.path) {
                    try manager.copyItem(at: staging(sessionID).appendingPathComponent(attachment.id.uuidString), to: destination)
                    copied.append(attachment.id)
                }
            }
            return copied
        } catch {
            rollback(copied)
            throw error
        }
    }

    func rollback(_ copied: [UUID]) {
        for id in copied { try? manager.removeItem(at: committed.appendingPathComponent(id.uuidString)) }
    }

    func finish(sessionID: UUID, removed: [TaskAttachment], keeping: Set<UUID>) {
        discard(sessionID: sessionID)
        for attachment in removed where !keeping.contains(attachment.id) {
            try? manager.removeItem(at: committed.appendingPathComponent(attachment.id.uuidString))
        }
    }

    func discard(sessionID: UUID) {
        try? manager.removeItem(at: staging(sessionID))
    }

    func recover(referenced: Set<UUID>) throws {
        if manager.fileExists(atPath: committed.path) {
            for file in try manager.contentsOfDirectory(at: committed, includingPropertiesForKeys: nil) {
                if let id = UUID(uuidString: file.lastPathComponent), !referenced.contains(id) {
                    try manager.removeItem(at: file)
                }
            }
        }
        let drafts = root.appendingPathComponent("Drafts", isDirectory: true)
        if manager.fileExists(atPath: drafts.path) { try manager.removeItem(at: drafts) }
        if let transfers = transferCleanupDirectory, manager.fileExists(atPath: transfers.path) {
            try manager.removeItem(at: transfers)
        }
    }

    private var committed: URL { root.appendingPathComponent("Files", isDirectory: true) }
    private func staging(_ id: UUID) -> URL {
        root.appendingPathComponent("Drafts", isDirectory: true).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private static func imageThumbnail(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 640
        ] as CFDictionary)
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw TaskMediaError.invalidFile
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw TaskMediaError.invalidFile }
    }
}
