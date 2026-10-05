import Foundation

struct AgendaTimeGrid {
    let interval: DateInterval
    let starts: [Date]

    init(day: Date, calendar: Calendar, now: Date? = nil) {
        let dayStart = calendar.startOfDay(for: day)
        let start: Date
        if let now, calendar.isDate(day, inSameDayAs: now) {
            start = calendar.dateInterval(of: .hour, for: now)?.start ?? dayStart
        } else {
            start = dayStart
        }
        let end = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        interval = DateInterval(start: start, end: end)
        var dates: [Date] = []
        var cursor = start
        while cursor < end {
            dates.append(cursor)
            guard let next = calendar.date(byAdding: .minute, value: 15, to: cursor), next > cursor else { break }
            cursor = next
        }
        starts = dates
    }

    func ends(after start: Date) -> [Date] {
        starts.filter { $0 > start } + (start < interval.end ? [interval.end] : [])
    }
}

enum TaskScheduleError: LocalizedError {
    case invalidEnd
    var errorDescription: String? {
        AppLocalization.string("Choose an end time after the start, within the same day.")
    }
}

enum TaskSchedule {
    static func validate(_ draft: TaskDraft, calendar: Calendar = .current) throws {
        guard let end = draft.dueEndTime else { return }
        guard let day = draft.dueDate, let start = draft.dueTime,
              calendar.isDate(start, inSameDayAs: day), end > start,
              end <= AgendaTimeGrid(day: day, calendar: calendar).interval.end else {
            throw TaskScheduleError.invalidEnd
        }
    }

    static func shiftedEnd(from start: Date?, end: Date?, to newStart: Date?, calendar: Calendar = .current) -> Date? {
        guard let start, let end, let newStart, end > start else { return nil }
        return min(newStart.addingTimeInterval(end.timeIntervalSince(start)),
                   AgendaTimeGrid(day: newStart, calendar: calendar).interval.end)
    }
}
