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
    private let beforeSave: () throws -> Void
    private let afterSave: () -> Void
    private let beforeFetch: () throws -> Void

    init(
        store: PersistenceContainer,
        beforeSave: @escaping () throws -> Void = {},
        afterSave: @escaping () -> Void = {},
        beforeFetch: @escaping () throws -> Void = {}
    ) {
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
        try await createTask(id: id, title: title, notes: "", dueDate: nil, dueTime: nil, reminderDate: nil, icon: nil, color: .defaultColor)
    }

    func createTask(id: UUID, title: String, notes: String, dueDate: Date?, dueTime: Date?, reminderDate: Date?, icon: TaskIcon?, color: TaskColor = .defaultColor) async throws {
        guard try fetchRecord(id: id) == nil else { return }
        let record = StoredTask(id: id, title: title, isDone: false, updatedAt: Date(), pendingSync: true)
        record.colorID = color.rawValue
        record.iconName = icon?.rawValue
        record.notes = notes
        record.dueDate = dueDate
        record.dueTime = dueDate == nil ? nil : dueTime
        record.reminderDate = reminderDate
        writeContext.insert(record)
        try saveChanges()
    }

    func saveDraft(_ draft: TaskDraft, creating: Bool) async throws {
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
        try update(id: id) { record in
            if let date, let time = record.dueTime {
                let components = Calendar.current.dateComponents([.hour, .minute], from: time)
                let start = Calendar.current.date(bySettingHour: components.hour ?? 0, minute: components.minute ?? 0, second: 0, of: date)
                record.dueEndTime = TaskSchedule.shiftedEnd(from: record.dueTime, end: record.dueEndTime, to: start)
                record.dueTime = start
            } else if date == nil {
                record.dueTime = nil
                record.dueEndTime = nil
            }
            record.dueDate = date
        }
    }

    func setIcon(id: UUID, icon: TaskIcon?) async throws {
        try update(id: id) { $0.iconName = icon?.rawValue }
    }

    func setDueTime(id: UUID, date: Date?) async throws {
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
        guard try fetchPendingDeletion(id: snapshot.id) == nil else { return }
        if let record = try fetchRecord(id: snapshot.id) {
            guard !record.pendingSync, snapshot.updatedAt >= record.updatedAt else { return }
            record.title = snapshot.title
            record.isDone = snapshot.isDone
            record.updatedAt = snapshot.updatedAt
        } else {
            writeContext.insert(StoredTask(id: snapshot.id, title: snapshot.title, isDone: snapshot.isDone,
                                          updatedAt: snapshot.updatedAt, pendingSync: false))
        }
        try saveChanges()
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
