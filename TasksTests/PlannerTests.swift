import Foundation
import Testing
@testable import Tasks

@Suite struct PlannerTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private var day: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 31))!
    }

    private func task(offset: Int = 0, hour: Int? = nil, minute: Int = 0, done: Bool = false) -> TaskSnapshot {
        let date = calendar.date(byAdding: .day, value: offset, to: day)!
        return TaskSnapshot(id: UUID(), title: "Task", isDone: done, updatedAt: day, pendingSync: true,
                            dueDate: date, dueTime: hour.flatMap {
            calendar.date(bySettingHour: $0, minute: minute, second: 0, of: date)
        })
    }

    @Test func homeSectionsAreDisjointAndNextTasksUseDeadlineOrderAcrossDST() {
        let overdue = task(offset: -1)
        let today = task()
        let done = task(done: true)
        let tomorrowMorning = task(offset: 1, hour: 9)
        let tomorrowEvening = task(offset: 1, hour: 20)
        let later = task(offset: 2)
        let undated = TaskSnapshot(id: UUID(), title: "Undated", isDone: false, updatedAt: day, pendingSync: true)
        let plan = TodayPlan(tasks: [later, task(offset: 3), tomorrowEvening, overdue,
                                     today, done, tomorrowMorning, undated, task(offset: 1, done: true)],
                             now: day, calendar: calendar)
        #expect(Set(plan.today.map(\.id)) == Set([today.id, done.id]))
        #expect(plan.overdue.map(\.id) == [overdue.id])
        #expect(plan.next.map(\.id) == [tomorrowMorning.id, tomorrowEvening.id, later.id])
        let ids = (plan.today + plan.overdue + plan.next).map(\.id)
        #expect(Set(ids).count == ids.count)
    }
}
