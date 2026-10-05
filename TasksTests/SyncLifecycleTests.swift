import Foundation
import Testing

@testable import Tasks

private actor SyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}

private actor ControlledSyncService: SyncService {
    let pullEntered = SyncGate()
    let pushEntered = SyncGate()
    private let pullGate: SyncGate?
    private let pushGate: SyncGate?
    private let mock = MockSyncService(latency: .zero)
    private var errors: [URLError.Code]
    private(set) var pullCount = 0
    private(set) var pushCount = 0
    private(set) var maxConcurrentCalls = 0
    private(set) var cancelledPushReturns = 0
    private var activeCalls = 0

    init(pullGate: SyncGate? = nil, pushGate: SyncGate? = nil, errors: [URLError.Code] = []) {
        self.pullGate = pullGate
        self.pushGate = pushGate
        self.errors = errors
    }

    func pull() async throws -> [RemoteTaskSnapshot] {
        enter()
        defer { activeCalls -= 1 }
        pullCount += 1
        await pullEntered.open()
        await pullGate?.wait()
        if !errors.isEmpty { throw URLError(errors.removeFirst()) }
        return try await mock.pull()
    }

    func push(_ changes: [RemoteTaskSnapshot]) async throws {
        enter()
        defer { activeCalls -= 1 }
        pushCount += 1
        try await mock.push(changes)
        await pushEntered.open()
        await pushGate?.wait()
        if Task.isCancelled { cancelledPushReturns += 1 }
    }

    func pushDeletions(_ ids: [UUID]) async throws {
        enter()
        defer { activeCalls -= 1 }
        try await mock.pushDeletions(ids)
    }

    func records() async -> [RemoteTaskSnapshot] {
        await mock.currentRecords()
    }

    private func enter() {
        activeCalls += 1
        maxConcurrentCalls = max(maxConcurrentCalls, activeCalls)
    }
}

@Suite(.timeLimit(.minutes(1)))
@MainActor
struct SyncLifecycleTests {
    @Test
    func concurrentRequestsJoinTheRunningCycle() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        try await store.createTask(title: "Original")
        let gate = SyncGate()
        let service = ControlledSyncService(pullGate: gate)
        let coordinator = SyncCoordinator(store: store, syncService: service, networkMonitor: NetworkMonitor(startMonitoring: false))
        let first = Task { await coordinator.sync() }
        await service.pullEntered.wait()

        for _ in 0..<10 { coordinator.syncNow() }
        let joining = Task {
            let release = Task { await gate.open() }
            await coordinator.sync()
            await release.value
        }
        await first.value
        await joining.value

        #expect(await service.pullCount == 1)
        #expect(await service.pushCount == 1)
        #expect(await service.maxConcurrentCalls == 1)
        #expect(coordinator.status == .synced)
        coordinator.suspend()
    }

    @Test
    func localWritesDuringPushTriggerOneFollowingCycleWithoutCancellation() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Original")
        let gate = SyncGate()
        let service = ControlledSyncService(pushGate: gate)
        let coordinator = SyncCoordinator(store: store, syncService: service, networkMonitor: NetworkMonitor(startMonitoring: false))
        let first = Task { await coordinator.sync() }
        await service.pushEntered.wait()

        for title in ["First edit", "Second edit", "Final edit"] {
            try await store.rename(id: id, title: title)
            coordinator.didWriteLocally()
        }
        await gate.open()
        await first.value

        let snapshot = try await store.snapshot(id: id)
        let remote = await service.records()
        #expect(snapshot?.title == "Final edit")
        #expect(snapshot?.pendingSync == false)
        #expect(remote.first?.title == "Final edit")
        #expect(await service.pullCount == 2)
        #expect(await service.pushCount == 2)
        #expect(await service.maxConcurrentCalls == 1)
        #expect(await service.cancelledPushReturns == 0)
        coordinator.suspend()
    }

    @Test
    func resumingBeforeACancelledRequestReturnsWaitsForItsCompletion() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Original")
        let gate = SyncGate()
        let completed = SyncGate()
        let service = ControlledSyncService(pushGate: gate)
        let coordinator = SyncCoordinator(store: store, syncService: service, networkMonitor: NetworkMonitor(startMonitoring: false))
        var completions = 0
        var cancelledStatus: SyncCoordinator.Status?
        coordinator.onSyncCompleted = {
            completions += 1
            if completions == 1 { cancelledStatus = coordinator.status }
            if completions == 2 { Task { await completed.open() } }
        }
        let first = Task { await coordinator.sync() }
        await service.pushEntered.wait()
        coordinator.suspend()
        coordinator.resume()
        await gate.open()
        await first.value
        await completed.wait()

        #expect(cancelledStatus != .failed)
        #expect(coordinator.status == .synced)
        #expect(await service.pullCount == 2)
        #expect(await service.maxConcurrentCalls == 1)
        let snapshot = try await store.snapshot(id: id)
        #expect(snapshot?.pendingSync == false)
        coordinator.onSyncCompleted = nil
        coordinator.suspend()
    }

    @Test
    func immediateSuspendAndResumeDoesNotLoseTheActivationRequest() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        try await store.createTask(title: "Pending")
        let service = ControlledSyncService()
        let completed = SyncGate()
        let coordinator = SyncCoordinator(store: store, syncService: service, networkMonitor: NetworkMonitor(startMonitoring: false))
        var completions = 0
        coordinator.onSyncCompleted = {
            completions += 1
            if completions == 2 { Task { await completed.open() } }
        }

        coordinator.syncNow()
        coordinator.suspend()
        coordinator.resume()
        await completed.wait()

        #expect(coordinator.status == .synced)
        #expect(await service.pullCount == 1)
        #expect(await service.pushCount == 1)
        coordinator.suspend()
    }

    @Test
    func cancellingAWaitingCallerDoesNotCancelTheSharedCycle() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        try await store.createTask(title: "Original")
        let gate = SyncGate()
        let service = ControlledSyncService(pullGate: gate)
        let coordinator = SyncCoordinator(store: store, syncService: service, networkMonitor: NetworkMonitor(startMonitoring: false))
        let caller = Task { await coordinator.sync() }
        await service.pullEntered.wait()
        caller.cancel()
        coordinator.syncNow()
        await gate.open()
        await caller.value

        #expect(coordinator.status == .synced)
        #expect(await service.pullCount == 1)
        #expect(await service.maxConcurrentCalls == 1)
        coordinator.suspend()
    }

    @Test
    func returningOnlineRecoversPendingChangesWithoutAManualRequest() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        try await store.createTask(title: "Offline edit")
        let monitor = NetworkMonitor(startMonitoring: false)
        monitor.setOnline(false)
        let service = ControlledSyncService()
        let completed = SyncGate()
        let coordinator = SyncCoordinator(store: store, syncService: service, networkMonitor: monitor)
        coordinator.onSyncCompleted = { Task { await completed.open() } }
        coordinator.resume()
        monitor.setOnline(true)
        await completed.wait()

        #expect(coordinator.status == .synced)
        #expect(coordinator.pendingCount == 0)
        #expect(await service.pushCount == 1)
        coordinator.suspend()
    }

    @Test
    func connectivityWhileSuspendedDoesNotStartSyncUntilResume() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        try await store.createTask(title: "Offline edit")
        let monitor = NetworkMonitor(startMonitoring: false)
        monitor.setOnline(false)
        let service = ControlledSyncService()
        let coordinator = SyncCoordinator(store: store, syncService: service, networkMonitor: monitor)
        coordinator.suspend()
        monitor.setOnline(true)
        await coordinator.sync()
        #expect(await service.pullCount == 0)

        let completed = SyncGate()
        coordinator.onSyncCompleted = { Task { await completed.open() } }
        coordinator.resume()
        await completed.wait()
        #expect(coordinator.status == .synced)
        #expect(await service.pushCount == 1)
        coordinator.suspend()
    }

    @Test
    func transientFailuresRetryAutomaticallyWithAFiniteBudget() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        try await store.createTask(title: "Pending")
        let service = ControlledSyncService(errors: [.timedOut, .networkConnectionLost])
        let completed = SyncGate()
        let coordinator = SyncCoordinator(
            store: store, syncService: service, networkMonitor: NetworkMonitor(startMonitoring: false),
            retryDelays: [.zero, .zero]
        )
        var completions = 0
        coordinator.onSyncCompleted = {
            completions += 1
            if completions == 3 { Task { await completed.open() } }
        }
        coordinator.resume()
        await completed.wait()

        #expect(coordinator.status == .synced)
        #expect(await service.pullCount == 3)
        #expect(await service.maxConcurrentCalls == 1)
        coordinator.suspend()
    }

    @Test(arguments: [URLError.Code.badURL, .timedOut])
    func permanentFailuresOrExhaustedRetriesStopAutomaticAttempts(errorCode: URLError.Code) async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        try await store.createTask(title: "Pending")
        let service = ControlledSyncService(errors: Array(repeating: errorCode, count: 10))
        let completed = SyncGate()
        let expectedAttempts = errorCode == .timedOut ? 3 : 1
        let coordinator = SyncCoordinator(
            store: store, syncService: service, networkMonitor: NetworkMonitor(startMonitoring: false),
            retryDelays: [.zero, .zero]
        )
        var completions = 0
        coordinator.onSyncCompleted = {
            completions += 1
            if completions == expectedAttempts { Task { await completed.open() } }
        }
        coordinator.resume()
        await completed.wait()
        try await Task.sleep(for: .milliseconds(50))

        #expect(coordinator.status == .failed)
        #expect(coordinator.pendingCount == 1)
        #expect(await service.pullCount == expectedAttempts)
        coordinator.suspend()
    }

    @Test
    func reopeningTheDatabaseRecoversWritesAndDeletionsOnActivation() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let original = try disk.open()
        let writer = SwiftDataTaskRepository(store: original)
        let editedID = UUID()
        let deletedID = UUID()
        try await writer.createTask(id: editedID, title: "Saved before reopening")
        try await writer.createTask(id: deletedID, title: "Deleted before reopening")
        try await writer.delete(id: deletedID)

        let reopened = try disk.open()
        let store = SwiftDataTaskRepository(store: reopened)
        let service = ControlledSyncService()
        let completed = SyncGate()
        let coordinator = SyncCoordinator(store: store, syncService: service, networkMonitor: NetworkMonitor(startMonitoring: false))
        coordinator.onSyncCompleted = { Task { await completed.open() } }
        coordinator.resume()
        await completed.wait()

        let snapshot = try await store.snapshot(id: editedID)
        let deletions = try await store.pendingDeletionIDs()
        let remote = await service.records()
        #expect(snapshot?.pendingSync == false)
        #expect(deletions.isEmpty)
        #expect(remote.map(\.id) == [editedID])
        #expect(coordinator.status == .synced)
        coordinator.suspend()
    }
}
