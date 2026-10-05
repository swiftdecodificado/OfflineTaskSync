import Foundation
import SwiftData

@MainActor
final class PersistenceContainer {
    private var storage: ModelContainer?
    private var contextOwners: [() -> Void] = []

    var container: ModelContainer {
        guard let storage else { preconditionFailure("Persistent store is disconnected") }
        return storage
    }

    func register(_ owner: SwiftDataTaskRepository) {
        contextOwners.append { [weak owner] in owner?.disconnect() }
    }

    func disconnect() {
        contextOwners.forEach { $0() }
        contextOwners.removeAll()
        storage = nil
    }

    init(inMemory: Bool = false, storeURL: URL? = nil) throws {
        let schema = Schema(versionedSchema: TasksSchemaV7.self)
        let configuration: ModelConfiguration
        if inMemory {
            configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        } else {
            let url: URL
            if let storeURL {
                url = storeURL
            } else {
                let directory = URL.applicationSupportDirectory.appendingPathComponent("SwiftData-v1", isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                url = directory.appendingPathComponent("Tasks.store")
            }
            configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
        }
        storage = try ModelContainer(for: schema, migrationPlan: TasksMigrationPlan.self, configurations: [configuration])
    }
}
