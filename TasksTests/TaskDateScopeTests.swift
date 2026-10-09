import Foundation
import Testing
@testable import Tasks

@Suite struct TaskDateScopeTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))! }
    private func task(_ title: String, offset: Int? = 0, done: Bool = false, icon: TaskIcon? = nil) -> TaskSnapshot {
        TaskSnapshot(id: UUID(), title: title, isDone: done, updatedAt: day, pendingSync: false,
                     dueDate: offset.flatMap { calendar.date(byAdding: .day, value: $0, to: day) }, iconName: icon?.rawValue)
    }

    @Test func todayIncludesBothStatusesAndExcludesOtherDaysAndUndatedTasks() {
        let pending = task("Pending")
        let done = task("Done", done: true)
        let tasks = [task("Yesterday", offset: -1), done, task("Tomorrow", offset: 1), pending, task("Undated", offset: nil)]
        #expect(Set(tasks.filter { TaskDateScope.today.includes($0, now: day, calendar: calendar) }.map(\.id))
                == Set([pending.id, done.id]))
        #expect(tasks.allSatisfy { TaskDateScope.any.includes($0, now: day, calendar: calendar) })
    }

    @Test func overdueMeansPendingTasksBeforeToday() {
        let overdue = task("Overdue", offset: -1)
        let tasks = [task("Completed yesterday", offset: -1, done: true), task("Today"), overdue,
                     task("Tomorrow", offset: 1), task("Undated", offset: nil)]
        #expect(tasks.filter { TaskDateScope.overdue.includes($0, now: day, calendar: calendar) } == [overdue])
    }

    @Test func dateScopeCombinesWithStatusCategoryAndSearch() {
        let match = task("Study Swift", icon: .study)
        let tasks = [match, task("Study Swift tomorrow", offset: 1, icon: .study),
                     task("Study Swift done", done: true, icon: .study), task("Study Swift work", icon: .work)]
        let query = TaskQuery(collection: .all, category: .category(.study), search: "Swift", dateScope: .today)
        #expect(query.results(in: tasks, now: day, calendar: calendar) == [match])
        #expect(TaskQuery(collection: .completed, dateScope: .overdue).results(in: tasks, now: day, calendar: calendar).isEmpty)
    }

    @Test func todayFollowsCalendarDayBoundariesAcrossTheLongDay() {
        let task = task("Long day")
        let end = calendar.dateInterval(of: .day, for: day)!.end
        #expect(end.timeIntervalSince(day) == 25 * 60 * 60)
        #expect(TaskDateScope.today.includes(task, now: end.addingTimeInterval(-1), calendar: calendar))
        #expect(!TaskDateScope.today.includes(task, now: end, calendar: calendar))
        #expect(TaskDateScope.overdue.includes(task, now: end, calendar: calendar))
    }
}
