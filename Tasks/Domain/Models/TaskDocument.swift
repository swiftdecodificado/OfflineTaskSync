import Foundation

struct TaskDocument: Codable, Equatable, Sendable {
    static let currentVersion = 1
    var version = currentVersion
    var blocks: [TaskContentBlock] = []

    var attachments: [TaskAttachment] {
        blocks.compactMap {
            if case .attachment(let attachment) = $0 { return attachment }
            return nil
        }
    }

    var plainText: String {
        blocks.map {
            switch $0 {
            case .text(let text): text.plainText
            case .attachment(let attachment): "\n[\(attachment.filename)]\n"
            }
        }.joined()
    }
}

enum TaskContentBlock: Codable, Equatable, Sendable, Identifiable {
    case text(TaskRichText)
    case attachment(TaskAttachment)

    var id: UUID {
        switch self {
        case .text(let text): text.id
        case .attachment(let attachment): attachment.id
        }
    }
}

struct TaskRichText: Codable, Equatable, Sendable {
    var id: UUID
    var rtf: Data
    var plainText: String
}

struct TaskAttachment: Codable, Equatable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable { case image, video, file }

    let id: UUID
    let kind: Kind
    let relativePath: String
    let thumbnailPath: String?
    let filename: String
    let contentType: String
    let byteCount: Int64
    let duration: Double?
}
