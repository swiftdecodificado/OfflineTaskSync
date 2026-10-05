import EventKit
import Foundation

struct TaskCalendarChoice: Identifiable, Equatable {
    let id: String
    let title: String
}

enum TaskCalendarError: LocalizedError {
    case denied, noCalendar, missingTask, missingDate, missingEvent

    var errorDescription: String? {
        switch self {
        case .denied: AppLocalization.string("Calendar access is unavailable. Allow full calendar access for this app in Settings.")
        case .noCalendar: AppLocalization.string("No writable calendar is available. Choose another calendar or check Settings.")
        case .missingTask: AppLocalization.string("This task is no longer available.")
        case .missingDate: AppLocalization.string("Set a deadline before adding this task to Calendar.")
        case .missingEvent: AppLocalization.string("The linked event couldn't be found. It may have moved or its calendar may be unavailable. Existing events have been kept.")
        }
    }
}

@MainActor
protocol TaskCalendarClient: AnyObject {
    func authorize() async throws
    func calendars() throws -> [TaskCalendarChoice]
    func defaultCalendarID() throws -> String
    func existingEvent(for task: TaskSnapshot) throws -> String?
    func createEvent(for task: TaskSnapshot, calendarID: String) throws -> String
    func updateEvent(for task: TaskSnapshot) throws
}

@MainActor
final class AppleTaskCalendarClient: TaskCalendarClient {
    private let store = EKEventStore()

    func authorize() async throws {
        if EKEventStore.authorizationStatus(for: .event) == .notDetermined {
            guard try await store.requestFullAccessToEvents() else { throw TaskCalendarError.denied }
        }
        try checkAccess()
    }

    private func checkAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { throw TaskCalendarError.denied }
    }

    func calendars() throws -> [TaskCalendarChoice] {
        try checkAccess()
        return store.calendars(for: .event).filter(\.allowsContentModifications)
            .map { TaskCalendarChoice(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    func defaultCalendarID() throws -> String {
        try checkAccess()
        guard let calendar = store.defaultCalendarForNewEvents, calendar.allowsContentModifications else {
            throw TaskCalendarError.noCalendar
        }
        return calendar.calendarIdentifier
    }

    func existingEvent(for task: TaskSnapshot) throws -> String? {
        try checkAccess()
        if let id = task.calendarEventID, !id.isEmpty, let event = store.event(withIdentifier: id) {
            return event.eventIdentifier
        }
        for date in [task.calendarLinkDate, task.dueDate].compactMap({ $0 }) {
            let start = Calendar.current.startOfDay(for: date)
            guard let end = Calendar.current.date(byAdding: .day, value: 1, to: start) else { continue }
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            if let event = store.events(matching: predicate).first(where: { $0.url == Self.marker(task.id) }) {
                return event.eventIdentifier
            }
        }
        return nil
    }

    func createEvent(for task: TaskSnapshot, calendarID: String) throws -> String {
        try checkAccess()
        guard let date = task.dueDate else { throw TaskCalendarError.missingDate }
        guard let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications else {
            throw TaskCalendarError.noCalendar
        }
        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = task.title
        event.notes = task.notes
        setDates(of: event, day: date, time: task.dueTime, end: task.dueEndTime)
        event.url = Self.marker(task.id)
        try store.save(event, span: .thisEvent)
        guard let id = event.eventIdentifier else { throw TaskCalendarError.missingEvent }
        return id
    }

    func updateEvent(for task: TaskSnapshot) throws {
        try checkAccess()
        guard let date = task.dueDate else { throw TaskCalendarError.missingDate }
        guard let id = try existingEvent(for: task), let event = store.event(withIdentifier: id) else {
            throw TaskCalendarError.missingEvent
        }
        setDates(of: event, day: date, time: task.dueTime, end: task.dueEndTime)
        try store.save(event, span: .thisEvent)
    }

    private func setDates(of event: EKEvent, day: Date, time: Date?, end: Date?) {
        event.isAllDay = time == nil
        event.startDate = time ?? Calendar.current.startOfDay(for: day)
        event.endDate = time.map { end ?? $0.addingTimeInterval(3600) }
            ?? Calendar.current.date(byAdding: .day, value: 1, to: event.startDate)
    }

    private static func marker(_ id: UUID) -> URL {
        URL(string: "offlinetasksync://task/\(id.uuidString)")!
    }
}

@MainActor
final class TaskCalendar {
    private let client: any TaskCalendarClient
    private let repository: any TaskRepository
    private var linking: Set<UUID> = []

    init(client: any TaskCalendarClient, repository: any TaskRepository) {
        self.client = client
        self.repository = repository
    }

    func choices() async throws -> [TaskCalendarChoice] {
        try await client.authorize()
        let calendars = try client.calendars()
        guard !calendars.isEmpty else { throw TaskCalendarError.noCalendar }
        return calendars
    }

    func updateDeadline(taskID: UUID) async throws {
        guard let task = try await repository.snapshot(id: taskID) else { throw TaskCalendarError.missingTask }
        guard task.calendarEventID?.isEmpty == false else { return }
        try client.updateEvent(for: task)
    }

    func add(taskID: UUID, calendarID: String? = nil) async throws {
        guard linking.insert(taskID).inserted else { return }
        defer { linking.remove(taskID) }
        try await client.authorize()
        guard var task = try await repository.snapshot(id: taskID) else { throw TaskCalendarError.missingTask }
        if let id = try client.existingEvent(for: task) {
            try await repository.linkCalendar(id: taskID, eventID: id, date: task.calendarLinkDate ?? task.dueDate ?? .now)
            return
        }
        if let id = task.calendarEventID, !id.isEmpty { throw TaskCalendarError.missingEvent }
        guard let date = task.dueDate else { throw TaskCalendarError.missingDate }
        let destination = try calendarID ?? client.defaultCalendarID()
        // Save the search date before EventKit so a failed reference save can be retried safely.
        try await repository.linkCalendar(id: taskID, eventID: "", date: date)
        task.calendarLinkDate = date
        let id = try client.createEvent(for: task, calendarID: destination)
        try await repository.linkCalendar(id: taskID, eventID: id, date: date)
    }
}
