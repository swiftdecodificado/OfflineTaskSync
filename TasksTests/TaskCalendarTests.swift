import Foundation
import Testing
@testable import Tasks

@MainActor
private final class CalendarClientDouble: TaskCalendarClient {
    var denied = false
    var creations = 0
    var destinations: [String] = []
    var updates: [TaskSnapshot] = []
    var events: [UUID: String] = [:]
    var onCreate: (() -> Void)?
    func authorize() async throws { if denied { throw TaskCalendarError.denied } }
    func calendars() throws -> [TaskCalendarChoice] { [TaskCalendarChoice(id: "test", title: "Test only")] }
    func defaultCalendarID() throws -> String { "default" }
    func existingEvent(for task: TaskSnapshot) throws -> String? { events[task.id] }
    func updateEvent(for task: TaskSnapshot) throws {
        if denied { throw TaskCalendarError.denied }
        guard task.dueDate != nil else { throw TaskCalendarError.missingDate }
        updates.append(task)
    }
    func createEvent(for task: TaskSnapshot, calendarID: String) throws -> String {
        creations += 1
        destinations.append(calendarID)
        let id = UUID().uuidString
        events[task.id] = id
        onCreate?()
        return id
    }
}

@Suite @MainActor struct TaskCalendarTests {
    @Test func repeatedRequestsDoNotDuplicateEventsAndDeletionKeepsEvent() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Calendar task")
        try await store.setDueDate(id: id, date: .now)
        let client = CalendarClientDouble()
        let service = TaskCalendar(client: client, repository: store)
        _ = try await service.choices()
        try await service.add(taskID: id, calendarID: "test")
        try await store.setDueDate(id: id, date: .now.addingTimeInterval(172800))
        try await service.add(taskID: id, calendarID: "test")
        #expect(client.creations == 1)
        #expect(try await store.snapshot(id: id)?.calendarEventID == client.events[id])
        try await store.delete(id: id)
        #expect(client.events[id] != nil)
    }

    @Test func retriesRecoverAfterEventCreationAndFailedReferenceSave() async throws {
        var fail = false
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true), beforeSave: {
            if fail { throw CocoaError(.fileWriteUnknown) }
        })
        let id = UUID()
        try await store.createTask(id: id, title: "Recover")
        let date = Date.now
        try await store.setDueDate(id: id, date: date)
        let client = CalendarClientDouble()
        client.onCreate = { fail = true }
        let service = TaskCalendar(client: client, repository: store)
        do {
            try await service.add(taskID: id, calendarID: "test")
            Issue.record("Expected reference save to fail")
        } catch { }
        #expect(try await store.snapshot(id: id)?.calendarLinkDate == date)
        #expect(try await store.snapshot(id: id)?.calendarEventID == "")
        fail = false
        try await service.add(taskID: id, calendarID: "test")
        #expect(client.creations == 1)
        #expect(try await store.snapshot(id: id)?.calendarEventID == client.events[id])
    }

    @Test func creationSurvivesCalendarDenialAndRetryLinksOnlyOneEvent() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let client = CalendarClientDouble()
        client.denied = true
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), calendar: TaskCalendar(client: client, repository: store), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Keep the local task"
        draft.dueDate = .now
        draft.addToCalendar = true
        draft.calendarID = "test"
        #expect(await model.create(draft))
        await model.flushTitleEdits()
        #expect(try await store.allTasks().count == 1)
        #expect(client.creations == 0)
        #expect(model.pendingCalendarRequests[draft.id] == "test")
        client.denied = false
        model.retryCalendarRequests()
        model.retryCalendarRequests()
        await model.flushTitleEdits()
        #expect(client.creations == 1)
        #expect(model.pendingCalendarRequests.isEmpty)
        let reminder = Date.now.addingTimeInterval(600)
        try await store.setReminderDate(id: draft.id, date: reminder)
        model.editDueDate(id: draft.id, date: .now.addingTimeInterval(86400))
        await model.flushTitleEdits()
        #expect(client.updates.count == 1)
        #expect(client.updates.first?.reminderDate == reminder)
        #expect(client.creations == 1)
        client.denied = true
        model.editDueDate(id: draft.id, date: .now.addingTimeInterval(172800))
        await model.flushTitleEdits()
        #expect(model.hasPendingCalendarRequests)
        #expect(try await store.snapshot(id: draft.id)?.reminderDate == reminder)
        client.denied = false
        model.retryCalendarRequests()
        await model.flushTitleEdits()
        #expect(!model.hasPendingCalendarRequests)
        #expect(client.updates.count == 2)
        #expect(client.creations == 1)
    }

    @Test func deniedAndRevokedPermissionsDoNotCreateEvents() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Keep")
        let client = CalendarClientDouble()
        let service = TaskCalendar(client: client, repository: store)
        _ = try await service.choices()
        client.denied = true
        do {
            try await service.add(taskID: id, calendarID: "test")
            Issue.record("Expected denied access")
        } catch { #expect(error as? TaskCalendarError == .denied) }
        #expect(client.creations == 0)
        #expect(try await store.snapshot(id: id)?.calendarEventID == nil)
    }
}
