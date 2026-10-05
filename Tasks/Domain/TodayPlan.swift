import Foundation

struct TodayPlan {
    let today: [TaskSnapshot]
    let overdue: [TaskSnapshot]
    let next: [TaskSnapshot]

    init(tasks: [TaskSnapshot], now: Date, calendar: Calendar) {
        today = TaskQuery(collection: .today, selectedDay: now, includeCompleted: true)
            .results(in: tasks, now: now, calendar: calendar)
        overdue = TaskQuery.overdueResults(in: tasks, now: now, calendar: calendar)
        next = Array(TaskQuery(collection: .upcoming)
            .results(in: tasks, now: now, calendar: calendar).prefix(3))
    }
}
