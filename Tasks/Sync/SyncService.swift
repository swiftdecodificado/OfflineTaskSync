import Foundation

protocol SyncService: Sendable {
    func pull() async throws -> [RemoteTaskSnapshot]
    func push(_ changes: [RemoteTaskSnapshot]) async throws
    func pushDeletions(_ ids: [UUID]) async throws
}

extension RemoteTaskSnapshot {
    init(_ task: TaskSnapshot) {
        self.init(id: task.id, title: task.title, isDone: task.isDone, updatedAt: task.updatedAt,
                  version: Self.currentVersion,
                  details: Details(notes: task.notes, document: task.document, dueDate: task.dueDate,
                                   dueTime: task.dueTime, dueEndTime: task.dueEndTime,
                                   reminderDate: task.reminderDate, iconName: task.iconName, colorID: task.colorID))
    }
}
