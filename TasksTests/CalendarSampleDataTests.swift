import Foundation
import Testing
@testable import Tasks

@Suite @MainActor struct CalendarSampleDataTests {
    @Test func replacementRemovesOldTasksAndDeletionMarkersAndPersistsScheduledSamples() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let persistent = try disk.open()
        let store = SwiftDataTaskRepository(store: persistent)
        let oldID = UUID()
        try await store.createTask(id: oldID, title: "Old data")
        try await store.delete(id: UUID())
        let count = try CalendarSampleData.replace(in: persistent)
        try disk.disconnect()
        let reopened = SwiftDataTaskRepository(store: try disk.open())
        let samples = try await reopened.allTasks()
        #expect(count == 12)
        #expect(samples.count == count)
        #expect(samples.allSatisfy { $0.id != oldID && !$0.notes.isEmpty })
        #expect(samples.allSatisfy { task in
            guard let day = task.dueDate, let start = task.dueTime, let end = task.dueEndTime else { return false }
            return Calendar.current.isDate(start, inSameDayAs: day) && end > start
        })
        #expect(try await reopened.pendingDeletionIDs().isEmpty)
    }

    @Test func replacementFailureKeepsExistingTasksAndDeletionMarkers() async throws {
        let persistent = try PersistenceContainer(inMemory: true)
        let store = SwiftDataTaskRepository(store: persistent)
        try await store.createTask(title: "Keep until replacement succeeds")
        let deletionID = UUID()
        try await store.delete(id: deletionID)
        let before = try await store.allTasks()
        #expect(throws: CocoaError.self) {
            try CalendarSampleData.replace(in: persistent, beforeSave: { throw CocoaError(.fileWriteUnknown) })
        }
        #expect(try await store.allTasks() == before)
        #expect(try await store.pendingDeletionIDs() == [deletionID])
    }
}
