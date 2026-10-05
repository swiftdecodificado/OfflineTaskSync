import Foundation
import SwiftData
import Testing
import UIKit
@testable import Tasks

@Suite @MainActor
struct TaskIconTests {
    @Test func everyChoiceUsesAnAvailableSystemSymbol() {
        for icon in TaskIcon.allCases {
            #expect(UIImage(systemName: icon.rawValue) != nil)
            #expect(!icon.title.isEmpty)
        }
    }

    @Test func choiceSurvivesReopeningEditingExportCompletionAndRemoval() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let first = SwiftDataTaskRepository(store: try disk.open())
        let model = TasksViewModel(store: first, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Exercise"
        draft.notes = "Keep these notes"
        draft.icon = .exercise
        #expect(await model.create(draft))
        await model.flushTitleEdits()
        try disk.disconnect()

        let second = SwiftDataTaskRepository(store: try disk.open())
        let editor = TasksViewModel(store: second, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        await editor.refresh()
        #expect(editor.task(id: draft.id)?.icon == .exercise)
        editor.editIcon(id: draft.id, icon: .study)
        await editor.flushTitleEdits()
        #expect(editor.task(id: draft.id)?.icon == .study)
        #expect(await editor.toggle(id: draft.id))
        await editor.undoCompletion()
        #expect(editor.task(id: draft.id)?.icon == .study)
        let export = try #require(await editor.prepareExport())
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(TaskArchive.self, from: export.data)
        #expect(archive.tasks.first?.icon == .study)
        editor.editIcon(id: draft.id, icon: nil)
        await editor.flushTitleEdits()
        try disk.disconnect()

        let reader = SwiftDataTaskRepository(store: try disk.open())
        let task = try #require(try await reader.snapshot(id: draft.id))
        #expect(task.iconName == nil)
        #expect(task.notes == draft.notes)
        #expect(task.isDone == false)
    }

    @Test func failedWritesKeepTheDraftAndPreviousChoice() async throws {
        var fail = true
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true), beforeSave: {
            if fail { throw CocoaError(.fileWriteUnknown) }
        })
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Keep my choice"
        draft.icon = .exercise
        #expect(await model.create(draft) == false)
        #expect(try await store.allTasks().isEmpty)
        fail = false
        #expect(await model.create(draft))
        await model.flushTitleEdits()
        fail = true
        model.editIcon(id: draft.id, icon: .study)
        await model.flushTitleEdits()
        #expect(model.failure == .update)
        #expect(model.task(id: draft.id)?.icon == .exercise)
        #expect(try await store.snapshot(id: draft.id)?.icon == .exercise)
        fail = false
        model.editIcon(id: draft.id, icon: .study)
        await model.flushTitleEdits()
        #expect(model.task(id: draft.id)?.icon == .study)
        #expect(try await store.allTasks().count == 1)
    }

    @Test func syncAcknowledgementsAndRemoteUpdatesKeepTheLocalIcon() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Local task"
        draft.icon = .exercise
        #expect(await model.create(draft))
        await model.flushTitleEdits()
        let sent = try #require(try await store.snapshot(id: draft.id))
        try await store.setIcon(id: draft.id, icon: .study)
        try await store.markSynced(sent)
        let updated = try #require(try await store.snapshot(id: draft.id))
        #expect(updated.pendingSync)
        try await store.markSynced(updated)
        try await store.applyRemoteSnapshot(RemoteTaskSnapshot(id: draft.id, title: "Remote title", isDone: false,
                                                             updatedAt: updated.updatedAt.addingTimeInterval(1)))
        let merged = try #require(try await store.snapshot(id: draft.id))
        #expect(merged.title == "Remote title")
        #expect(merged.icon == .study)
    }

    @Test func oldAndUnknownIconValuesCanBeDecoded() throws {
        let task = TaskSnapshot(id: UUID(), title: "Legacy task", isDone: false, updatedAt: .now,
                                pendingSync: true, iconName: TaskIcon.exercise.rawValue)
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(task)) as? [String: Any])
        json.removeValue(forKey: "iconName")
        let legacy = try JSONDecoder().decode(TaskSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(legacy.iconName == nil)
        json["iconName"] = "future.symbol.name"
        let unknown = try JSONDecoder().decode(TaskSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(unknown.icon == nil)
        #expect(unknown.iconName == "future.symbol.name")
    }

    @Test func migrationFromV3KeepsExistingTaskFieldsAndDeletionMarkers() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tasks.store")
        let id = UUID()
        let deletionID = UUID()
        let date = Date.now
        try autoreleasepool {
            let schema = Schema(versionedSchema: TasksSchemaV3.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let task = TasksSchemaV3.StoredTask(id: id, title: "Existing task", isDone: true, updatedAt: date, pendingSync: true)
            task.notes = "Existing notes"
            task.dueDate = date
            task.dueTime = date
            task.reminderDate = date
            task.calendarEventID = "existing-event"
            task.calendarLinkDate = date
            context.insert(task)
            context.insert(TasksSchemaV3.StoredDeletion(id: deletionID, requestedAt: date))
            try context.save()
        }
        let persistent = try PersistenceContainer(storeURL: url)
        defer { persistent.disconnect() }
        let store = SwiftDataTaskRepository(store: persistent)
        let task = try #require(try await store.snapshot(id: id))
        #expect(task.iconName == nil)
        #expect(task.title == "Existing task")
        #expect(task.notes == "Existing notes")
        #expect(task.isDone)
        #expect(task.pendingSync)
        #expect(task.dueDate == date)
        #expect(task.dueTime == date)
        #expect(task.reminderDate == date)
        #expect(task.calendarEventID == "existing-event")
        #expect(task.calendarLinkDate == date)
        #expect(try await store.pendingDeletionIDs() == [deletionID])
    }
}
