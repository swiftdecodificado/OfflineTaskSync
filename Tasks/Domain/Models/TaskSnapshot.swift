import Foundation

struct TaskSnapshot: Sendable, Equatable, Identifiable, Codable {
    let id: UUID
    let title: String
    let isDone: Bool
    let updatedAt: Date
    let pendingSync: Bool
    var notes: String = ""
    var document: TaskDocument? = nil
    var dueDate: Date?
    var dueEndTime: Date?
    var dueTime: Date?
    var reminderDate: Date?
    var calendarEventID: String?
    var calendarLinkDate: Date?
    var iconName: String?
    var colorID: String?
}
