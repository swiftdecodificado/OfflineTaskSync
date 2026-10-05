import Foundation
import Testing

@testable import Tasks

@Suite
@MainActor
struct SyncCoordinatorTests {
    @Test(arguments: [false, true])
    func anEditDuringPushStaysPendingUntilTheNextSync(toggleDone: Bool) async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Pay the invoice")

        let mock = MockSyncService(latency: .zero)
        let networkMonitor = NetworkMonitor(startMonitoring: false)
        let coordinator = SyncCoordinator(store: store, syncService: mock, networkMonitor: networkMonitor)

        await mock.setBeforeReturningFromPush {
            if toggleDone {
                try? await store.toggleDone(id: id)
            } else {
                try? await store.rename(id: id, title: "Pay the revised invoice")
            }
        }

        await coordinator.sync()

        let expectedTitle = toggleDone ? "Pay the invoice" : "Pay the revised invoice"
        let edited = try await store.snapshot(id: id)
        #expect(edited?.title == expectedTitle)
        #expect(edited?.isDone == toggleDone)
        #expect(edited?.pendingSync == true)
        #expect(coordinator.pendingCount == 1)
        #expect(coordinator.status == .waiting(1))

        let firstRemoteRecords = await mock.currentRecords()
        #expect(firstRemoteRecords.first { $0.id == id }?.title == "Pay the invoice")
        #expect(firstRemoteRecords.first { $0.id == id }?.isDone == false)

        await mock.setBeforeReturningFromPush(nil)
        await coordinator.sync()

        let synced = try await store.snapshot(id: id)
        #expect(synced?.title == expectedTitle)
        #expect(synced?.isDone == toggleDone)
        #expect(synced?.pendingSync == false)
        #expect(coordinator.pendingCount == 0)
        #expect(coordinator.status == .synced)

        let finalRemoteRecords = await mock.currentRecords()
        #expect(finalRemoteRecords.first { $0.id == id }?.title == expectedTitle)
        #expect(finalRemoteRecords.first { $0.id == id }?.isDone == toggleDone)
        let callLog = await mock.callLog
        #expect(callLog == [.pull, .push([id]), .pull, .push([id])])
    }

    @Test
    func aDeletionDuringPushIsPreservedUntilTheNextSync() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Pay the invoice")

        let mock = MockSyncService(latency: .zero)
        let networkMonitor = NetworkMonitor(startMonitoring: false)
        let coordinator = SyncCoordinator(store: store, syncService: mock, networkMonitor: networkMonitor)
        await mock.setBeforeReturningFromPush {
            try? await store.delete(id: id)
        }

        await coordinator.sync()

        let deleted = try await store.snapshot(id: id)
        let pendingDeletions = try await store.pendingDeletionIDs()
        #expect(deleted == nil)
        #expect(pendingDeletions == [id])
        #expect(coordinator.status == .waiting(1))

        await mock.setBeforeReturningFromPush(nil)
        await coordinator.sync()

        let finalSnapshot = try await store.snapshot(id: id)
        let finalDeletions = try await store.pendingDeletionIDs()
        let remoteRecords = await mock.currentRecords()
        #expect(finalSnapshot == nil)
        #expect(finalDeletions.isEmpty)
        #expect(remoteRecords.isEmpty)
        #expect(coordinator.status == .synced)
    }

    @Test
    func syncCoordinatorPullsBeforePushing() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Pay the invoice")
        try await store.toggleDone(id: id)

        let mock = MockSyncService(
            seed: [RemoteTaskSnapshot(id: id, title: "Pay the invoice", isDone: false, updatedAt: Date())],
            latency: .zero
        )
        let networkMonitor = NetworkMonitor(startMonitoring: false)
        let coordinator = SyncCoordinator(store: store, syncService: mock, networkMonitor: networkMonitor)

        await coordinator.sync()

        let callLog = await mock.callLog
        #expect(callLog.first == .pull)
        #expect(callLog.contains { if case .push = $0 { true } else { false } })

        let snapshot = try await store.snapshot(id: id)
        #expect(snapshot?.isDone == true)
        #expect(snapshot?.pendingSync == false)

        let serverRecords = await mock.currentRecords()
        #expect(serverRecords.first { $0.id == id }?.isDone == true)
    }

    @Test
    func goingOfflineMidSyncKeepsPendingFlag() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Pay the invoice")
        try await store.toggleDone(id: id)

        let mock = MockSyncService(latency: .zero)
        let networkMonitor = NetworkMonitor(startMonitoring: false)

        await mock.setBeforeReturningFromPull { @Sendable in
            await networkMonitor.setOnline(false)
        }

        let coordinator = SyncCoordinator(store: store, syncService: mock, networkMonitor: networkMonitor)

        await coordinator.sync()

        #expect(coordinator.status == .offline)

        let callLog = await mock.callLog
        #expect(callLog == [.pull])

        let snapshot = try await store.snapshot(id: id)
        #expect(snapshot?.pendingSync == true)
    }
}
