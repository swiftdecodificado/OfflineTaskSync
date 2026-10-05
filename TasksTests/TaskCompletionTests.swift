import Foundation
import Testing
@testable import Tasks

@Suite @MainActor
struct TaskCompletionTests {
    @Test func undoRestoresTaskAndReminderAfterCompletion() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let store = SwiftDataTaskRepository(store: try disk.open())
        let center = ReminderCenterDouble()
        center.status = .permitted
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), reminders: TaskReminders(center: center), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Review release notes"
        draft.notes = "Keep this description"
        draft.dueDate = .now
        draft.reminderDate = .now.addingTimeInterval(3600)
        #expect(await model.create(draft))
        await model.flushTitleEdits()
        #expect(center.requests.count == 1)
        #expect(await model.toggle(id: draft.id))
        #expect(center.requests.isEmpty)
        #expect(model.completionUndo?.id == draft.id)
        await model.undoCompletion()
        #expect(model.completionUndo == nil)
        #expect(center.requests.count == 1)
        let reader = SwiftDataTaskRepository(store: try disk.open())
        let restored = try #require(try await reader.snapshot(id: draft.id))
        #expect(!restored.isDone)
        #expect(restored.notes == draft.notes)
        #expect(restored.reminderDate == draft.reminderDate)
        #expect(restored.pendingSync)
        await model.undoCompletion()
        #expect(try await store.snapshot(id: draft.id)?.isDone == false)
    }

    @Test func failedCompletionAndUndoKeepSavedState() async throws {
        var fail = false
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true), beforeSave: {
            if fail { throw CocoaError(.fileWriteUnknown) }
        })
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Keep the saved state"
        #expect(await model.create(draft))
        fail = true
        #expect(await model.toggle(id: draft.id) == false)
        #expect(model.completionUndo == nil)
        #expect(try await store.snapshot(id: draft.id)?.isDone == false)
        fail = false
        #expect(await model.toggle(id: draft.id))
        fail = true
        await model.undoCompletion()
        #expect(model.completionUndo?.id == draft.id)
        #expect(try await store.snapshot(id: draft.id)?.isDone == true)
        fail = false
        await model.undoCompletion()
        #expect(model.completionUndo == nil)
        #expect(try await store.snapshot(id: draft.id)?.isDone == false)
    }

    @Test func undoTracksLatestCompletionAndDeletionClearsIt() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        var first = TaskDraft()
        first.title = "First"
        var second = TaskDraft()
        second.title = "Second"
        #expect(await model.create(first))
        #expect(await model.create(second))
        #expect(await model.toggle(id: first.id))
        #expect(await model.toggle(id: second.id))
        #expect(model.completionUndo?.id == second.id)
        #expect(await model.delete(id: second.id))
        #expect(model.completionUndo == nil)
        await model.undoCompletion()
        #expect(try await store.snapshot(id: first.id)?.isDone == true)
    }
    @Test func differentTasksCanBeCompletedTogether() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        var first = TaskDraft()
        first.title = "First task"
        var second = TaskDraft()
        second.title = "Second task"
        #expect(await model.create(first))
        #expect(await model.create(second))
        let firstID = first.id
        let secondID = second.id
        async let firstSaved = model.toggle(id: firstID)
        async let secondSaved = model.toggle(id: secondID)
        let saved = await (firstSaved, secondSaved)
        #expect(saved.0 && saved.1)
        #expect(try await store.snapshot(id: first.id)?.isDone == true)
        #expect(try await store.snapshot(id: second.id)?.isDone == true)
    }

}
