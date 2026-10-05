import Foundation

protocol SyncService: Sendable {
    func pull() async throws -> [RemoteTaskSnapshot]
    func push(_ changes: [RemoteTaskSnapshot]) async throws
    func pushDeletions(_ ids: [UUID]) async throws
}

extension RemoteTaskSnapshot {
    init(_ task: TaskSnapshot) {
        self.init(id: task.id, title: task.title, isDone: task.isDone, updatedAt: task.updatedAt)
    }
}
