import Foundation
import SwiftData
import Testing

@testable import Tasks

@MainActor
final class DiskStoreFixture {
    private let directory: URL
    private var stores: [PersistenceContainer] = []

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func open() throws -> PersistenceContainer {
        let store = try PersistenceContainer(storeURL: directory.appendingPathComponent("Tasks.sqlite"))
        stores.append(store)
        return store
    }

    func disconnect() throws {
        autoreleasepool {
            for store in stores { store.disconnect() }
        }
        stores.removeAll()
    }

    func close() {
        do {
            try disconnect()
            try FileManager.default.removeItem(at: directory)
        } catch {
            Issue.record(error)
        }
    }
}
