import Foundation

struct RemoteTaskSnapshot: Sendable, Equatable, Codable {
    static let currentVersion = 2

    let id: UUID
    let title: String
    let isDone: Bool
    let updatedAt: Date
    var version: Int = 1
    var details: Details?

    struct Details: Sendable, Equatable, Codable {
        var notes: String
        var document: TaskDocument?
        var dueDate: Date?
        var dueTime: Date?
        var dueEndTime: Date?
        var reminderDate: Date?
        var iconName: String?
        var colorID: String?
        var attachments: [Attachment] = []
    }

    struct Attachment: Sendable, Equatable, Codable {
        let id: UUID
        let data: Data
        let thumbnail: Data?
    }

    enum ContractError: Error {
        case unsupportedVersion, invalidPayload
    }

    func validate() throws {
        guard (1...Self.currentVersion).contains(version) else { throw ContractError.unsupportedVersion }
        guard version == 2 else {
            guard details == nil else { throw ContractError.invalidPayload }
            return
        }
        guard let details else { throw ContractError.invalidPayload }
        if let document = details.document, document.version != TaskDocument.currentVersion {
            throw ContractError.unsupportedVersion
        }
        let references = details.document?.attachments ?? []
        guard Set(references.map(\.id)).count == references.count,
              Set(details.attachments.map(\.id)).count == details.attachments.count,
              Set(references.map(\.id)) == Set(details.attachments.map(\.id)) else {
            throw ContractError.invalidPayload
        }
        for reference in references {
            guard let file = details.attachments.first(where: { $0.id == reference.id }),
                  Int64(file.data.count) == reference.byteCount,
                  (reference.thumbnailPath == nil) == (file.thumbnail == nil) else {
                throw ContractError.invalidPayload
            }
            for path in [reference.relativePath, reference.thumbnailPath].compactMap({ $0 }) {
                let parts = path.split(separator: "/", omittingEmptySubsequences: false)
                guard parts.count == 2, parts[0] == Substring(reference.id.uuidString),
                      !["", ".", ".."].contains(String(parts[1])) else { throw ContractError.invalidPayload }
            }
            guard reference.relativePath != reference.thumbnailPath else { throw ContractError.invalidPayload }
        }
    }

    private enum CodingKeys: String, CodingKey { case id, title, isDone, updatedAt, version, details }

    init(id: UUID, title: String, isDone: Bool, updatedAt: Date, version: Int = 1, details: Details? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.updatedAt = updatedAt
        self.version = version
        self.details = details
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        isDone = try values.decode(Bool.self, forKey: .isDone)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        details = try values.decodeIfPresent(Details.self, forKey: .details)
        try validate()
    }
}
