import Foundation
import Testing
@testable import Tasks

@Suite @MainActor struct TaskExportTests {
    @Test func versionTwoExportKeepsDocumentsColorsAndSavedMetadataAfterDeletion() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        var draft = TaskDraft()
        draft.title = "Título 📝"
        draft.color = .lavender
        draft.icon = .study
        draft.isDone = true
        draft.dueDate = Date(timeIntervalSince1970: 1_790_000_000)
        draft.dueTime = Date(timeIntervalSince1970: 1_790_003_600)
        draft.reminderDate = Date(timeIntervalSince1970: 1_790_000_600)
        draft.document = TaskDocument(blocks: [.text(TaskRichText(id: UUID(), rtf: Data("notes".utf8), plainText: "Line 1\nLine 2: café"))])
        try await store.saveDraft(draft, creating: true)
        try await store.linkCalendar(id: draft.id, eventID: "local-event", date: draft.dueDate!)
        try await store.createTask(title: "Without deadline")
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        await model.refresh()
        let before = model.tasks
        let export = try #require(await model.prepareExport())
        try await store.delete(id: draft.id)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(TaskArchive.self, from: export.data)
        #expect(archive.formatVersion == 3)
        #expect(archive.tasks.count == before.count)
        for task in archive.tasks {
            let original = try #require(before.first { $0.id == task.id })
            #expect(task.id == original.id)
            #expect(task.title == original.title)
            #expect(task.notes == original.notes)
            #expect(task.document == original.document)
            #expect(task.color == original.color)
            #expect(task.colorID == original.colorID)
            #expect(task.iconName == original.iconName)
            #expect(task.isDone == original.isDone)
            #expect(task.pendingSync == original.pendingSync)
            #expect(task.dueDate == original.dueDate)
            #expect(task.dueTime == original.dueTime)
            #expect(task.reminderDate == original.reminderDate)
            #expect(task.calendarEventID == original.calendarEventID)
            #expect(task.calendarLinkDate == original.calendarLinkDate)
            #expect(abs(task.updatedAt.timeIntervalSince(original.updatedAt)) < 0.00001)
        }
        #expect(archive.tasks.first { $0.id == draft.id }?.color == .lavender)
        #expect(try await store.snapshot(id: draft.id) == nil)
    }

    @Test func failedReadsAndUnsavedEditsProduceAnErrorInsteadOfPartialExport() async throws {
        var failSave = false
        var failFetch = false
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true), beforeSave: {
            if failSave { throw CocoaError(.fileWriteUnknown) }
        }, beforeFetch: {
            if failFetch { throw CocoaError(.fileReadUnknown) }
        })
        let id = UUID()
        try await store.createTask(id: id, title: "Keep")
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        await model.refresh()
        failFetch = true
        #expect(await model.prepareExport() == nil)
        #expect(model.serviceMessage != nil)
        failFetch = false
        failSave = true
        model.editNotes(id: id, notes: "Unsaved text")
        #expect(await model.prepareExport() == nil)
        #expect(model.notes(id: id) == "Unsaved text")
    }
}
