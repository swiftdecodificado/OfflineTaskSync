import Foundation

enum UpcomingGroup: String, CaseIterable, Identifiable {
    case tomorrow = "Tomorrow"
    case nextDays = "Next days"
    case later = "Later dates"

    var id: Self { self }
}

struct UpcomingPlan {
    let tasks: [TaskSnapshot]
    let now: Date
    let calendar: Calendar

    func tasks(in group: UpcomingGroup) -> [TaskSnapshot] {
        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
              let nextDay = calendar.date(byAdding: .day, value: 2, to: today),
              let later = calendar.date(byAdding: .day, value: 7, to: today) else { return [] }
        return TaskQuery(collection: .upcoming).results(in: tasks, now: now, calendar: calendar).filter { task in
            guard let date = task.dueDate else { return false }
            switch group {
            case .tomorrow: return date >= tomorrow && date < nextDay
            case .nextDays: return date >= nextDay && date < later
            case .later: return date >= later
            }
        }
    }
}

struct UpcomingDay: Identifiable {
    let date: Date
    let tasks: [TaskSnapshot]
    var id: Date { date }
}

extension UpcomingPlan {
    var days: [UpcomingDay] {
        let future = TaskQuery(collection: .upcoming).results(in: tasks, now: now, calendar: calendar)
        let grouped = Dictionary(grouping: future) { calendar.startOfDay(for: $0.dueDate ?? now) }
        return grouped.keys.sorted().map { UpcomingDay(date: $0, tasks: grouped[$0] ?? []) }
    }
}
