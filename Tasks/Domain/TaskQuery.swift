import Foundation

enum TaskCollection: String, CaseIterable, Identifiable {
    case today = "Today"
    case upcoming = "Upcoming"
    case all = "All"
    case completed = "Completed"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .upcoming: "calendar"
        case .all: "tray.full"
        case .completed: "checkmark.circle"
        }
    }
}

enum TaskFilter: String, CaseIterable, Identifiable {
    case any = "Any deadline"
    case dated = "With deadline"
    case undated = "Without deadline"
    var id: Self { self }
}

struct TaskQuery {
    var collection: TaskCollection = .all
    var filter: TaskFilter = .any
    var category: TaskCategoryFilter = .all
    var search = ""
    var selectedDay: Date?
    var includeCompleted = false
    var dateScope: TaskDateScope = .any

    func results(in tasks: [TaskSnapshot], now: Date = .now, calendar: Calendar = .current) -> [TaskSnapshot] {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.filter { task in
            guard category.includes(task), dateScope.includes(task, now: now, calendar: calendar) else { return false }
            switch collection {
            case .today:
                guard (!task.isDone || includeCompleted), let date = task.dueDate else { return false }
                if let selectedDay {
                    guard calendar.isDate(date, inSameDayAs: selectedDay) else { return false }
                } else {
                    guard calendar.isDate(date, inSameDayAs: now) else { return false }
                }
            case .upcoming:
                guard !task.isDone, let date = task.dueDate else { return false }
                if let selectedDay {
                    guard calendar.isDate(date, inSameDayAs: selectedDay) else { return false }
                } else {
                    guard date >= tomorrow else { return false }
                }
            case .all:
                guard !task.isDone else { return false }
            case .completed:
                guard task.isDone else { return false }
            }
            if filter == .dated && task.dueDate == nil { return false }
            if filter == .undated && task.dueDate != nil { return false }
            return text.isEmpty || task.title.localizedStandardContains(text) || task.notes.localizedStandardContains(text)
        }.sorted {
            if collection == .upcoming || collection == .today {
                let firstDay = calendar.startOfDay(for: $0.dueDate ?? .distantFuture)
                let secondDay = calendar.startOfDay(for: $1.dueDate ?? .distantFuture)
                if firstDay != secondDay { return firstDay < secondDay }
                let firstTime = Self.timeOfDay($0.dueTime, calendar: calendar)
                let secondTime = Self.timeOfDay($1.dueTime, calendar: calendar)
                if firstTime != secondTime { return firstTime < secondTime }
                return $0.id.uuidString < $1.id.uuidString
            }
            if $0.dueDate != $1.dueDate { return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
            if includeCompleted {
                if $0.dueTime != $1.dueTime { return ($0.dueTime ?? .distantFuture) < ($1.dueTime ?? .distantFuture) }
                return $0.id.uuidString < $1.id.uuidString
            }
            if $0.updatedAt != $1.updatedAt { return $0.updatedAt > $1.updatedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func overdueResults(in tasks: [TaskSnapshot], now: Date, calendar: Calendar) -> [TaskSnapshot] {
        tasks.filter { $0.isOverdue(now: now, calendar: calendar) }.sorted {
            if $0.dueDate != $1.dueDate { return ($0.dueDate ?? .distantPast) < ($1.dueDate ?? .distantPast) }
            let firstTime = timeOfDay($0.dueTime, calendar: calendar)
            let secondTime = timeOfDay($1.dueTime, calendar: calendar)
            if firstTime != secondTime { return firstTime < secondTime }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    private static func timeOfDay(_ date: Date?, calendar: Calendar) -> Int {
        guard let date else { return -1 }
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
    }
}

extension TaskSnapshot {
    func isOverdue(now: Date = .now, calendar: Calendar = .current) -> Bool {
        !isDone && dueDate.map { $0 < calendar.startOfDay(for: now) } == true
    }
}
