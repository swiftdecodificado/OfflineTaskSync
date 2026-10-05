import Foundation
import Testing

@testable import Tasks

@MainActor
private final class MemoryTaskRepository: TaskRepository {
    enum Failure: Error { case write }

    var tasks: [TaskSnapshot] = []
    var deletions: [UUID] = []
    var failsWrite = false
    var nextRead: (() async -> Void)?

    func createTask(id: UUID, title: String) async throws {
        try checkWrite()
        tasks.append(TaskSnapshot(id: id, title: title, isDone: false, updatedAt: Date(), pendingSync: true))
    }

    func createTask(id: UUID, title: String, notes: String, dueDate: Date?, dueTime: Date?, reminderDate: Date?, icon: TaskIcon?, color: TaskColor) async throws {
        try checkWrite()
        guard !tasks.contains(where: { $0.id == id }) else { return }
        tasks.append(TaskSnapshot(id: id, title: title, isDone: false, updatedAt: .now, pendingSync: true,
                                  notes: notes, dueDate: dueDate, dueTime: dueTime, reminderDate: reminderDate, iconName: icon?.rawValue, colorID: color.rawValue))
    }

    func setIcon(id: UUID, icon: TaskIcon?) async throws {
        try checkWrite()
        if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index].iconName = icon?.rawValue }
    }

    func setDueTime(id: UUID, date: Date?) async throws {
        try checkWrite()
        if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index].dueTime = date }
    }

    func toggleDone(id: UUID) async throws {
        try checkWrite()
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        replace(task, isDone: !task.isDone)
    }

    func rename(id: UUID, title: String) async throws {
        try checkWrite()
        guard let task = tasks.first(where: { $0.id == id }) else { return }
        replace(task, title: title)
    }

    func setNotes(id: UUID, notes: String) async throws {
        try checkWrite()
        if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index].notes = notes }
    }

    func setDueDate(id: UUID, date: Date?) async throws {
        try checkWrite()
        if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index].dueDate = date }
    }

    func setReminderDate(id: UUID, date: Date?) async throws {
        try checkWrite()
        if let index = tasks.firstIndex(where: { $0.id == id }) { tasks[index].reminderDate = date }
    }

    func linkCalendar(id: UUID, eventID: String, date: Date) async throws {
        try checkWrite()
        if let index = tasks.firstIndex(where: { $0.id == id }) {
            tasks[index].calendarEventID = eventID
            tasks[index].calendarLinkDate = date
        }
    }

    func delete(id: UUID) async throws {
        try checkWrite()
        tasks.removeAll { $0.id == id }
        deletions.append(id)
    }

    func allTasks() async throws -> [TaskSnapshot] {
        let snapshot = tasks
        let read = nextRead
        nextRead = nil
        await read?()
        return snapshot
    }
    func snapshot(id: UUID) async throws -> TaskSnapshot? { tasks.first { $0.id == id } }
    func pendingRecords() async throws -> [TaskSnapshot] { tasks.filter(\.pendingSync) }
    func pendingDeletionIDs() async throws -> [UUID] { deletions }

    func applyRemoteSnapshot(_ snapshot: RemoteTaskSnapshot) async throws {
        try checkWrite()
        guard !deletions.contains(snapshot.id), !tasks.contains(where: { $0.id == snapshot.id && $0.pendingSync }) else { return }
        tasks.removeAll { $0.id == snapshot.id }
        tasks.append(TaskSnapshot(id: snapshot.id, title: snapshot.title, isDone: snapshot.isDone,
                                  updatedAt: snapshot.updatedAt, pendingSync: false))
    }

    func markSynced(_ sentSnapshot: TaskSnapshot) async throws {
        try checkWrite()
        guard tasks.contains(sentSnapshot) else { return }
        replace(sentSnapshot, pendingSync: false)
    }

    func confirmDeletion(id: UUID) async throws {
        try checkWrite()
        deletions.removeAll { $0 == id }
    }

    private func checkWrite() throws {
        if failsWrite { throw Failure.write }
    }

    private func replace(_ task: TaskSnapshot, title: String? = nil, isDone: Bool? = nil, pendingSync: Bool = true) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index] = TaskSnapshot(id: task.id, title: title ?? task.title, isDone: isDone ?? task.isDone,
                                    updatedAt: task.updatedAt, pendingSync: pendingSync, notes: task.notes, dueDate: task.dueDate,
                                    dueTime: task.dueTime, reminderDate: task.reminderDate, calendarEventID: task.calendarEventID,
                                    calendarLinkDate: task.calendarLinkDate, iconName: task.iconName)
    }
}

@Suite
@MainActor
struct RepositoryBoundaryTests {
    @Test
    func presentationEditsTasksWithoutPersistenceOrSyncServices() async throws {
        let repository = MemoryTaskRepository()
        var writes = 0
        let viewModel = TasksViewModel(store: repository, mediaStore: makeTestMediaStore(), onLocalWrite: { writes += 1 })
        viewModel.newTaskTitle = "  Original  "
        #expect(await viewModel.add())
        let task = try #require(viewModel.tasks.first)
        #expect(task.title == "Original")

        viewModel.editTitle(id: task.id, title: "  Edited  ")
        viewModel.finishTitleEditing(id: task.id)
        await viewModel.flushTitleEdits()
        #expect(viewModel.task(id: task.id)?.title == "Edited")
        #expect(!viewModel.hasUnsavedTitle(id: task.id))
        #expect(await viewModel.toggle(id: task.id))
        #expect(viewModel.task(id: task.id)?.isDone == true)
        #expect(await viewModel.delete(id: task.id))
        #expect(viewModel.tasks.isEmpty)
        #expect(repository.deletions == [task.id])
        #expect(writes == 4)
    }

    @Test
    func failedRepositoryWritesKeepPresentationDraftsWithoutNotifyingSync() async {
        let repository = MemoryTaskRepository()
        repository.failsWrite = true
        var writes = 0
        let viewModel = TasksViewModel(store: repository, mediaStore: makeTestMediaStore(), onLocalWrite: { writes += 1 })
        viewModel.newTaskTitle = "Keep this draft"
        #expect(await viewModel.add() == false)
        #expect(viewModel.failure == .create)
        #expect(viewModel.newTaskTitle == "Keep this draft")
        #expect(writes == 0)

        repository.failsWrite = false
        #expect(await viewModel.add())
        #expect(writes == 1)
        #expect(viewModel.failure == nil)
    }

    @Test
    func coordinatorUsesRepositoryValuesWithoutASwiftDataContainer() async throws {
        let repository = MemoryTaskRepository()
        let localID = UUID()
        let deletedID = UUID()
        try await repository.createTask(id: localID, title: "Local edit")
        try await repository.delete(id: deletedID)
        let remote = RemoteTaskSnapshot(id: UUID(), title: "Remote task", isDone: true, updatedAt: Date())
        let service = MockSyncService(seed: [remote], latency: .zero)
        let coordinator = SyncCoordinator(store: repository, syncService: service,
                                          networkMonitor: NetworkMonitor(startMonitoring: false))
        defer { coordinator.suspend() }
        await coordinator.sync()

        #expect(coordinator.status == .synced)
        #expect(coordinator.pendingCount == 0)
        #expect(repository.tasks.count == 2)
        #expect(repository.tasks.allSatisfy { !$0.pendingSync })
        #expect(repository.deletions.isEmpty)
        #expect(Set(await service.currentRecords().map(\.id)) == Set([localID, remote.id]))
    }
    @Test
    func lateRefreshCannotReplaceNewerResults() async throws {
        let repository = MemoryTaskRepository()
        try await repository.createTask(id: UUID(), title: "First")
        var continuation: CheckedContinuation<Void, Never>?
        repository.nextRead = {
            await withCheckedContinuation { continuation = $0 }
        }
        let model = TasksViewModel(store: repository, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        let oldRead = Task { await model.refresh() }
        while continuation == nil { await Task.yield() }
        try await repository.createTask(id: UUID(), title: "Second")
        await model.refresh()
        continuation?.resume()
        await oldRead.value
        #expect(model.tasks.count == 2)
    }

}
