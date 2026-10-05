import Foundation

@MainActor
protocol TaskRepository: AnyObject {
    func createTask(id: UUID, title: String) async throws
    func createTask(id: UUID, title: String, notes: String, dueDate: Date?, dueTime: Date?, reminderDate: Date?, icon: TaskIcon?, color: TaskColor) async throws
    func saveDraft(_ draft: TaskDraft, creating: Bool) async throws
    func setIcon(id: UUID, icon: TaskIcon?) async throws
    func setDueTime(id: UUID, date: Date?) async throws
    func toggleDone(id: UUID) async throws
    func setNotes(id: UUID, notes: String) async throws
    func setDueDate(id: UUID, date: Date?) async throws
    func setReminderDate(id: UUID, date: Date?) async throws
    func linkCalendar(id: UUID, eventID: String, date: Date) async throws
    func rename(id: UUID, title: String) async throws
    func delete(id: UUID) async throws
    func allTasks() async throws -> [TaskSnapshot]
    func snapshot(id: UUID) async throws -> TaskSnapshot?
    func pendingRecords() async throws -> [TaskSnapshot]
    func pendingDeletionIDs() async throws -> [UUID]
    func applyRemoteSnapshot(_ snapshot: RemoteTaskSnapshot) async throws
    func markSynced(_ sentSnapshot: TaskSnapshot) async throws
    func confirmDeletion(id: UUID) async throws
}

extension TaskRepository {
    func createTask(id: UUID, title: String, notes: String, dueDate: Date?, dueTime: Date?, reminderDate: Date?, icon: TaskIcon?) async throws {
        try await createTask(id: id, title: title, notes: notes, dueDate: dueDate, dueTime: dueTime,
                             reminderDate: reminderDate, icon: icon, color: .defaultColor)
    }

    func saveDraft(_ draft: TaskDraft, creating: Bool) async throws {
        throw CocoaError(.featureUnsupported)
    }

    func createTask(title: String) async throws {
        try await createTask(id: UUID(), title: title)
    }
}
