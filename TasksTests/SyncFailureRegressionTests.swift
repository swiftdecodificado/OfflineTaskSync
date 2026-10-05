import Foundation
import Testing

@testable import Tasks

private actor FailingSyncService: SyncService {
    enum Stage: CaseIterable, Sendable {
        case pull, deletion, push
    }

    private var failure: Stage?
    private let remote: MockSyncService
    private(set) var calls = 0

    init(failure: Stage, seed: [RemoteTaskSnapshot]) {
        self.failure = failure
        remote = MockSyncService(seed: seed, latency: .zero)
    }

    private func attempt(_ stage: Stage) throws {
        calls += 1
        if failure == stage {
            failure = nil
            throw URLError(.timedOut)
        }
    }

    func pull() async throws -> [RemoteTaskSnapshot] {
        try attempt(.pull)
        return try await remote.pull()
    }

    func pushDeletions(_ ids: [UUID]) async throws {
        try attempt(.deletion)
        try await remote.pushDeletions(ids)
    }

    func push(_ changes: [RemoteTaskSnapshot]) async throws {
        try attempt(.push)
        try await remote.push(changes)
    }

    func records() async -> [RemoteTaskSnapshot] {
        await remote.currentRecords()
    }
}

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct SyncFailureRegressionTests {
    @Test(arguments: FailingSyncService.Stage.allCases)
    fileprivate func failedSyncPreservesUnacknowledgedOperationsAcrossSQLiteReopening(
        stage: FailingSyncService.Stage
    ) async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let store = SwiftDataTaskRepository(store: try disk.open())
        let keptID = UUID()
        let deletedID = UUID()
        try await store.createTask(id: keptID, title: "Created offline")
        try await store.rename(id: keptID, title: "Edited offline")
        try await store.toggleDone(id: keptID)
        try await store.createTask(id: deletedID, title: "Deleted offline")
        try await store.delete(id: deletedID)
        let expected = try await store.snapshot(id: keptID)
        let monitor = NetworkMonitor(startMonitoring: false)
        monitor.setOnline(false)
        let service = FailingSyncService(failure: stage, seed: [
            RemoteTaskSnapshot(id: deletedID, title: "Old remote task", isDone: false, updatedAt: Date())
        ])
        let coordinator = SyncCoordinator(store: store, syncService: service, networkMonitor: monitor, retryDelays: [])
        defer { coordinator.suspend() }
        await coordinator.sync()
        #expect(coordinator.status == .offline)
        #expect(await service.calls == 0)

        monitor.setOnline(true)
        await coordinator.sync()
        #expect(coordinator.status == .failed)
        #expect(coordinator.lastSynced == nil)
        #expect(coordinator.pendingCount == (stage == .push ? 1 : 2))
        coordinator.suspend()
        try disk.disconnect()

        let reader = SwiftDataTaskRepository(store: try disk.open())
        let restored = try await reader.snapshot(id: keptID)
        let deletions = try await reader.pendingDeletionIDs()
        #expect(restored == expected)
        #expect(deletions == (stage == .push ? [] : [deletedID]))
        let deleted = try await reader.snapshot(id: deletedID)
        #expect(deleted == nil)

        let recovered = SyncCoordinator(
            store: reader, syncService: service,
            networkMonitor: NetworkMonitor(startMonitoring: false), retryDelays: []
        )
        defer { recovered.suspend() }
        await recovered.sync()
        #expect(recovered.status == .synced)
        #expect(recovered.pendingCount == 0)
        let saved = try await reader.snapshot(id: keptID)
        #expect(saved?.pendingSync == false)
        #expect(saved?.title == expected?.title)
        #expect(saved?.isDone == true)
        #expect(saved?.updatedAt == expected?.updatedAt)
        let finalDeletions = try await reader.pendingDeletionIDs()
        #expect(finalDeletions.isEmpty)
        let remote = await service.records()
        #expect(remote.count == 1)
        #expect(remote.first?.id == keptID)
        #expect(remote.first?.title == expected?.title)
        #expect(remote.first?.isDone == true)
    }
}
