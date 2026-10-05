import Foundation
import SwiftData
import Testing

@testable import Tasks

@Suite
@MainActor
struct PersistenceRegressionTests {
    enum Operation: CaseIterable, Sendable {
        case create, rename, complete, reopen, delete
    }

    @Test
    func regressionHostUsesAnInMemoryStoreAndStartsOffline() throws {
        try #require(ProcessInfo.processInfo.environment["TASKS_REGRESSION_TEST_HOST"] == "1")
        let environment = AppEnvironment()
        #expect(environment.persistentStore.container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        #expect(!environment.networkMonitor.isOnline)
        #expect(environment.syncCoordinator.status == .offline)
    }

    @Test(arguments: Operation.allCases)
    func savedOperationsSurviveDisconnectingTheSQLiteStore(operation: Operation) async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let store = SwiftDataTaskRepository(store: try disk.open())
        let id = UUID()
        try await store.createTask(id: id, title: "Original 📝")
        if operation != .create {
            let created = try await store.snapshot(id: id)
            try await store.markSynced(try #require(created))
        }
        switch operation {
        case .create: break
        case .rename: try await store.rename(id: id, title: "Edited — ação")
        case .complete: try await store.toggleDone(id: id)
        case .reopen:
            try await store.toggleDone(id: id)
            try await store.toggleDone(id: id)
        case .delete: try await store.delete(id: id)
        }
        let before = try await store.allTasks()
        let deletionsBefore = try await store.pendingDeletionIDs()
        try disk.disconnect()

        let reader = SwiftDataTaskRepository(store: try disk.open())
        let after = try await reader.allTasks()
        let deletionsAfter = try await reader.pendingDeletionIDs()
        #expect(after == before)
        #expect(deletionsAfter == deletionsBefore)
        if operation == .delete {
            #expect(after.isEmpty)
            #expect(deletionsAfter == [id])
        } else {
            let task = try #require(after.first)
            #expect(after.count == 1)
            #expect(task.id == id)
            #expect(task.title == (operation == .rename ? "Edited — ação" : "Original 📝"))
            #expect(task.isDone == (operation == .complete))
            #expect(task.pendingSync)
            #expect(deletionsAfter.isEmpty)
        }
    }

    @Test
    func deletionMarkersKeepTheirTimestampAndBlockRemoteResurrectionAfterReopening() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let persistent = try disk.open()
        let store = SwiftDataTaskRepository(store: persistent)
        let id = UUID()
        try await store.createTask(id: id, title: "Deleted offline")
        try await store.delete(id: id)
        let requestedAt = try autoreleasepool {
            let context = ModelContext(persistent.container)
            return try #require(context.fetch(FetchDescriptor<StoredDeletion>()).first).requestedAt
        }
        try disk.disconnect()

        let reopened = try disk.open()
        let reader = SwiftDataTaskRepository(store: reopened)
        try await reader.applyRemoteSnapshot(
            RemoteTaskSnapshot(id: id, title: "Stale server copy", isDone: false, updatedAt: Date())
        )
        let task = try await reader.snapshot(id: id)
        #expect(task == nil)
        let restoredDate = try autoreleasepool {
            let context = ModelContext(reopened.container)
            return try #require(context.fetch(FetchDescriptor<StoredDeletion>()).first).requestedAt
        }
        #expect(restoredDate == requestedAt)
        try await reader.confirmDeletion(id: id)
        try disk.disconnect()
        let finalReader = SwiftDataTaskRepository(store: try disk.open())
        let pending = try await finalReader.pendingDeletionIDs()
        #expect(pending.isEmpty)
    }

    @Test
    func swiftDataSchemaAndRecordsSurviveReopening() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let persistent = try disk.open()
        #expect(Set(persistent.container.schema.entities.map(\.name)) == ["StoredTask", "StoredDeletion"])
        let store = SwiftDataTaskRepository(store: persistent)
        try await store.createTask(title: "Schema v1")
        let before = try await store.allTasks()
        try disk.disconnect()
        let reopened = SwiftDataTaskRepository(store: try disk.open())
        #expect(try await reopened.allTasks() == before)
    }
}
