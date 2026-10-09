import Foundation

enum TaskListSort: String, CaseIterable, Identifiable {
    case deadline = "Deadline"
    case title = "Title"
    case recentlyUpdated = "Recently updated"

    var id: Self { self }

    func ordered(_ tasks: [TaskSnapshot], calendar: Calendar) -> [TaskSnapshot] {
        tasks.sorted { first, second in
            switch self {
            case .deadline:
                break
            case .title:
                let comparison = first.title.localizedStandardCompare(second.title)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            case .recentlyUpdated:
                if first.updatedAt != second.updatedAt { return first.updatedAt > second.updatedAt }
            }
            let firstDay = first.dueDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
            let secondDay = second.dueDate.map { calendar.startOfDay(for: $0) } ?? .distantFuture
            if firstDay != secondDay { return firstDay < secondDay }
            let firstTime = timeOfDay(first.dueTime, calendar: calendar)
            let secondTime = timeOfDay(second.dueTime, calendar: calendar)
            if firstTime != secondTime { return firstTime < secondTime }
            return first.id.uuidString < second.id.uuidString
        }
    }

    private func timeOfDay(_ date: Date?, calendar: Calendar) -> Int {
        guard let date else { return -1 }
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
    }
}
