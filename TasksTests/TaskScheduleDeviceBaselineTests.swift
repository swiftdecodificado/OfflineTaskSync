import Foundation
import SwiftData
import Testing
@testable import Tasks

@Suite @MainActor struct TaskScheduleDeviceBaselineTests {
    @Test(.enabled(if: FileManager.default.fileExists(atPath: URL.temporaryDirectory
        .appendingPathComponent("TaskScheduleMigrationBaseline/Tasks.store").path)))
    func copiedDeviceStoreKeepsEveryTaskFieldAndDeletion() async throws {
        let source = URL.temporaryDirectory.appendingPathComponent("TaskScheduleMigrationBaseline")
        let directory = URL.temporaryDirectory.appendingPathComponent("ScheduleMigration-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tasks.store")
        let baseline: ([TaskSnapshot], [UUID]) = try autoreleasepool {
            let schema = Schema(versionedSchema: TasksSchemaV6.self)
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let tasks = try context.fetch(FetchDescriptor<TasksSchemaV6.StoredTask>()).map { record in
                let document = try record.documentData.map { try JSONDecoder().decode(TaskDocument.self, from: $0) }
                return TaskSnapshot(id: record.id, title: record.title, isDone: record.isDone,
                                    updatedAt: record.updatedAt, pendingSync: record.pendingSync,
                                    notes: record.notes, document: document, dueDate: record.dueDate, dueTime: record.dueTime,
                                    reminderDate: record.reminderDate, calendarEventID: record.calendarEventID,
                                    calendarLinkDate: record.calendarLinkDate, iconName: record.iconName, colorID: record.colorID)
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            let deletions = try context.fetch(FetchDescriptor<TasksSchemaV6.StoredDeletion>()).map(\.id)
            return (tasks, deletions)
        }
        let persistence = try PersistenceContainer(storeURL: url)
        defer { persistence.disconnect() }
        let store = SwiftDataTaskRepository(store: persistence)
        let migrated = try await store.allTasks().sorted { $0.id.uuidString < $1.id.uuidString }
        #expect(migrated == baseline.0)
        #expect(Set(try await store.pendingDeletionIDs()) == Set(baseline.1))
        print("SCHEDULE_MIGRATION_TASKS_VALIDATED: \(migrated.count)")
    }
}
