import Foundation
import Testing
@testable import Tasks

@MainActor
final class ReminderCenterDouble: ReminderCenter {
    var status: ReminderAccess = .permitted
    var granted = false
    var requests: [ReminderRequest] = []
    var delivered: Set<String> = []
    var permissionRequests = 0
    var additions = 0
    var failAdd = false
    func access() async -> ReminderAccess { status }
    func requestAccess() async throws -> Bool {
        permissionRequests += 1
        status = granted ? .permitted : .denied
        return granted
    }
    func pending() async -> [ReminderRequest] { requests }
    func add(_ request: ReminderRequest) async throws {
        if failAdd { throw CocoaError(.fileWriteUnknown) }
        additions += 1
        requests.removeAll { $0.id == request.id }
        requests.append(request)
    }
    func remove(ids: [String]) {
        requests.removeAll { ids.contains($0.id) }
        delivered.subtract(ids)
    }
    func cleanDelivered(activeIDs: Set<String>) async { delivered.formIntersection(activeIDs) }
}

@Suite @MainActor struct TaskReminderTests {
    @Test func schedulesReschedulesAndCancelsWithoutDuplicates() async {
        let center = ReminderCenterDouble()
        let service = TaskReminders(center: center)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        var task = TaskSnapshot(id: UUID(), title: "Reminder", isDone: false, updatedAt: now, pendingSync: true, reminderDate: now.addingTimeInterval(600))
        await service.reconcile(tasks: [task], now: now)
        await service.reconcile(tasks: [task], now: now)
        #expect(center.requests.count == 1)
        #expect(center.additions == 1)
        task.reminderDate = now.addingTimeInterval(1200)
        await service.reconcile(tasks: [task], now: now)
        #expect(center.requests.first?.date == task.reminderDate)
        task = TaskSnapshot(id: task.id, title: task.title, isDone: true, updatedAt: now, pendingSync: true, reminderDate: task.reminderDate)
        center.delivered = Set(center.requests.map(\.id))
        await service.reconcile(tasks: [task], now: now)
        #expect(center.requests.isEmpty)
        #expect(center.delivered.isEmpty)
        #expect(center.permissionRequests == 0)
    }

    @Test func deniedPermissionKeepsTasksAndDoesNotPromptOnReconciliation() async throws {
        let center = ReminderCenterDouble()
        center.status = .notDetermined
        let service = TaskReminders(center: center)
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let id = UUID()
        try await store.createTask(id: id, title: "Keep")
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), reminders: service, onLocalWrite: {})
        await model.refresh()
        await model.reconcileReminders()
        #expect(center.permissionRequests == 0)
        model.editReminderDate(id: id, date: .now.addingTimeInterval(600))
        await model.flushTitleEdits()
        #expect(center.permissionRequests == 1)
        #expect(try await store.snapshot(id: id)?.reminderDate == nil)
        #expect(model.tasks.count == 1)
        #expect(service.message != nil)
    }

    @Test func repairsMissingSchedulesAndRemovesDeletedOrRevokedSchedules() async {
        let center = ReminderCenterDouble()
        let service = TaskReminders(center: center)
        let task = TaskSnapshot(id: UUID(), title: "Recover", isDone: false, updatedAt: .now, pendingSync: true, reminderDate: .now.addingTimeInterval(600))
        center.failAdd = true
        await service.reconcile(tasks: [task])
        #expect(service.message != nil)
        center.failAdd = false
        await service.reconcile(tasks: [task])
        #expect(center.requests.count == 1)
        center.status = .denied
        await service.reconcile(tasks: [task])
        #expect(center.requests.isEmpty)
        #expect(service.message != nil)
        center.status = .permitted
        await service.reconcile(tasks: [task])
        await service.reconcile(tasks: [])
        #expect(center.requests.isEmpty)
    }
    @Test func editorSchedulesBeforeSaveReturnsAndUpdatesWithoutDuplicates() async throws {
        let center = ReminderCenterDouble()
        center.status = .notDetermined
        center.granted = true
        let reminders = TaskReminders(center: center)
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), reminders: reminders, onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Ready before closing"
        draft.reminderDate = Date(timeIntervalSince1970: floor(Date.now.timeIntervalSince1970) + 600)
        #expect(await model.saveEditingDraft(draft, creating: true))
        #expect(center.requests.count == 1)
        #expect(center.requests.first?.date == draft.reminderDate)
        #expect(center.permissionRequests == 1)
        #expect(reminders.authorizationStatus == .permitted)
        draft.reminderDate = draft.reminderDate?.addingTimeInterval(600)
        #expect(await model.saveEditingDraft(draft, creating: false))
        #expect(center.requests.count == 1)
        #expect(center.requests.first?.date == draft.reminderDate)
        draft.reminderDate = nil
        #expect(await model.saveEditingDraft(draft, creating: false))
        #expect(center.requests.isEmpty)
    }

    @Test func quickCreationSchedulesBeforeReturning() async throws {
        let center = ReminderCenterDouble()
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(),
                                   reminders: TaskReminders(center: center), onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Ready immediately"
        draft.reminderDate = .now.addingTimeInterval(600)
        #expect(await model.create(draft))
        #expect(center.requests.count == 1)
        #expect(center.permissionRequests == 0)
    }

    @Test func concurrentPermissionRequestsShareTheSystemPrompt() async {
        let center = ReminderCenterDouble()
        center.status = .notDetermined
        center.granted = true
        let reminders = TaskReminders(center: center)
        async let first = reminders.authorize()
        async let second = reminders.authorize()
        let granted = await (first, second)
        #expect(granted.0 && granted.1)
        #expect(center.permissionRequests == 1)
        #expect(!reminders.isRequestingPermission)
        #expect(reminders.authorizationStatus == .permitted)
    }

    @Test func deniedPermissionKeepsTheEditorReminderForSettingsRetry() async throws {
        let center = ReminderCenterDouble()
        center.status = .denied
        let reminders = TaskReminders(center: center)
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        let model = TasksViewModel(store: store, mediaStore: makeTestMediaStore(), reminders: reminders, onLocalWrite: {})
        var draft = TaskDraft()
        draft.title = "Keep reminder intent"
        draft.reminderDate = .now.addingTimeInterval(600)
        #expect(await model.saveEditingDraft(draft, creating: true))
        #expect(center.requests.isEmpty)
        #expect(try await store.snapshot(id: draft.id)?.reminderDate == draft.reminderDate)
        #expect(reminders.authorizationStatus == .denied)
        center.status = .permitted
        await model.reconcileReminders()
        #expect(center.requests.count == 1)
        #expect(reminders.authorizationStatus == .permitted)
        #expect(reminders.message == nil)
    }

}
