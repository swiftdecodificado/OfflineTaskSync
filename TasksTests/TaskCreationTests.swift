import Foundation
import SwiftData
import Testing
@testable import Tasks

@Suite @MainActor
struct TaskCreationTests {
    @Test func savesAllFieldsOnceAndSurvivesReopening() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let store = SwiftDataTaskRepository(store: try disk.open())
        var writes = 0
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: { writes += 1 })
        var draft = TaskDraft()
        draft.title = "  Ship the release  "
        draft.notes = "Keep the notes 📝"
        draft.dueDate = .now.addingTimeInterval(86400)
        draft.dueTime = draft.dueDate
        draft.reminderDate = .now.addingTimeInterval(600)
        #expect(await model.create(draft))
        #expect(await model.create(draft) == false)
        await model.flushTitleEdits()
        #expect(writes == 1)
        try disk.disconnect()
        let reader = SwiftDataTaskRepository(store: try disk.open())
        let tasks = try await reader.allTasks()
        let task = try #require(tasks.first)
        #expect(tasks.count == 1)
        #expect(task.title == "Ship the release")
        #expect(task.notes == draft.notes)
        #expect(task.dueDate == draft.dueDate.map { Calendar.current.startOfDay(for: $0) })
        #expect(task.dueTime == draft.dueTime)
        #expect(task.reminderDate == draft.reminderDate)
    }

    @Test func failedCreationRollsBackAllFieldsAndCanRetryTheSameDraft() async throws {
        var fail = true
        var saves = 0
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true), beforeSave: {
            saves += 1
            if fail { throw CocoaError(.fileWriteUnknown) }
        })
        let center = ReminderCenterDouble()
        center.status = .notDetermined
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), reminders: TaskReminders(center: center), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Keep my draft"
        draft.notes = "Do not lose these notes"
        draft.dueDate = .now
        draft.reminderDate = .now.addingTimeInterval(600)
        #expect(await model.create(draft) == false)
        #expect(try await store.allTasks().isEmpty)
        #expect(!store.hasChanges)
        #expect(center.permissionRequests == 0)
        #expect(model.failure == .create)
        fail = false
        #expect(await model.create(draft))
        await model.flushTitleEdits()
        #expect(saves == 2)
        #expect(try await store.snapshot(id: draft.id)?.notes == draft.notes)
    }

    @Test func deniedNotificationsKeepReminderIntentAndRetryDoesNotDuplicate() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let center = ReminderCenterDouble()
        center.status = .notDetermined
        let reminders = TaskReminders(center: center)
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), reminders: reminders, onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Saved before permission"
        draft.reminderDate = .now.addingTimeInterval(600)
        #expect(await model.create(draft))
        await model.flushTitleEdits()
        #expect(center.permissionRequests == 1)
        #expect(center.requests.isEmpty)
        #expect(try await store.snapshot(id: draft.id)?.reminderDate == draft.reminderDate)
        #expect(reminders.message != nil)
        center.status = .permitted
        await model.reconcileReminders()
        await model.reconcileReminders()
        #expect(center.requests.count == 1)
        #expect(center.additions == 1)
        #expect(try await store.allTasks().count == 1)
    }

    @Test func newTaskStartsWithDateAndTimeWithoutRequestingNotificationPermission() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let center = ReminderCenterDouble()
        center.status = .notDetermined
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), reminders: TaskReminders(center: center), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Quick task"
        #expect(await model.create(draft))
        await model.flushTitleEdits()
        let task = try #require(try await store.snapshot(id: draft.id))
        #expect(task.dueDate == Calendar.current.startOfDay(for: .now))
        #expect(task.dueTime == draft.dueTime)
        let defaultTime = try #require(task.dueTime)
        #expect(abs(defaultTime.timeIntervalSinceNow) < 120)
        #expect(task.reminderDate == nil)
        #expect(center.permissionRequests == 0)
    }

    @Test func defaultDateSurvivesSavingAndReopeningTheEditor() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let store = SwiftDataTaskRepository(store: try disk.open())
        var draft = TaskDraft()
        draft.title = "Created today"
        let creationDay = Calendar.current.startOfDay(for: .now)
        #expect(draft.dueDate == creationDay)
        try await store.saveDraft(draft, creating: true)
        try disk.disconnect()
        let reopened = SwiftDataTaskRepository(store: try disk.open())
        let saved = try #require(try await reopened.snapshot(id: draft.id))
        #expect(saved.dueDate == creationDay)
        let session = TaskEditingSession(task: saved, mediaStore: makeTestMediaStore())
        #expect(session.draft.dueDate == creationDay)
    }

    @Test func chosenDatePersistsAndCannotBeRemoved() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        var draft = TaskDraft()
        draft.title = "Chosen day"
        let selectedDay = try #require(Calendar.current.date(byAdding: .day, value: 3, to: Calendar.current.startOfDay(for: .now)))
        draft.dueDate = selectedDay
        try await store.saveDraft(draft, creating: true)
        let chosen = try #require(try await store.snapshot(id: draft.id))
        #expect(chosen.dueDate == selectedDay)
        #expect(Calendar.current.isDate(try #require(chosen.dueTime), inSameDayAs: selectedDay))
        draft.dueDate = nil
        await #expect(throws: TaskScheduleError.self) { try await store.saveDraft(draft, creating: false) }
        let saved = try #require(try await store.snapshot(id: draft.id))
        #expect(saved.dueDate == selectedDay)
        let session = TaskEditingSession(task: saved, mediaStore: makeTestMediaStore())
        #expect(session.draft.dueDate == selectedDay)
    }

    @Test func movingDeadlineKeepsDueTimeAndIndependentReminder() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Separate dates"
        draft.dueDate = .now
        draft.dueTime = .now
        draft.reminderDate = .now.addingTimeInterval(600)
        #expect(await model.create(draft))
        let newDay = Date.now.addingTimeInterval(172800)
        model.editDueDate(id: draft.id, date: newDay)
        await model.flushTitleEdits()
        let task = try #require(try await store.snapshot(id: draft.id))
        #expect(task.reminderDate == draft.reminderDate)
        #expect(task.dueTime.map { Calendar.current.startOfDay(for: $0) } == Calendar.current.startOfDay(for: newDay))
        #expect(task.dueTime.map { Calendar.current.component(.hour, from: $0) } == draft.dueTime.map { Calendar.current.component(.hour, from: $0) })
        model.editDueDate(id: draft.id, date: nil)
        await model.flushTitleEdits()
        #expect(model.failure == .update)
        #expect(try await store.snapshot(id: draft.id)?.dueTime == task.dueTime)
        #expect(try await store.snapshot(id: draft.id)?.reminderDate == draft.reminderDate)
    }

    @Test func missingDateOrTimeCannotBeSavedThroughTheEditorOrRepository() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        for missingDate in [false, true] {
            var draft = TaskDraft()
            draft.title = "Required schedule"
            if missingDate { draft.dueDate = nil } else { draft.dueTime = nil }
            let session = TaskEditingSession(draft: draft, mediaStore: makeTestMediaStore())
            #expect(!session.canSave)
            await #expect(throws: TaskScheduleError.self) { try await store.saveDraft(draft, creating: true) }
            await #expect(throws: TaskScheduleError.self) {
                try await store.createTask(id: draft.id, title: draft.title, notes: "", dueDate: draft.dueDate,
                                           dueTime: draft.dueTime, reminderDate: nil, icon: nil)
            }
            #expect(try await store.snapshot(id: draft.id) == nil)
        }
    }

    @Test func migratesV2WithDatesAndCalendarLinkIntact() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tasks.store")
        let id = UUID()
        let date = Date.now
        try autoreleasepool {
            let schema = Schema(versionedSchema: TasksSchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let task = TasksSchemaV2.StoredTask(id: id, title: "Existing task", isDone: false, updatedAt: date, pendingSync: true)
            task.notes = "Existing notes"
            task.dueDate = date
            task.reminderDate = date
            task.calendarEventID = "existing-event"
            task.calendarLinkDate = date
            context.insert(task)
            try context.save()
        }
        let persistent = try PersistenceContainer(storeURL: url)
        defer { persistent.disconnect() }
        let store = SwiftDataTaskRepository(store: persistent)
        let task = try #require(try await store.snapshot(id: id))
        #expect(task.notes == "Existing notes")
        #expect(task.dueDate == date)
        #expect(task.dueTime == nil)
        #expect(task.reminderDate == date)
        #expect(task.calendarEventID == "existing-event")
        #expect(task.calendarLinkDate == date)
    }
}
