import Foundation

enum CalendarPeriod: String, CaseIterable, Identifiable {
    case day = "Dia"
    case week = "Semana"
    case month = "Mês"

    var id: Self { self }
    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

struct CalendarPlan {
    let tasks: [TaskSnapshot]
    let day: Date
    let period: CalendarPeriod
    let calendar: Calendar

    var days: [UpcomingDay] {
        guard let interval = calendar.dateInterval(of: period.component, for: day) else { return [] }
        let matching = tasks.filter {
            guard !$0.isDone, let date = $0.dueDate else { return false }
            return date >= interval.start && date < interval.end
        }
        let grouped = Dictionary(grouping: matching) { calendar.startOfDay(for: $0.dueDate ?? day) }
        let dates: [Date]
        switch period {
        case .day: dates = [calendar.startOfDay(for: day)]
        case .week:
            dates = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
        case .month: dates = grouped.keys.sorted()
        }
        return dates.map { date in
            UpcomingDay(date: date, tasks: TaskQuery(collection: .upcoming, selectedDay: date)
                .results(in: grouped[date] ?? [], now: day, calendar: calendar))
        }
    }
}

struct CalendarDaySchedule {
    let scheduledDuration: TimeInterval
    let overlappingTaskIDs: Set<UUID>

    init(tasks: [TaskSnapshot], day: Date, calendar: Calendar) {
        let dayEnd = calendar.dateInterval(of: .day, for: day)?.end ?? day
        let intervals = tasks.compactMap { task -> (id: UUID, start: Date, end: Date)? in
            guard !task.isDone, let date = task.dueDate, calendar.isDate(date, inSameDayAs: day),
                  let time = task.dueTime, let end = task.dueEndTime, end > time else { return nil }
            let start = TaskSchedule.normalizedStart(day: day, time: time, calendar: calendar)
            let normalizedEnd = min(dayEnd, start.addingTimeInterval(end.timeIntervalSince(time)))
            guard normalizedEnd > start else { return nil }
            return (task.id, start, normalizedEnd)
        }.sorted { $0.start < $1.start }
        var active: [(id: UUID, start: Date, end: Date)] = []
        var overlapping: Set<UUID> = []
        var duration: TimeInterval = 0
        var coveredUntil = calendar.startOfDay(for: day)
        for interval in intervals {
            active.removeAll { $0.end <= interval.start }
            for other in active {
                overlapping.insert(other.id)
                overlapping.insert(interval.id)
            }
            active.append(interval)
            duration += max(0, interval.end.timeIntervalSince(max(coveredUntil, interval.start)))
            coveredUntil = max(coveredUntil, interval.end)
        }
        scheduledDuration = duration
        overlappingTaskIDs = overlapping
    }
}
