import Foundation
import Testing

@testable import Tasks

@Suite
@MainActor
struct TitlePersistenceTests {
    @Test
    func rapidEditsSurviveLeavingTheDetailAndReopeningTheDatabase() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let persistentStore = try disk.open()
        let store = SwiftDataTaskRepository(store: persistentStore)
        let id = UUID()
        try await store.createTask(id: id, title: "Original")
        let monitor = NetworkMonitor(startMonitoring: false)
        monitor.setOnline(false)
        let coordinator = SyncCoordinator(store: store, syncService: MockSyncService(latency: .zero), networkMonitor: monitor)
        let viewModel = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: coordinator.didWriteLocally)
        await viewModel.refresh()

        for title in ["F", "Fi", "Fin", "Final title"] {
            viewModel.editTitle(id: id, title: title)
        }
        #expect(viewModel.hasUnsavedTitle(id: id))
        viewModel.finishTitleEditing(id: id)
        coordinator.suspend()
        await viewModel.flushTitleEdits()

        coordinator.suspend()
        let reopened = SwiftDataTaskRepository(store: try disk.open())
        let snapshot = try await reopened.snapshot(id: id)
        #expect(snapshot?.title == "Final title")
        #expect(snapshot?.pendingSync == true)
        #expect(viewModel.title(id: id) == "Final title")
        #expect(viewModel.failure == nil)
        #expect(!viewModel.hasUnsavedTitle(id: id))
    }

    @Test
    func deletingWhileTitleWritesAreQueuedDoesNotRecreateTheTask() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Original")
        let monitor = NetworkMonitor(startMonitoring: false)
        monitor.setOnline(false)
        let coordinator = SyncCoordinator(store: store, syncService: MockSyncService(latency: .zero), networkMonitor: monitor)
        let viewModel = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: coordinator.didWriteLocally)
        await viewModel.refresh()
        viewModel.editTitle(id: id, title: "First edit")
        viewModel.editTitle(id: id, title: "Last edit")

        let deleted = await viewModel.delete(id: id)
        await viewModel.flushTitleEdits()
        let snapshot = try await store.snapshot(id: id)
        let deletions = try await store.pendingDeletionIDs()
        #expect(deleted)
        #expect(snapshot == nil)
        #expect(deletions == [id])
        #expect(viewModel.title(id: id).isEmpty)
        coordinator.suspend()
    }

    @Test
    func anEmptyTitleIsNotReportedAsPersistedAndCanBeCorrected() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Original")
        let monitor = NetworkMonitor(startMonitoring: false)
        monitor.setOnline(false)
        let coordinator = SyncCoordinator(store: store, syncService: MockSyncService(latency: .zero), networkMonitor: monitor)
        let viewModel = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: coordinator.didWriteLocally)
        await viewModel.refresh()
        viewModel.editTitle(id: id, title: "")
        await viewModel.flushTitleEdits()

        let original = try await store.snapshot(id: id)
        #expect(original?.title == "Original")
        #expect(viewModel.title(id: id).isEmpty)
        #expect(viewModel.failure == .emptyTitle)

        viewModel.editTitle(id: id, title: "Corrected")
        await viewModel.flushTitleEdits()
        let corrected = try await store.snapshot(id: id)
        #expect(corrected?.title == "Corrected")
        #expect(viewModel.failure == nil)
        coordinator.suspend()
    }
}
