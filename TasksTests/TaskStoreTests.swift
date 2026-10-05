import Foundation
import Testing

@testable import Tasks

@Suite
@MainActor
struct TaskStoreTests {
    @Test
    func aStaleRemoteSnapshotDoesNotUndoAPendingLocalWrite() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        let createdAt = Date()
        try await store.createTask(id: id, title: "Pay the invoice")

        try await store.toggleDone(id: id)

        try await store.applyRemoteSnapshot(
            RemoteTaskSnapshot(id: id, title: "Pay the invoice", isDone: false, updatedAt: createdAt)
        )

        let snapshot = try await store.snapshot(id: id)
        #expect(snapshot?.isDone == true)
        #expect(snapshot?.pendingSync == true)
    }

    @Test
    func aSnapshotAppliesAfterMarkSynced() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Pay the invoice")
        try await store.toggleDone(id: id)

        let snapshotToSend = try await store.snapshot(id: id)
        let sentSnapshot = try #require(snapshotToSend)
        try await store.markSynced(sentSnapshot)

        let updatedAt = Date()
        try await store.applyRemoteSnapshot(
            RemoteTaskSnapshot(id: id, title: "Pay the invoice (shared)", isDone: true, updatedAt: updatedAt)
        )

        let snapshot = try await store.snapshot(id: id)
        #expect(snapshot?.title == "Pay the invoice (shared)")
        #expect(snapshot?.pendingSync == false)
    }

    @Test
    func aSnapshotForAnUnknownTaskIsInserted() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        let updatedAt = Date()

        try await store.applyRemoteSnapshot(
            RemoteTaskSnapshot(id: id, title: "Created on another device", isDone: false, updatedAt: updatedAt)
        )

        let snapshot = try await store.snapshot(id: id)
        #expect(snapshot?.title == "Created on another device")
        #expect(snapshot?.pendingSync == false)
    }
    @Test
    func olderRemoteSnapshotCannotUndoAnAcknowledgedRecentEdit() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        let oldDate = Date.now.addingTimeInterval(-3600)
        try await store.createTask(id: id, title: "Latest")
        let sent = try #require(try await store.snapshot(id: id))
        try await store.markSynced(sent)
        try await store.applyRemoteSnapshot(RemoteTaskSnapshot(id: id, title: "Old", isDone: true, updatedAt: oldDate))
        #expect(try await store.snapshot(id: id)?.title == "Latest")
        #expect(try await store.snapshot(id: id)?.isDone == false)
    }

}
