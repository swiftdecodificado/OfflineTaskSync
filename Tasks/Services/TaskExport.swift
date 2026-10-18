import CoreTransferable
import Foundation
import UniformTypeIdentifiers

struct TaskArchive: Codable, Sendable {
    let formatVersion: Int
    let exportedAt: Date
    let tasks: [TaskSnapshot]
}

struct TaskExport: Transferable, Identifiable, Sendable {
    let id = UUID()
    let data: Data

    init(tasks: [TaskSnapshot], exportedAt: Date = .now) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        data = try encoder.encode(TaskArchive(formatVersion: 3, exportedAt: exportedAt, tasks: tasks))
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("Tilo-tasks.json")
    }
}
