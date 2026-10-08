import Foundation
import SwiftData
import Testing

@testable import Tasks

@Suite @MainActor
struct FreePersistenceTests {
    @Test
    func migratesV1WithoutLosingTasksOrDeletions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tasks.store")
        let id = UUID()
        let deletedID = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: TasksSchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            context.insert(TasksSchemaV1.StoredTask(id: id, title: "Existing task", isDone: true, updatedAt: .now, pendingSync: true))
            context.insert(TasksSchemaV1.StoredDeletion(id: deletedID, requestedAt: .now))
            try context.save()
        }
        let persistent = try PersistenceContainer(storeURL: url)
        defer { persistent.disconnect() }
        let store = SwiftDataTaskRepository(store: persistent)
        let task = try #require(try await store.snapshot(id: id))
        #expect(task.title == "Existing task")
        #expect(task.isDone)
        #expect(task.notes.isEmpty)
        #expect(task.dueDate == nil)
        #expect(try await store.pendingDeletionIDs() == [deletedID])
    }

    @Test
    func descriptionSurvivesReopeningAndRapidEdits() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let store = SwiftDataTaskRepository(store: try disk.open())
        let id = UUID()
        try await store.createTask(id: id, title: "Title only")
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        await model.refresh()
        for notes in ["D", "Description", "Final description 📝"] {
            model.editNotes(id: id, notes: notes)
        }
        await model.flushTitleEdits()
        try disk.disconnect()
        let reader = SwiftDataTaskRepository(store: try disk.open())
        #expect(try await reader.snapshot(id: id)?.notes == "Final description 📝")
    }

    @Test
    func failedDescriptionSaveRetainsDraftAndRollsBack() async throws {
        enum Failure: Error { case save }
        var shouldFail = false
        let persistent = try PersistenceContainer(inMemory: true)
        let store = SwiftDataTaskRepository(store: persistent, beforeSave: { if shouldFail { throw Failure.save } })
        let id = UUID()
        try await store.createTask(id: id, title: "Original")
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        await model.refresh()
        shouldFail = true
        model.editNotes(id: id, notes: "Keep my draft")
        await model.flushTitleEdits()
        #expect(model.notes(id: id) == "Keep my draft")
        #expect(model.failure == .update)
        #expect(try await store.snapshot(id: id)?.notes == "")
        shouldFail = false
        model.editNotes(id: id, notes: model.notes(id: id))
        await model.flushTitleEdits()
        #expect(try await store.snapshot(id: id)?.notes == "Keep my draft")
    }
    @Test
    func deadlineChangesPreserveIndependentReminderAndSurviveReopening() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let store = SwiftDataTaskRepository(store: try disk.open())
        let id = UUID()
        try await store.createTask(id: id, title: "Dates")
        let reminder = Date.now.addingTimeInterval(3600)
        try await store.setReminderDate(id: id, date: reminder)
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        await model.refresh()
        let lastDate = Date.now.addingTimeInterval(172800)
        model.editDueDate(id: id, date: .now)
        model.editDueDate(id: id, date: lastDate)
        await model.flushTitleEdits()
        try disk.disconnect()
        let reader = SwiftDataTaskRepository(store: try disk.open())
        let task = try #require(try await reader.snapshot(id: id))
        #expect(task.dueDate == Calendar.current.startOfDay(for: lastDate))
        #expect(task.reminderDate == reminder)
        await #expect(throws: TaskScheduleError.self) { try await reader.setDueDate(id: id, date: nil) }
        #expect(try await reader.snapshot(id: id)?.dueDate == task.dueDate)
        #expect(try await reader.snapshot(id: id)?.reminderDate == reminder)
    }

    @Test
    func storesAreIsolatedAndDateFailuresRollBack() async throws {
        var fail = false
        let first = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true), beforeSave: {
            if fail { throw CocoaError(.fileWriteUnknown) }
        })
        let second = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await first.createTask(id: id, title: "Private local task")
        #expect(try await second.allTasks().isEmpty)
        let original = try await first.snapshot(id: id)
        fail = true
        do {
            try await first.setDueDate(id: id, date: .now)
            Issue.record("Expected deadline save failure")
        } catch { }
        do {
            try await first.setReminderDate(id: id, date: .now)
            Issue.record("Expected reminder save failure")
        } catch { }
        #expect(try await first.snapshot(id: id)?.dueDate == original?.dueDate)
        #expect(try await first.snapshot(id: id)?.reminderDate == nil)
    }

}
