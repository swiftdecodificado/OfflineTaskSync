import Foundation

enum TaskDateScope: String, CaseIterable, Identifiable {
    case any = "Any date"
    case today = "Today"
    case overdue = "Overdue"

    var id: Self { self }

    func includes(_ task: TaskSnapshot, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .any:
            true
        case .today:
            task.dueDate.map { calendar.isDate($0, inSameDayAs: now) } == true
        case .overdue:
            task.isOverdue(now: now, calendar: calendar)
        }
    }
}
