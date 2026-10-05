import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.offlinetasksync.tasks", category: "TasksViewModel")

@MainActor
@Observable
final class TasksViewModel {
    enum Failure: Equatable {
        case load
        case create
        case update
        case delete
        case emptyTitle

        var message: String {
            switch self {
            case .load:
                AppLocalization.string("Couldn't load tasks. Any tasks already shown have been kept. Try again.")
            case .create:
                AppLocalization.string("Couldn't save the new task. Your text has been kept. Try adding it again.")
            case .update:
                AppLocalization.string("Couldn't save the change. Your edited text has been kept. Try again.")
            case .delete:
                AppLocalization.string("Couldn't delete the task. It has been kept. Try again.")
            case .emptyTitle:
                AppLocalization.string("Enter a task title. The previous title is still saved.")
            }
        }
    }

    private(set) var tasks: [TaskSnapshot] = []
    private(set) var hasLoadedTasks = false
    private(set) var failure: Failure?
    private(set) var isAdding = false
    private(set) var completionUndo: TaskSnapshot?
    private var changingCompletionIDs: Set<UUID> = []
    var isChangingCompletion: Bool { !changingCompletionIDs.isEmpty }
    var newTaskTitle = ""
    var serviceMessage: String?
    let mediaStore: TaskMediaStore
    let reminders: TaskReminders?
    let calendar: TaskCalendar?

    private(set) var pendingCalendarRequests: [UUID: String] = [:]
    private(set) var pendingDefaultCalendarRequests: Set<UUID> = []
    private var pendingCalendarUpdates: Set<UUID> = []
    var hasPendingCalendarRequests: Bool {
        !pendingCalendarRequests.isEmpty || !pendingDefaultCalendarRequests.isEmpty || !pendingCalendarUpdates.isEmpty
    }
    private var savedCreationIDs: Set<UUID> = []
    private let store: any TaskRepository
    private let onLocalWrite: @MainActor () -> Void
    private var notesDrafts: [UUID: String] = [:]
    private var refreshVersion = 0
    private var editorStoragePrepared = false
    private var titleDrafts: [UUID: String] = [:]
    @ObservationIgnored private var titleWriteTask: Task<Void, Never>?
    @ObservationIgnored private var titleWriteVersion = 0

    init(
        store: any TaskRepository,
        mediaStore: TaskMediaStore,
        reminders: TaskReminders? = nil,
        calendar: TaskCalendar? = nil,
        onLocalWrite: @escaping @MainActor () -> Void
    ) {
        self.store = store
        self.mediaStore = mediaStore
        self.reminders = reminders
        self.calendar = calendar
        self.onLocalWrite = onLocalWrite
    }

    func task(id: UUID) -> TaskSnapshot? {
        tasks.first { $0.id == id }
    }

    @discardableResult
    func add() async -> Bool {
        guard !isAdding else { return false }
        let title = newTaskTitle
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isAdding = true
        defer { isAdding = false }
        let saved = await write(failure: .create) {
            try await store.createTask(title: trimmed)
        }
        if saved, newTaskTitle == title {
            newTaskTitle = ""
        }
        return saved
    }

    @discardableResult
    func create(_ draft: TaskDraft) async -> Bool {
        guard !isAdding, !savedCreationIDs.contains(draft.id) else { return false }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { failure = .emptyTitle; return false }
        if let reminder = draft.reminderDate, reminder <= .now {
            serviceMessage = AppLocalization.string("Choose a future time for the reminder, or remove it.")
            return false
        }
        isAdding = true
        defer { isAdding = false }
        do {
            if draft.dueEndTime != nil {
                try await store.saveDraft(draft, creating: true)
            } else {
                try await store.createTask(id: draft.id, title: title, notes: draft.notes,
                                           dueDate: draft.dueDate.map { Calendar.current.startOfDay(for: $0) },
                                           dueTime: draft.dueTime, reminderDate: draft.reminderDate, icon: draft.icon, color: draft.color)
            }
        } catch {
            failure = .create
            return false
        }
        savedCreationIDs.insert(draft.id)
        if failure == .create || failure == .emptyTitle { failure = nil }
        onLocalWrite()
        await refresh()
        if draft.addToCalendar, draft.dueDate != nil {
            if let calendarID = draft.calendarID {
                pendingCalendarRequests[draft.id] = calendarID
            } else {
                pendingDefaultCalendarRequests.insert(draft.id)
            }
        }
        await scheduleReminders(requestPermission: draft.reminderDate != nil)
        enqueueTitleWrite { [self] in
            if draft.addToCalendar, draft.dueDate != nil {
                await linkCalendar(id: draft.id, calendarID: draft.calendarID)
            }
        }
        return true
    }

    @discardableResult
    func saveEditingDraft(_ draft: TaskDraft, creating: Bool) async -> Bool {
        guard !isAdding else { return false }
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { failure = .emptyTitle; return false }
        let previous = task(id: draft.id)
        if let reminder = draft.reminderDate, reminder <= .now, reminder != previous?.reminderDate {
            serviceMessage = AppLocalization.string("Choose a future time for the reminder, or remove it.")
            return false
        }
        isAdding = true
        defer { isAdding = false }
        await flushTitleEdits()
        do { try await store.saveDraft(draft, creating: creating) }
        catch { failure = creating ? .create : .update; return false }
        failure = nil
        if let previous {
            if !previous.isDone && draft.isDone { completionUndo = previous }
            else if !draft.isDone && completionUndo?.id == draft.id { completionUndo = nil }
        }
        onLocalWrite()
        await refresh()
        await scheduleReminders(requestPermission: !draft.isDone && draft.reminderDate != nil
                                && draft.reminderDate != previous?.reminderDate)
        enqueueTitleWrite { [self] in
            if draft.addToCalendar, draft.dueDate != nil {
                if let calendarID = draft.calendarID { pendingCalendarRequests[draft.id] = calendarID }
                else { pendingDefaultCalendarRequests.insert(draft.id) }
                await linkCalendar(id: draft.id, calendarID: draft.calendarID)
            }
            if previous?.calendarEventID?.isEmpty == false {
                await updateCalendarDeadline(id: draft.id)
            }
        }
        return true
    }

    func retryCalendarRequests() {
        for (id, calendarID) in pendingCalendarRequests { addToCalendar(id: id, calendarID: calendarID) }
        for id in pendingDefaultCalendarRequests {
            enqueueTitleWrite { [self] in await linkCalendar(id: id, calendarID: nil) }
        }
        for id in pendingCalendarUpdates {
            enqueueTitleWrite { [self] in await updateCalendarDeadline(id: id) }
        }
    }

    @discardableResult
    func toggle(id: UUID, onSaved: (Bool) async -> Void = { _ in }) async -> Bool {
        guard changingCompletionIDs.insert(id).inserted else { return false }
        defer { changingCompletionIDs.remove(id) }
        await flushTitleEdits()
        guard let previous = task(id: id) else { return false }
        let saved = await write(failure: .update, afterSave: { await onSaved(!previous.isDone) }) {
            try await store.toggleDone(id: id)
        }
        if saved {
            if !previous.isDone { completionUndo = previous }
            else if completionUndo?.id == id { completionUndo = nil }
        }
        return saved
    }

    func undoCompletion() async {
        guard let previous = completionUndo else { return }
        guard task(id: previous.id)?.isDone == true else {
            completionUndo = nil
            return
        }
        _ = await toggle(id: previous.id)
    }

    func dismissCompletionUndo() {
        completionUndo = nil
    }

    @discardableResult
    func rename(id: UUID, title: String) async -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            failure = .emptyTitle
            return false
        }
        let saved = await write(failure: .update) { try await store.rename(id: id, title: trimmed) }
        if saved, failure == .emptyTitle { failure = nil }
        return saved
    }

    func hasUnsavedText(id: UUID) -> Bool {
        hasUnsavedTitle(id: id) || notesDrafts[id].map { $0 != task(id: id)?.notes } == true
    }

    func prepareExport() async -> TaskExport? {
        await flushTitleEdits()
        guard !tasks.contains(where: { hasUnsavedText(id: $0.id) }) else {
            serviceMessage = AppLocalization.string("Save your text edits before exporting. Retry the edits shown in the error message.")
            return nil
        }
        do {
            let export = try TaskExport(tasks: try await store.allTasks())
            serviceMessage = nil
            return export
        } catch {
            serviceMessage = AppLocalization.string("Couldn't export your tasks. Your saved tasks are unchanged. Try again.")
            return nil
        }
    }

    func calendarChoices() async -> [TaskCalendarChoice] {
        guard let calendar else { return [] }
        do {
            serviceMessage = nil
            return try await calendar.choices()
        } catch {
            serviceMessage = error.localizedDescription
            return []
        }
    }

    func checkCalendarLink(id: UUID) {
        pendingDefaultCalendarRequests.insert(id)
        enqueueTitleWrite { [self] in await linkCalendar(id: id, calendarID: nil) }
    }

    func addToCalendar(id: UUID, calendarID: String) {
        pendingCalendarRequests[id] = calendarID
        enqueueTitleWrite { [self] in await linkCalendar(id: id, calendarID: calendarID) }
    }

    private func linkCalendar(id: UUID, calendarID: String?) async {
        guard let calendar else {
            serviceMessage = AppLocalization.string("Task saved. Calendar is unavailable. Try again from task details.")
            return
        }
        do {
            try await calendar.add(taskID: id, calendarID: calendarID)
            pendingCalendarRequests.removeValue(forKey: id)
            pendingDefaultCalendarRequests.remove(id)
            serviceMessage = nil
            onLocalWrite()
        } catch {
            serviceMessage = AppLocalization.string("Task saved. \(error.localizedDescription) Retry will check for an existing event first.")
        }
        await refresh()
    }

    func editReminderDate(id: UUID, date: Date?) {
        enqueueTitleWrite { [self] in
            if let date {
                guard date > .now else {
                    serviceMessage = AppLocalization.string("Choose a future time for the reminder.")
                    return
                }
                guard let reminders, await reminders.authorize() else { return }
            }
            serviceMessage = nil
            _ = await write(failure: .update) { try await store.setReminderDate(id: id, date: date) }
        }
    }

    private func scheduleReminders(requestPermission: Bool) async {
        if requestPermission, let reminders { _ = await reminders.authorize() }
        await reconcileReminders()
    }

    func retryReminders() async {
        guard let reminders else { return }
        _ = await reminders.authorize()
        await reconcileReminders()
    }

    func reconcileReminders() async {
        guard let reminders else { return }
        do { await reminders.reconcile(tasks: try await store.allTasks()) }
        catch { serviceMessage = AppLocalization.string("Couldn't load tasks to check reminders. Try again.") }
    }

    func editDueDate(id: UUID, date: Date?) {
        let day = date.map { Calendar.current.startOfDay(for: $0) }
        enqueueTitleWrite { [self] in
            if await write(failure: .update, operation: { try await store.setDueDate(id: id, date: day) }) {
                await updateCalendarDeadline(id: id)
            }
        }
    }

    func editIcon(id: UUID, icon: TaskIcon?) {
        enqueueTitleWrite { [self] in
            _ = await write(failure: .update) { try await store.setIcon(id: id, icon: icon) }
        }
    }

    func editDueTime(id: UUID, date: Date?) {
        enqueueTitleWrite { [self] in
            guard let day = task(id: id)?.dueDate else { return }
            let time = date.flatMap { value in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: value)
                return Calendar.current.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day)
            }
            if await write(failure: .update, operation: { try await store.setDueTime(id: id, date: time) }) {
                await updateCalendarDeadline(id: id)
            }
        }
    }

    private func updateCalendarDeadline(id: UUID) async {
        guard let calendar, task(id: id)?.calendarEventID?.isEmpty == false else { return }
        guard task(id: id)?.dueDate != nil else {
            pendingCalendarUpdates.remove(id)
            serviceMessage = AppLocalization.string("Deadline removed. The linked Calendar event has been kept.")
            return
        }
        do {
            try await calendar.updateDeadline(taskID: id)
            pendingCalendarUpdates.remove(id)
            serviceMessage = nil
        } catch {
            pendingCalendarUpdates.insert(id)
            serviceMessage = AppLocalization.string("Deadline saved. \(error.localizedDescription) Retry will update the linked event.")
        }
    }

    func retryTextEdits() {
        for (id, title) in titleDrafts { editTitle(id: id, title: title) }
        for (id, notes) in notesDrafts { editNotes(id: id, notes: notes) }
    }

    func notes(id: UUID) -> String {
        notesDrafts[id] ?? task(id: id)?.notes ?? ""
    }

    func editNotes(id: UUID, notes: String) {
        notesDrafts[id] = notes
        enqueueTitleWrite { [self] in
            guard notesDrafts[id] == notes else { return }
            let saved = await write(failure: .update) { try await store.setNotes(id: id, notes: notes) }
            if saved, notesDrafts[id] == notes { notesDrafts.removeValue(forKey: id) }
        }
    }

    func title(id: UUID) -> String {
        titleDrafts[id] ?? task(id: id)?.title ?? ""
    }

    func hasUnsavedTitle(id: UUID) -> Bool {
        guard let draft = titleDrafts[id] else { return false }
        return draft.trimmingCharacters(in: .whitespacesAndNewlines) != task(id: id)?.title
    }

    func editTitle(id: UUID, title: String) {
        titleDrafts[id] = title
        enqueueTitleWrite { [self] in
            guard titleDrafts[id] == title else { return }
            await rename(id: id, title: title)
        }
    }

    func finishTitleEditing(id: UUID) {
        enqueueTitleWrite { [self] in
            guard let draft = titleDrafts[id],
                  draft.trimmingCharacters(in: .whitespacesAndNewlines) == task(id: id)?.title else { return }
            titleDrafts.removeValue(forKey: id)
        }
    }

    func flushTitleEdits() async {
        while let task = titleWriteTask {
            let version = titleWriteVersion
            await task.value
            if version == titleWriteVersion { return }
        }
    }

    private func enqueueTitleWrite(_ operation: @escaping @MainActor () async -> Void) {
        let previous = titleWriteTask
        titleWriteVersion += 1
        titleWriteTask = Task {
            await previous?.value
            await operation()
        }
    }

    @discardableResult
    func delete(id: UUID) async -> Bool {
        await flushTitleEdits()
        let removedAttachments = task(id: id)?.document?.attachments ?? []
        let deleted = await write(failure: .delete) { try await store.delete(id: id) }
        if deleted {
            let referenced = Set(tasks.flatMap { $0.document?.attachments ?? [] }.map(\.id))
            await mediaStore.finish(sessionID: UUID(), removed: removedAttachments, keeping: referenced)
            if completionUndo?.id == id { completionUndo = nil }
            pendingDefaultCalendarRequests.remove(id)
            pendingCalendarRequests.removeValue(forKey: id)
            pendingCalendarUpdates.remove(id)
            titleDrafts.removeValue(forKey: id)
            notesDrafts.removeValue(forKey: id)
        }
        return deleted
    }

    func prepareEditorStorage() async {
        guard !editorStoragePrepared else { return }
        editorStoragePrepared = true
        do {
            let saved = try await store.allTasks()
            let referenced = Set(saved.flatMap { $0.document?.attachments ?? [] }.map(\.id))
            try await mediaStore.recover(referenced: referenced)
        } catch {
            serviceMessage = AppLocalization.string("Não foi possível limpar arquivos temporários. Seus dados foram mantidos.")
        }
    }

    func refresh() async {
        refreshVersion += 1
        let version = refreshVersion
        do {
            let loaded = try await store.allTasks()
            guard version == refreshVersion else { return }
            tasks = loaded
            hasLoadedTasks = true
            if failure == .load { failure = nil }
        } catch {
            guard version == refreshVersion else { return }
            failure = .load
            logger.error("Task load failed: \(String(describing: error), privacy: .private)")
        }
    }

    func dismissFailure() {
        failure = nil
    }

    private func write(failure: Failure, afterSave: () async -> Void = {}, operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
        } catch {
            self.failure = failure
            logger.error("Task write failed: \(String(describing: error), privacy: .private)")
            return false
        }
        if self.failure == failure { self.failure = nil }
        await afterSave()
        onLocalWrite()
        await refresh()
        await reconcileReminders()
        return true
    }
}
