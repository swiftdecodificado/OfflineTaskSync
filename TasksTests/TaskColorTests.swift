import Foundation
import SwiftData
import Testing
@testable import Tasks

@Suite @MainActor
struct TaskColorTests {
    @Test(arguments: TaskColor.allCases)
    func colorSurvivesReopeningEditingCompletionAndExport(color: TaskColor) async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let store = SwiftDataTaskRepository(store: try disk.open())
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Colored task"
        draft.color = color
        #expect(await model.create(draft))
        await model.flushTitleEdits()
        try disk.disconnect()

        let reopened = SwiftDataTaskRepository(store: try disk.open())
        let saved = try #require(try await reopened.snapshot(id: draft.id))
        #expect(saved.color == color)
        let session = TaskEditingSession(task: saved, mediaStore: model.mediaStore)
        #expect(session.draft.color == color)
        let changed: TaskColor = color == .blue ? .pink : .blue
        session.draft.color = changed
        try await reopened.saveDraft(session.draft, creating: false)
        try await reopened.toggleDone(id: draft.id)
        try await reopened.setDueDate(id: draft.id, date: .now)
        try disk.disconnect()

        let reader = SwiftDataTaskRepository(store: try disk.open())
        let completed = try #require(try await reader.snapshot(id: draft.id))
        #expect(completed.isDone)
        #expect(completed.color == changed)
        let export = try TaskExport(tasks: [completed])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        #expect(try decoder.decode(TaskArchive.self, from: export.data).tasks.first?.color == changed)
    }

    @Test func missingAndUnknownIdentifiersUseTheDefault() throws {
        var task = TaskSnapshot(id: UUID(), title: "Existing task", isDone: false, updatedAt: .now, pendingSync: false)
        #expect(task.color == .yellow)
        #expect(TaskDraft().color == .yellow)
        task.colorID = "unknown"
        #expect(task.color == .yellow)
        let encoded = try JSONEncoder().encode(task)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object.removeValue(forKey: "colorID")
        let oldData = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(TaskSnapshot.self, from: oldData).color == .yellow)
    }

    @Test func failedEditKeepsTheSavedColorAndDraft() async throws {
        var fails = false
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true), beforeSave: {
            if fails { throw CocoaError(.fileWriteUnknown) }
        })
        var draft = TaskDraft()
        draft.title = "Keep my color"
        draft.color = .mint
        try await store.saveDraft(draft, creating: true)
        draft.color = .peach
        fails = true
        await #expect(throws: (any Error).self) { try await store.saveDraft(draft, creating: false) }
        #expect(draft.color == .peach)
        #expect(try await store.snapshot(id: draft.id)?.color == .mint)
    }

    @Test func previousStoreOpensWithDefaultColorWithoutLosingContent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tasks.store")
        let id = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: TasksSchemaV5.self)
            let config = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = ModelContext(container)
            let task = TasksSchemaV5.StoredTask(id: id, title: "Existing notes", isDone: true, updatedAt: .now, pendingSync: false)
            task.notes = "Keep this text"
            context.insert(task)
            try context.save()
        }
        let container = try PersistenceContainer(storeURL: url)
        defer { container.disconnect() }
        let reader = SwiftDataTaskRepository(store: container)
        let task = try #require(try await reader.snapshot(id: id))
        #expect(task.color == .yellow)
        #expect(task.isDone)
        #expect(task.notes == "Keep this text")
    }
}
