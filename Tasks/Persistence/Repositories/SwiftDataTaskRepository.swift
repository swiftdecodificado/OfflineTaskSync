import SwiftData
import Foundation

@MainActor
final class SwiftDataTaskRepository: TaskRepository {
    private var context: ModelContext?
    private var writeContext: ModelContext {
        guard let context else { preconditionFailure("Task store is disconnected") }
        return context
    }

    func disconnect() {
        context = nil
    }
    private let mediaStore: TaskMediaStore
    private let beforeSave: () throws -> Void
    private let afterSave: () -> Void
    private let beforeFetch: () throws -> Void

    init(
        store: PersistenceContainer,
        mediaStore: TaskMediaStore = .shared,
        beforeSave: @escaping () throws -> Void = {},
        afterSave: @escaping () -> Void = {},
        beforeFetch: @escaping () throws -> Void = {}
    ) {
        self.mediaStore = mediaStore
        let context = ModelContext(store.container)
        context.autosaveEnabled = false
        self.context = context
        self.beforeSave = beforeSave
        self.afterSave = afterSave
        self.beforeFetch = beforeFetch
        store.register(self)
    }

    var hasChanges: Bool { writeContext.hasChanges }

    func createTask(id: UUID = UUID(), title: String) async throws {
        let now = Calendar.current.dateInterval(of: .minute, for: .now)?.start ?? .now
        try await createTask(id: id, title: title, notes: "", dueDate: Calendar.current.startOfDay(for: now),
                             dueTime: now, reminderDate: nil, icon: nil, color: .defaultColor)
    }

    func createTask(id: UUID, title: String, notes: String, dueDate: Date?, dueTime: Date?, reminderDate: Date?, icon: TaskIcon?, color: TaskColor = .defaultColor) async throws {
        try TaskSchedule.requireStart(day: dueDate, time: dueTime)
        guard try fetchRecord(id: id) == nil else { return }
        let record = StoredTask(id: id, title: title, isDone: false, updatedAt: Date(), pendingSync: true)
        record.colorID = color.rawValue
        record.iconName = icon?.rawValue
        record.notes = notes
        record.dueDate = dueDate
        record.dueTime = dueDate.flatMap { day in dueTime.map { TaskSchedule.normalizedStart(day: day, time: $0) } }
        record.reminderDate = reminderDate
        writeContext.insert(record)
        try saveChanges()
    }

    func saveDraft(_ draft: TaskDraft, creating: Bool) async throws {
        var draft = draft
        if let day = draft.dueDate, let time = draft.dueTime {
            draft.dueTime = TaskSchedule.normalizedStart(day: day, time: time)
        }
        try TaskSchedule.validate(draft)
        let existing = try fetchRecord(id: draft.id)
        if creating, existing != nil { throw CocoaError(.fileWriteFileExists) }
        if !creating, existing == nil { throw TaskCalendarError.missingTask }
        let record = existing ?? StoredTask(id: draft.id, title: draft.title, isDone: false,
                                           updatedAt: .now, pendingSync: true)
        let encoded = try draft.document.map { try JSONEncoder().encode($0) }
        record.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        record.isDone = draft.isDone
        record.notes = draft.document?.plainText ?? draft.notes
        record.documentData = encoded
        record.colorID = draft.color.rawValue
        record.iconName = draft.icon?.rawValue
        record.dueDate = draft.dueDate.map { Calendar.current.startOfDay(for: $0) }
        record.dueTime = draft.dueDate == nil ? nil : draft.dueTime
        record.dueEndTime = draft.dueEndTime
        record.reminderDate = draft.reminderDate
        record.updatedAt = .now
        record.pendingSync = true
        if existing == nil { writeContext.insert(record) }
        try saveChanges()
    }

    func toggleDone(id: UUID) async throws {
        guard let record = try fetchRecord(id: id) else { return }
        record.isDone.toggle()
        record.updatedAt = Date()
        record.pendingSync = true
        try saveChanges()
    }

    func rename(id: UUID, title: String) async throws {
        guard let record = try fetchRecord(id: id) else { return }
        record.title = title
        record.updatedAt = Date()
        record.pendingSync = true
        try saveChanges()
    }

    func setNotes(id: UUID, notes: String) async throws {
        try update(id: id) { $0.notes = notes }
    }

    func setDueDate(id: UUID, date: Date?) async throws {
        guard let date else { throw TaskScheduleError.missingStart }
        try update(id: id) { record in
            if let time = record.dueTime {
                let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                let start = Calendar.current.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: date)
                record.dueEndTime = TaskSchedule.shiftedEnd(from: record.dueTime, end: record.dueEndTime, to: start)
                record.dueTime = start
            }
            record.dueDate = date
        }
    }

    func setIcon(id: UUID, icon: TaskIcon?) async throws {
        try update(id: id) { $0.iconName = icon?.rawValue }
    }

    func setDueTime(id: UUID, date: Date?) async throws {
        guard let record = try fetchRecord(id: id) else { return }
        try TaskSchedule.requireStart(day: record.dueDate, time: date)
        try update(id: id) { record in
            let start = record.dueDate == nil ? nil : date
            record.dueEndTime = TaskSchedule.shiftedEnd(from: record.dueTime, end: record.dueEndTime, to: start)
            record.dueTime = start
        }
    }

    func setReminderDate(id: UUID, date: Date?) async throws {
        try update(id: id) { $0.reminderDate = date }
    }

    func linkCalendar(id: UUID, eventID: String, date: Date) async throws {
        try update(id: id) {
            $0.calendarEventID = eventID
            $0.calendarLinkDate = date
        }
    }

    private func update(id: UUID, mutation: (StoredTask) -> Void) throws {
        guard let record = try fetchRecord(id: id) else { return }
        mutation(record)
        record.updatedAt = Date()
        record.pendingSync = true
        try saveChanges()
    }

    func delete(id: UUID) async throws {
        if let record = try fetchRecord(id: id) {
            writeContext.delete(record)
        }
        writeContext.insert(StoredDeletion(id: id, requestedAt: Date()))
        try saveChanges()
    }

    func applyRemoteSnapshot(_ snapshot: RemoteTaskSnapshot) async throws {
        try snapshot.validate()
        guard try canApply(snapshot) else { return }
        let sessionID = UUID()
        let attachments = snapshot.details?.document?.attachments ?? []
        try await mediaStore.stageForSync(snapshot, sessionID: sessionID)
        let copied: [UUID]
        do {
            copied = try await mediaStore.prepare(attachments, sessionID: sessionID)
        } catch {
            await mediaStore.discard(sessionID: sessionID)
            throw error
        }
        do {
            try Task.checkCancellation()
            // Recheck for local edits after writing media.
            guard try canApply(snapshot) else {
                await mediaStore.rollback(copied)
                await mediaStore.discard(sessionID: sessionID)
                return
            }
            let existing = try fetchRecord(id: snapshot.id)
            let record = existing ?? StoredTask(id: snapshot.id, title: snapshot.title, isDone: snapshot.isDone,
                                               updatedAt: snapshot.updatedAt, pendingSync: false)
            let encoded = try snapshot.details?.document.map { try JSONEncoder().encode($0) }
            record.title = snapshot.title
            record.isDone = snapshot.isDone
            record.updatedAt = snapshot.updatedAt
            if let details = snapshot.details {
                record.notes = details.notes
                record.documentData = encoded
                record.dueDate = details.dueDate
                record.dueTime = details.dueTime
                record.dueEndTime = details.dueEndTime
                record.reminderDate = details.reminderDate
                record.iconName = details.iconName
                record.colorID = details.colorID
            }
            if existing == nil { writeContext.insert(record) }
            try saveChanges()
        } catch {
            await mediaStore.rollback(copied)
            await mediaStore.discard(sessionID: sessionID)
            throw error
        }
        await mediaStore.discard(sessionID: sessionID)
    }

    private func canApply(_ snapshot: RemoteTaskSnapshot) throws -> Bool {
        guard try fetchPendingDeletion(id: snapshot.id) == nil else { return false }
        guard let record = try fetchRecord(id: snapshot.id) else { return true }
        return !record.pendingSync && snapshot.updatedAt >= record.updatedAt
    }

    func markSynced(_ sentSnapshot: TaskSnapshot) async throws {
        guard let record = try fetchRecord(id: sentSnapshot.id), try Self.snapshot(of: record) == sentSnapshot else { return }
        record.pendingSync = false
        try saveChanges()
    }

    func confirmDeletion(id: UUID) async throws {
        guard let marker = try fetchPendingDeletion(id: id) else { return }
        writeContext.delete(marker)
        try saveChanges()
    }

    func pendingRecords() async throws -> [TaskSnapshot] {
        try beforeFetch()
        let request = FetchDescriptor<StoredTask>(predicate: #Predicate { $0.pendingSync })
        return try writeContext.fetch(request).map { try Self.snapshot(of: $0) }
    }

    func pendingDeletionIDs() async throws -> [UUID] {
        try beforeFetch()
        return try writeContext.fetch(FetchDescriptor<StoredDeletion>()).map(\.id)
    }

    func snapshot(id: UUID) async throws -> TaskSnapshot? {
        try fetchRecord(id: id).map { try Self.snapshot(of: $0) }
    }

    func allTasks() async throws -> [TaskSnapshot] {
        try beforeFetch()
        let request = FetchDescriptor<StoredTask>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        return try writeContext.fetch(request).map { try Self.snapshot(of: $0) }
    }

    private func saveChanges() throws {
        do {
            try beforeSave()
            try writeContext.save()
            afterSave()
        } catch {
            writeContext.rollback()
            throw error
        }
    }

    private func fetchRecord(id: UUID) throws -> StoredTask? {
        try beforeFetch()
        var request = FetchDescriptor<StoredTask>(predicate: #Predicate { $0.id == id })
        request.fetchLimit = 1
        return try writeContext.fetch(request).first
    }

    private func fetchPendingDeletion(id: UUID) throws -> StoredDeletion? {
        try beforeFetch()
        var request = FetchDescriptor<StoredDeletion>(predicate: #Predicate { $0.id == id })
        request.fetchLimit = 1
        return try writeContext.fetch(request).first
    }

    private static func snapshot(of record: StoredTask) throws -> TaskSnapshot {
        let document = try record.documentData.map { try JSONDecoder().decode(TaskDocument.self, from: $0) }
        if let document, document.version != TaskDocument.currentVersion { throw CocoaError(.fileReadCorruptFile) }
        return TaskSnapshot(id: record.id, title: record.title, isDone: record.isDone,
                     updatedAt: record.updatedAt, pendingSync: record.pendingSync,
                     notes: record.notes, document: document, dueDate: record.dueDate, dueEndTime: record.dueEndTime, dueTime: record.dueTime, reminderDate: record.reminderDate,
                     calendarEventID: record.calendarEventID, calendarLinkDate: record.calendarLinkDate, iconName: record.iconName, colorID: record.colorID)
    }
}
