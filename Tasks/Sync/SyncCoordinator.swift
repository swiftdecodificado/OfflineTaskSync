import Foundation
import Observation
import OSLog

#if DEBUG
private let logger = Logger(subsystem: "com.offlinetasksync.tasks", category: "SyncCoordinator")
#endif

@MainActor
@Observable
final class SyncCoordinator {
    enum Status: Equatable {
        case offline
        case syncing
        case waiting(Int)
        case synced
        case failed
    }

    private(set) var status: Status
    private(set) var lastSynced: Date?
    private(set) var pendingCount: Int = 0

    var onSyncCompleted: (() -> Void)?

    private let store: any TaskRepository
    private let syncService: SyncService
    private let networkMonitor: NetworkMonitor
    private let retryDelays: [Duration]
    private var scheduledTask: Task<Void, Never>?
    private var syncTask: Task<Void, Never>?
    private var pendingRefreshTask: Task<Void, Never>?
    private var needsAnotherSync = false
    private var isActive = true
    private var retryAttempt = 0

    init(
        store: any TaskRepository,
        syncService: SyncService,
        networkMonitor: NetworkMonitor,
        retryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(15)]
    ) {
        self.store = store
        self.syncService = syncService
        self.networkMonitor = networkMonitor
        self.retryDelays = retryDelays
        status = networkMonitor.isOnline ? .waiting(0) : .offline

        networkMonitor.onChange = { [weak self] in
            self?.handleNetworkChange()
        }
        requestPendingRefresh()
    }

    func didWriteLocally() {
        requestPendingRefresh()
        retryAttempt = 0
        guard networkMonitor.isOnline else {
            status = .offline
            return
        }
        schedule(after: .seconds(1))
    }

    func syncNow() {
        retryAttempt = 0
        startSync()
    }

    func resume() {
        isActive = true
        retryAttempt = 0
        if syncTask?.isCancelled == true {
            needsAnotherSync = true
        } else {
            startSync()
        }
    }

    func suspend() {
        isActive = false
        cancelScheduledSync()
        pendingRefreshTask?.cancel()
        needsAnotherSync = false
        syncTask?.cancel()
        status = networkMonitor.isOnline ? .waiting(pendingCount) : .offline
    }

    private func handleNetworkChange() {
        if networkMonitor.isOnline {
            retryAttempt = 0
            schedule(after: .milliseconds(500))
        } else {
            cancelScheduledSync()
            needsAnotherSync = false
            syncTask?.cancel()
            status = .offline
        }
    }

    private func schedule(after delay: Duration) {
        guard isActive, networkMonitor.isOnline else { return }
        if syncTask != nil {
            needsAnotherSync = true
            return
        }
        cancelScheduledSync()
        scheduledTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
            } catch { return }
            guard let self else { return }
            self.scheduledTask = nil
            self.startSync()
        }
    }

    func sync() async {
        if let task = startSync() {
            await task.value
        }
    }

    @discardableResult
    private func startSync() -> Task<Void, Never>? {
        cancelScheduledSync()
        if let syncTask { return syncTask }
        guard isActive, networkMonitor.isOnline else {
            if !networkMonitor.isOnline { status = .offline }
            return nil
        }
        pendingRefreshTask?.cancel()
        status = .syncing
        let task = Task { await runSyncLoop() }
        syncTask = task
        return task
    }

    private func runSyncLoop() async {
        var nextDelay: Duration?
        defer {
            syncTask = nil
            onSyncCompleted?()
            if let nextDelay { schedule(after: nextDelay) }
        }

        repeat {
            do {
                try checkCanSync()
                needsAnotherSync = false
                status = .syncing
                try await syncOnce()
                retryAttempt = 0
                if !needsAnotherSync, pendingCount > 0 {
                    nextDelay = .seconds(1)
                }
            } catch is CancellationError {
                status = networkMonitor.isOnline ? .waiting(pendingCount) : .offline
                if needsAnotherSync, isActive, networkMonitor.isOnline {
                    nextDelay = .zero
                }
                return
            } catch {
                do {
                    try await refreshPendingCount()
                } catch {
                    logFailure(error)
                }
                if Task.isCancelled || !isActive || !networkMonitor.isOnline {
                    status = networkMonitor.isOnline ? .waiting(pendingCount) : .offline
                    if needsAnotherSync, isActive, networkMonitor.isOnline { nextDelay = .zero }
                } else {
                    status = .failed
                    if isTransient(error), retryAttempt < retryDelays.count {
                        nextDelay = retryDelays[retryAttempt]
                        retryAttempt += 1
                    }
                }
                logFailure(error)
                return
            }
        } while needsAnotherSync
    }

    private func syncOnce() async throws {
        let remoteSnapshots = try await syncService.pull()
        for remoteSnapshot in remoteSnapshots {
            try checkCanSync()
            try await store.applyRemoteSnapshot(remoteSnapshot)
        }

        try checkCanSync()
        let deletionIDs = try await store.pendingDeletionIDs()
        try checkCanSync()
        if !deletionIDs.isEmpty {
            try await syncService.pushDeletions(deletionIDs)
            for id in deletionIDs {
                try checkCanSync()
                try await store.confirmDeletion(id: id)
            }
        }

        try checkCanSync()
        let pending = try await store.pendingRecords()
        try checkCanSync()
        if !pending.isEmpty {
            try await syncService.push(pending.map(RemoteTaskSnapshot.init))
            for item in pending {
                try checkCanSync()
                try await store.markSynced(item)
            }
        }

        try await refreshPendingCount()
        try checkCanSync()
        lastSynced = Date()
        status = pendingCount > 0 ? .waiting(pendingCount) : .synced
    }

    private func checkCanSync() throws {
        try Task.checkCancellation()
        guard isActive, networkMonitor.isOnline else { throw CancellationError() }
    }

    private func cancelScheduledSync() {
        scheduledTask?.cancel()
        scheduledTask = nil
    }

    private func requestPendingRefresh() {
        pendingRefreshTask?.cancel()
        pendingRefreshTask = Task { [weak self] in
            await self?.updatePendingState()
        }
    }

    private func updatePendingState() async {
        do {
            try await refreshPendingCount()
            guard !Task.isCancelled, syncTask == nil else { return }
            if !networkMonitor.isOnline {
                status = .offline
            } else {
                status = pendingCount > 0 ? .waiting(pendingCount) : .synced
            }
        } catch {
            guard !Task.isCancelled, syncTask == nil else { return }
            status = networkMonitor.isOnline ? .failed : .offline
            logFailure(error)
        }
    }

    private func isTransient(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet,
             .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private func logFailure(_ error: Error) {
        #if DEBUG
        logger.error("Sync failed: \(String(describing: error), privacy: .private)")
        #endif
    }

    private func refreshPendingCount() async throws {
        try Task.checkCancellation()
        let pendingRecords = try await store.pendingRecords().count
        try Task.checkCancellation()
        let pendingDeletions = try await store.pendingDeletionIDs().count
        try Task.checkCancellation()
        pendingCount = pendingRecords + pendingDeletions
    }
}
