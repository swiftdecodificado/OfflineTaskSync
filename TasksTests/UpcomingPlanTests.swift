import Foundation
import Testing
@testable import Tasks

@Suite struct UpcomingPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    @Test func groupsCoverEachFutureTaskOnceAcrossDaylightSavingChange() {
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!
        func task(_ offset: Int, done: Bool = false) -> TaskSnapshot {
            TaskSnapshot(id: UUID(), title: "Day \(offset)", isDone: done, updatedAt: today, pendingSync: true,
                         dueDate: calendar.date(byAdding: .day, value: offset, to: today))
        }
        let tomorrow = task(1)
        let next = [task(2), task(6)]
        let later = [task(7), task(40)]
        let undated = TaskSnapshot(id: UUID(), title: "No date", isDone: false, updatedAt: today, pendingSync: true)
        let plan = UpcomingPlan(tasks: [task(-1), task(0), task(1, done: true), undated] + later + next + [tomorrow],
                                now: today, calendar: calendar)
        #expect(plan.tasks(in: .tomorrow).map(\.id) == [tomorrow.id])
        #expect(plan.tasks(in: .nextDays).map(\.id) == next.map(\.id))
        #expect(plan.tasks(in: .later).map(\.id) == later.map(\.id))
        let ids = UpcomingGroup.allCases.flatMap { plan.tasks(in: $0).map(\.id) }
        #expect(ids.count == 5)
        #expect(Set(ids).count == 5)
    }

    @Test func selectedDateShowsOnlyPendingTasksOnThatDay() {
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let tasks = [
            TaskSnapshot(id: UUID(), title: "Today", isDone: false, updatedAt: today, pendingSync: true, dueDate: today),
            TaskSnapshot(id: UUID(), title: "Tomorrow", isDone: false, updatedAt: today, pendingSync: true, dueDate: tomorrow),
            TaskSnapshot(id: UUID(), title: "Done", isDone: true, updatedAt: today, pendingSync: true, dueDate: tomorrow),
            TaskSnapshot(id: UUID(), title: "Undated", isDone: false, updatedAt: today, pendingSync: true)
        ]
        #expect(TaskQuery(collection: .upcoming, selectedDay: tomorrow)
            .results(in: tasks, now: today, calendar: calendar).map(\.title) == ["Tomorrow"])
        #expect(TaskQuery(collection: .upcoming, selectedDay: today)
            .results(in: tasks, now: today, calendar: calendar).map(\.title) == ["Today"])
    }

    @Test func orderingUsesDayThenTimeThenStableIdentity() {
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        func task(_ id: String, hour: Int?, updated: Date) -> TaskSnapshot {
            TaskSnapshot(id: UUID(uuidString: id)!, title: "Task", isDone: false, updatedAt: updated, pendingSync: true,
                         dueDate: tomorrow, dueTime: hour.flatMap { calendar.date(bySettingHour: $0, minute: 0, second: 0, of: tomorrow) })
        }
        let allDay = task("00000000-0000-0000-0000-000000000004", hour: nil, updated: today)
        let early = task("00000000-0000-0000-0000-000000000001", hour: 9, updated: today)
        let tie = task("00000000-0000-0000-0000-000000000002", hour: 9, updated: tomorrow)
        let late = task("00000000-0000-0000-0000-000000000003", hour: 18, updated: tomorrow)
        let expected = [allDay, early, tie, late].map(\.id)
        let query = TaskQuery(collection: .upcoming)
        #expect(query.results(in: [late, tie, allDay, early], now: today, calendar: calendar).map(\.id) == expected)
        #expect(query.results(in: [early, allDay, tie, late], now: today, calendar: calendar).map(\.id) == expected)
    }
}
