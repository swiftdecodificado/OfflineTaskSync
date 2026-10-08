import Foundation

struct TaskDraft: Identifiable, Equatable {
    var id = UUID()
    var title = ""
    var isDone = false
    var notes = ""
    var document: TaskDocument?
    var color: TaskColor = .defaultColor
    var icon: TaskIcon?
    var dueDate: Date? = Calendar.current.startOfDay(for: .now)
    var dueEndTime: Date?
    var dueTime: Date? = Calendar.current.dateInterval(of: .minute, for: .now)?.start
    var reminderDate: Date?
    var addToCalendar = false
    var calendarID: String?
}
