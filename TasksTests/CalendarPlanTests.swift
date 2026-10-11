import Foundation
import Testing
@testable import Tasks

@Suite struct CalendarPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func date(_ day: Int, month: Int = 11, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func task(_ title: String, date: Date?, time: Date? = nil, done: Bool = false) -> TaskSnapshot {
        TaskSnapshot(id: UUID(), title: title, isDone: done, updatedAt: .now, pendingSync: false,
                     dueDate: date, dueTime: time)
    }

    @Test func dayIncludesUntimedTasksBeforeScheduledActivities() {
        var allDay = task("Exercise", date: date(1), time: date(1, hour: 8))
        allDay.iconName = TaskIcon.exercise.rawValue
        let morning = task("Morning", date: date(1), time: date(1, hour: 9))
        let evening = task("Evening", date: date(1), time: date(1, hour: 18))
        let plan = CalendarPlan(tasks: [evening, task("Undated", date: nil), task("Legacy without time", date: date(1)), morning, allDay,
                                        task("Done", date: date(1), done: true), task("Tomorrow", date: date(2))],
                                day: date(1), period: .day, calendar: calendar)
        #expect(plan.days.count == 1)
        #expect(plan.days.first?.tasks.map(\.title) == ["Legacy without time", "Exercise", "Morning", "Evening"])
    }

    @Test func weekUsesCalendarBoundariesAcrossMonthAndDST() {
        let plan = CalendarPlan(tasks: [task("Sunday", date: date(1), time: date(1, hour: 9)), task("Monday", date: date(26, month: 10), time: date(26, month: 10, hour: 9)),
                                       task("Next week", date: date(2), time: date(2, hour: 9)), task("Previous week", date: date(25, month: 10), time: date(25, month: 10, hour: 9))],
                                day: date(1), period: .week, calendar: calendar)
        #expect(plan.days.flatMap(\.tasks).map(\.title) == ["Monday", "Sunday"])
        #expect(plan.days.count == 7)
        #expect(plan.days[1].tasks.isEmpty)
    }

    @Test func monthIncludesPastAndFutureDaysAndExcludesNextMonth() {
        let plan = CalendarPlan(tasks: [task("Last", date: date(30), time: date(30, hour: 9)), task("First", date: date(1), time: date(1, hour: 9)),
                                       task("Next month", date: date(1, month: 12), time: date(1, month: 12, hour: 9))],
                                day: date(15), period: .month, calendar: calendar)
        #expect(plan.days.flatMap(\.tasks).map(\.title) == ["First", "Last"])
    }
    @Test func emptyDayStillHasAPlanningSection() {
        let plan = CalendarPlan(tasks: [], day: date(1), period: .day, calendar: calendar)
        #expect(plan.days.map(\.date) == [date(1)])
        #expect(plan.days.first?.tasks.isEmpty == true)
    }

    @Test func weekKeepsUntimedTasksAndExcludesCompletedAndUndatedTasks() {
        let plan = CalendarPlan(tasks: [task("No time", date: date(1)), task("No date", date: nil),
                                       task("Done", date: date(1), done: true)],
                                day: date(1), period: .week, calendar: calendar)
        #expect(plan.days.count == 7)
        #expect(plan.days.flatMap(\.tasks).map(\.title) == ["No time"])
    }

    @Test func scheduleCountsOverlappingTimeOnceAndIgnoresUnknownDurations() {
        var first = task("First", date: date(1), time: date(1, hour: 9))
        first.dueEndTime = date(1, hour: 11)
        var second = task("Second", date: date(1), time: date(1, hour: 10))
        second.dueEndTime = date(1, hour: 12)
        var adjacent = task("Adjacent", date: date(1), time: date(1, hour: 12))
        adjacent.dueEndTime = date(1, hour: 13)
        let unknown = task("Unknown duration", date: date(1), time: date(1, hour: 14))
        let schedule = CalendarDaySchedule(tasks: [second, adjacent, unknown, first], day: date(1), calendar: calendar)
        #expect(schedule.scheduledDuration == 4 * 60 * 60)
        #expect(schedule.overlappingTaskIDs == [first.id, second.id])
    }

    @Test func scheduleExcludesOtherDaysAndCompletedTasks() {
        var completed = task("Done", date: date(1), time: date(1, hour: 9), done: true)
        completed.dueEndTime = date(1, hour: 10)
        var tomorrow = task("Tomorrow", date: date(2), time: date(2, hour: 9))
        tomorrow.dueEndTime = date(2, hour: 10)
        let schedule = CalendarDaySchedule(tasks: [completed, tomorrow], day: date(1), calendar: calendar)
        #expect(schedule.scheduledDuration == 0)
        #expect(schedule.overlappingTaskIDs.isEmpty)
    }

}
