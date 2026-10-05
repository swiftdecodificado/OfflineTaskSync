import Foundation
import SwiftData
import Testing

@testable import Tasks

private enum InjectedFailure: Error {
    case save
    case fetch
}

@MainActor
private final class FailingOperations {
    var failsSave = false
    var failsFetch = false
    var failsFetchAfterSave = false

    func beforeSave() throws {
        if failsSave { throw InjectedFailure.save }
    }

    func beforeFetch() throws {
        if failsFetch { throw InjectedFailure.fetch }
    }

    func afterSave() {
        if failsFetchAfterSave { failsFetch = true }
    }
}

@Suite
@MainActor
struct PersistenceFailureTests {
    enum WriteOperation: CaseIterable, Sendable {
        case create, toggle, rename, delete, applyRemote, markSynced, confirmDeletion
    }

    @MainActor
    private struct Fixture {
        let persistentStore: PersistenceContainer
        let context: FailingOperations
        let store: SwiftDataTaskRepository
        let coordinator: SyncCoordinator
        let viewModel: TasksViewModel

        init() throws {
            persistentStore = try PersistenceContainer(inMemory: true)
            context = FailingOperations()
            store = SwiftDataTaskRepository(store: persistentStore, beforeSave: context.beforeSave,
                              afterSave: context.afterSave, beforeFetch: context.beforeFetch)
            coordinator = SyncCoordinator(
                store: store,
                syncService: MockSyncService(latency: .zero),
                networkMonitor: NetworkMonitor(startMonitoring: false)
            )
            viewModel = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: coordinator.didWriteLocally)
        }
    }

    @Test(arguments: WriteOperation.allCases)
    func failedSavesRollBackTheWholeOperation(operation: WriteOperation) async throws {
        let fixture = try Fixture()
        let store = fixture.store
        let context = fixture.context
        let id = UUID()
        try await store.createTask(id: id, title: "Original")
        let created = try await store.snapshot(id: id)
        let sentSnapshot = try #require(created)
        if operation != .markSynced {
            try await store.markSynced(sentSnapshot)
        }
        if operation == .confirmDeletion {
            try await store.delete(id: id)
        }
        let before = try await store.allTasks()
        let deletionsBefore = try await store.pendingDeletionIDs()
        context.failsSave = true

        do {
            switch operation {
            case .create:
                try await store.createTask(title: "Must not persist")
            case .toggle:
                try await store.toggleDone(id: id)
            case .rename:
                try await store.rename(id: id, title: "Must not persist")
            case .delete:
                try await store.delete(id: id)
            case .applyRemote:
                try await store.applyRemoteSnapshot(
                    RemoteTaskSnapshot(id: id, title: "Must not persist", isDone: true, updatedAt: Date())
                )
            case .markSynced:
                try await store.markSynced(sentSnapshot)
            case .confirmDeletion:
                try await store.confirmDeletion(id: id)
            }
            Issue.record("Expected a save failure")
        } catch {
            #expect(error as? InjectedFailure == .save)
        }

        let after = try await store.allTasks()
        let deletionsAfter = try await store.pendingDeletionIDs()
        let hasChanges = store.hasChanges
        #expect(after == before)
        #expect(deletionsAfter == deletionsBefore)
        #expect(!hasChanges)

        context.failsSave = false
        try await store.createTask(title: "Next operation")
        let reader = SwiftDataTaskRepository(store: fixture.persistentStore)
        let persisted = try await reader.allTasks()
        let persistedDeletions = try await reader.pendingDeletionIDs()
        #expect(persisted.count == before.count + 1)
        #expect(persisted.filter { $0.title != "Next operation" } == before)
        #expect(persistedDeletions == deletionsBefore)
    }

    @Test
    func failedCreationKeepsTheDraftAndCanBeRetried() async throws {
        let fixture = try Fixture()
        let context = fixture.context
        let viewModel = fixture.viewModel
        await viewModel.refresh()
        viewModel.newTaskTitle = "  Pay the invoice  "
        context.failsSave = true

        let failed = await viewModel.add()
        #expect(!failed)
        #expect(viewModel.newTaskTitle == "  Pay the invoice  ")
        #expect(viewModel.failure == .create)
        #expect(viewModel.tasks.isEmpty)
        #expect(!viewModel.isAdding)

        await viewModel.refresh()
        #expect(viewModel.failure == .create)
        context.failsSave = false
        let saved = await viewModel.add()
        #expect(saved)
        #expect(viewModel.newTaskTitle.isEmpty)
        #expect(viewModel.failure == nil)
        #expect(viewModel.tasks.count == 1)
        #expect(viewModel.tasks.first?.title == "Pay the invoice")
    }

    @Test(arguments: [WriteOperation.rename, .toggle, .delete])
    func failedEditsKeepTheDisplayedAndStoredTask(operation: WriteOperation) async throws {
        let fixture = try Fixture()
        let context = fixture.context
        let viewModel = fixture.viewModel
        let id = UUID()
        try await fixture.store.createTask(id: id, title: "Original")
        await viewModel.refresh()
        let before = viewModel.tasks
        context.failsSave = true

        let saved: Bool
        switch operation {
        case .rename: saved = await viewModel.rename(id: id, title: "Edited")
        case .toggle: saved = await viewModel.toggle(id: id)
        case .delete: saved = await viewModel.delete(id: id)
        default: return
        }

        #expect(!saved)
        #expect(viewModel.tasks == before)
        #expect(viewModel.failure == (operation == .delete ? .delete : .update))
        let persisted = try await fixture.store.allTasks()
        let deletions = try await fixture.store.pendingDeletionIDs()
        #expect(persisted == before)
        #expect(deletions.isEmpty)
    }

    @Test
    func failedRefreshKeepsTheLastLoadedTasksAndSupportsRetry() async throws {
        let fixture = try Fixture()
        let context = fixture.context
        let viewModel = fixture.viewModel
        try await fixture.store.createTask(title: "Original")
        await viewModel.refresh()
        let before = viewModel.tasks
        context.failsFetch = true

        await viewModel.refresh()
        #expect(viewModel.failure == .load)
        #expect(viewModel.hasLoadedTasks)
        #expect(viewModel.tasks == before)

        context.failsFetch = false
        await viewModel.refresh()
        #expect(viewModel.failure == nil)
        #expect(viewModel.tasks == before)
    }

    @Test
    func failedInitialLoadIsNotAnEmptySuccess() async throws {
        let fixture = try Fixture()
        let context = fixture.context
        context.failsFetch = true

        await fixture.viewModel.refresh()
        #expect(!fixture.viewModel.hasLoadedTasks)
        #expect(fixture.viewModel.failure == .load)

        context.failsFetch = false
        await fixture.viewModel.refresh()
        #expect(fixture.viewModel.hasLoadedTasks)
        #expect(fixture.viewModel.failure == nil)
        #expect(fixture.viewModel.tasks.isEmpty)
    }

    @Test
    func successfulSaveWithFailedReloadDoesNotKeepAnAlreadySavedDraft() async throws {
        let fixture = try Fixture()
        let context = fixture.context
        let viewModel = fixture.viewModel
        viewModel.newTaskTitle = "Pay the invoice"
        context.failsFetchAfterSave = true

        let saved = await viewModel.add()
        #expect(saved)
        #expect(viewModel.newTaskTitle.isEmpty)
        #expect(viewModel.failure == .load)

        let reader = SwiftDataTaskRepository(store: fixture.persistentStore)
        let persisted = try await reader.allTasks()
        #expect(persisted.count == 1)
        #expect(persisted.first?.title == "Pay the invoice")
    }

    @Test
    func aQueuedTitleFailureKeepsTheDraftAfterLeavingTheDetail() async throws {
        let fixture = try Fixture()
        let context = fixture.context
        let viewModel = fixture.viewModel
        let id = UUID()
        try await fixture.store.createTask(id: id, title: "Original")
        await viewModel.refresh()
        context.failsSave = true

        viewModel.editTitle(id: id, title: "Unsaved edit")
        viewModel.finishTitleEditing(id: id)
        await viewModel.flushTitleEdits()
        let original = try await fixture.store.snapshot(id: id)
        #expect(original?.title == "Original")
        #expect(viewModel.title(id: id) == "Unsaved edit")
        #expect(viewModel.failure == .update)

        context.failsSave = false
        viewModel.editTitle(id: id, title: "Unsaved edit")
        viewModel.finishTitleEditing(id: id)
        await viewModel.flushTitleEdits()
        let saved = try await fixture.store.snapshot(id: id)
        #expect(saved?.title == "Unsaved edit")
        #expect(viewModel.failure == nil)
        fixture.coordinator.suspend()
    }

    @Test
    func aPendingFetchFailureCannotReportASuccessfulSync() async throws {
        let fixture = try Fixture()
        let context = fixture.context
        context.failsFetch = true

        await fixture.coordinator.sync()
        #expect(fixture.coordinator.status == .failed)
        #expect(fixture.coordinator.lastSynced == nil)

        context.failsFetch = false
        await fixture.coordinator.sync()
        #expect(fixture.coordinator.status == .synced)
        #expect(fixture.coordinator.lastSynced != nil)
    }
}
