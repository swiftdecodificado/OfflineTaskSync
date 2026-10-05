import Foundation

actor MockSyncService: SyncService {
    enum Call: Equatable {
        case pull
        case push([UUID])
        case pushDeletions([UUID])
    }

    private(set) var callLog: [Call] = []
    private var records: [UUID: RemoteTaskSnapshot]
    private let latency: Duration

    private var beforeReturningFromPull: (@Sendable () async -> Void)?
    private var beforeReturningFromPush: (@Sendable () async -> Void)?

    init(seed: [RemoteTaskSnapshot] = [], latency: Duration = .milliseconds(900)) {
        records = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
        self.latency = latency
    }

    func setBeforeReturningFromPull(_ hook: (@Sendable () async -> Void)?) {
        beforeReturningFromPull = hook
    }

    func setBeforeReturningFromPush(_ hook: (@Sendable () async -> Void)?) {
        beforeReturningFromPush = hook
    }

    func pull() async throws -> [RemoteTaskSnapshot] {
        callLog.append(.pull)
        if latency > .zero { try await Task.sleep(for: latency) }
        await beforeReturningFromPull?()
        return Array(records.values)
    }

    func push(_ changes: [RemoteTaskSnapshot]) async throws {
        callLog.append(.push(changes.map(\.id)))
        if latency > .zero { try await Task.sleep(for: latency) }
        for change in changes {
            records[change.id] = change
        }
        await beforeReturningFromPush?()
    }

    func pushDeletions(_ ids: [UUID]) async throws {
        callLog.append(.pushDeletions(ids))
        if latency > .zero { try await Task.sleep(for: latency) }
        for id in ids {
            records.removeValue(forKey: id)
        }
    }

    func seed(_ snapshot: RemoteTaskSnapshot) {
        records[snapshot.id] = snapshot
    }

    func currentRecords() -> [RemoteTaskSnapshot] {
        Array(records.values)
    }
}
