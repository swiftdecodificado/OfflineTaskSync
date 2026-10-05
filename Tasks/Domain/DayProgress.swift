import Foundation

struct DayProgress: Equatable {
    let completedCount: Int
    let totalCount: Int

    init(tasks: [TaskSnapshot], date: Date, calendar: Calendar = .current) {
        let tasks = tasks.filter { task in
            task.dueDate.map { calendar.isDate($0, inSameDayAs: date) } == true
        }
        completedCount = tasks.filter(\.isDone).count
        totalCount = tasks.count
    }

    var fraction: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    var pendingCount: Int { totalCount - completedCount }
}
