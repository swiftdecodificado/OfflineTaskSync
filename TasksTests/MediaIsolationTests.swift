import Foundation
import Testing
@testable import Tasks

@Suite @MainActor
struct MediaIsolationTests {
    @Test func recoveringAnEmptyStoreKeepsOtherStoresFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MediaIsolation-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("sample.txt")
        let content = Data("Keep this attachment".utf8)
        try content.write(to: source)
        let normal = TaskMediaStore(root: directory.appendingPathComponent("Normal"))
        let isolated = TaskMediaStore(root: directory.appendingPathComponent("Isolated"))
        let sessionID = UUID()
        let attachment = try await normal.importFile(source, kind: .file, sessionID: sessionID)
        _ = try await normal.prepare([attachment], sessionID: sessionID)
        await normal.finish(sessionID: sessionID, removed: [], keeping: [attachment.id])
        try await isolated.recover(referenced: [])
        let file = try await normal.resolve(attachment, sessionID: sessionID)
        #expect(try Data(contentsOf: file) == content)
    }

    @Test func editingAndDeletingUseTheInjectedMediaStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EditorMedia-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("note.txt")
        let content = Data("Editor attachment".utf8)
        try content.write(to: source)
        let media = TaskMediaStore(root: directory.appendingPathComponent("Media"))
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let model = TasksViewModel(store: store, mediaStore: media, onLocalWrite: {})
        await model.prepareEditorStorage()
        var draft = TaskDraft()
        draft.title = "Task with a file"
        let session = TaskEditingSession(draft: draft, mediaStore: media)
        session.importFiles([source])
        for _ in 0..<100 where session.isImporting { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!session.isImporting)
        #expect(session.errorMessage == nil)
        let saved = await session.save(using: model)
        #expect(saved)
        let task = try #require(try await store.snapshot(id: draft.id))
        let attachment = try #require(task.document?.attachments.first)
        let file = try await media.resolve(attachment, sessionID: session.id)
        #expect(try Data(contentsOf: file) == content)
        #expect(await model.delete(id: draft.id))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test func regressionEnvironmentUsesTemporaryMediaStorage() async throws {
        try #require(ProcessInfo.processInfo.environment["TASKS_REGRESSION_TEST_HOST"] == "1")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("EnvironmentMedia-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("sample.txt")
        try Data("Test media".utf8).write(to: source)
        let environment = AppEnvironment()
        let media = environment.viewModel.mediaStore
        let sessionID = UUID()
        let attachment = try await media.importFile(source, kind: .file, sessionID: sessionID)
        let file = try await media.resolve(attachment, sessionID: sessionID)
        #expect(file.standardizedFileURL.path.hasPrefix(FileManager.default.temporaryDirectory.standardizedFileURL.path + "/"))
        #expect(!file.path.contains("Application Support/TaskMedia"))
        await media.discard(sessionID: sessionID)
    }
}
