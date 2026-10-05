import Foundation

struct AgendaTimelineEntry: Identifiable {
    enum ID: Hashable {
        case time(Date), task(UUID)
    }
    enum Content {
        case time(Date), task(TaskSnapshot)
    }
    let content: Content
    var id: ID {
        switch content {
        case .time(let date): .time(date)
        case .task(let task): .task(task.id)
        }
    }
}

struct AgendaTimelinePlan {
    let grid: AgendaTimeGrid
    let entries: [AgendaTimelineEntry]
    let placements: [TaskTimelinePlacement]

    init(tasks: [TaskSnapshot], day: Date, calendar: Calendar, now: Date? = nil) {
        grid = AgendaTimeGrid(day: day, calendar: calendar, now: now)
        let pending = TaskQuery(collection: .upcoming, selectedDay: day)
            .results(in: tasks, now: day, calendar: calendar)
        let timed: [(task: TaskSnapshot, time: Date)] = pending.compactMap { task in
            guard let time = task.dueTime else { return nil }
            let parts = calendar.dateComponents([.hour, .minute, .second], from: time)
            let normalized = calendar.isDate(time, inSameDayAs: day) ? time
                : calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0,
                                second: parts.second ?? 0, of: day) ?? time
            return (task, normalized)
        }
        placements = Self.place(timed, dayEnd: grid.interval.end, visibleStart: grid.interval.start)
        var result: [AgendaTimelineEntry] = []
        for start in grid.starts {
            let end = calendar.date(byAdding: .minute, value: 15, to: start) ?? start
            result.append(AgendaTimelineEntry(content: .time(start)))
            for item in placements where item.start >= start && item.start < end {
                result.append(AgendaTimelineEntry(content: .task(item.task)))
            }
        }
        entries = result
    }
}

struct TaskTimelinePlacement: Identifiable {
    let task: TaskSnapshot
    let start: Date
    let end: Date
    var column: Int
    var columns: Int
    var id: UUID { task.id }
}

extension AgendaTimelinePlan {
    static func place(_ timed: [(task: TaskSnapshot, time: Date)], dayEnd: Date, visibleStart: Date? = nil) -> [TaskTimelinePlacement] {
        var result: [TaskTimelinePlacement] = []
        var group: [TaskTimelinePlacement] = []
        var columnEnds: [Date] = []
        var groupEnd = Date.distantPast
        for item in timed.sorted(by: { $0.time == $1.time ? $0.task.id.uuidString < $1.task.id.uuidString : $0.time < $1.time }) {
            let end = min(dayEnd, max(item.time.addingTimeInterval(900), item.task.dueEndTime ?? item.time.addingTimeInterval(900)))
            let start = max(item.time, visibleStart ?? item.time)
            guard end > start else { continue }
            if start >= groupEnd {
                result += group.map { value in var value = value; value.columns = columnEnds.count; return value }
                group = []
                columnEnds = []
            }
            let column = columnEnds.firstIndex(where: { $0 <= start }) ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(end) } else { columnEnds[column] = end }
            group.append(TaskTimelinePlacement(task: item.task, start: start, end: end, column: column, columns: 1))
            groupEnd = max(groupEnd, end)
        }
        result += group.map { value in var value = value; value.columns = columnEnds.count; return value }
        return result
    }
}
