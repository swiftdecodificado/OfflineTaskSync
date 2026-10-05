import Foundation
import Testing
@testable import Tasks

@Suite struct TaskQueryTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: -10800)!
        return value
    }
    private var today: Date { calendar.startOfDay(for: Date(timeIntervalSince1970: 1_790_000_000)) }

    private func task(_ title: String, day: Int? = nil, done: Bool = false, color: TaskColor = .yellow, notes: String = "") -> TaskSnapshot {
        TaskSnapshot(id: UUID(), title: title, isDone: done, updatedAt: today, pendingSync: true, notes: notes,
                     dueDate: day.flatMap { calendar.date(byAdding: .day, value: $0, to: today) }, colorID: color.rawValue)
    }

    @Test func homeSeparatesTodayOverdueAndNextWithoutLosingColors() {
        let dueToday = task("Today", day: 0, color: .mint)
        let finishedToday = task("Finished today", day: 0, done: true, color: .lavender)
        let overdue = task("Late", day: -1, color: .pink)
        let tomorrow = task("Tomorrow", day: 1, color: .blue)
        let tasks = [tomorrow, task("No date"), overdue, task("Finished yesterday", day: -1, done: true), dueToday, finishedToday]
        let plan = TodayPlan(tasks: tasks, now: today, calendar: calendar)
        #expect(Set(plan.today.map(\.id)) == Set([dueToday.id, finishedToday.id]))
        #expect(plan.today.first { $0.id == finishedToday.id }?.color == .lavender)
        #expect(plan.overdue == [overdue])
        #expect(plan.next == [tomorrow])
        #expect(TaskQuery(collection: .today).results(in: tasks, now: today, calendar: calendar) == [dueToday])
    }

    @Test func selectedDaysAndFiltersKeepTheSavedTaskValues() {
        let yesterday = task("Late", day: -1, color: .peach)
        let tomorrow = task("Tomorrow", day: 1, color: .blue)
        let undated = task("No date", color: .mint, notes: "Descrição café")
        let completed = task("Finished", day: -1, done: true, color: .pink)
        let tasks = [tomorrow, undated, yesterday, completed]
        let selected = TaskQuery(collection: .upcoming, selectedDay: tomorrow.dueDate)
        #expect(selected.results(in: tasks, now: today, calendar: calendar) == [tomorrow])
        #expect(TaskQuery(collection: .today, selectedDay: yesterday.dueDate).results(in: tasks, now: today, calendar: calendar) == [yesterday])
        #expect(TaskQuery(collection: .all).results(in: tasks, now: today, calendar: calendar) == [yesterday, tomorrow, undated])
        #expect(TaskQuery(collection: .completed).results(in: tasks, now: today, calendar: calendar) == [completed])
        #expect(TaskQuery(filter: .undated, search: "cafe").results(in: tasks, now: today, calendar: calendar) == [undated])
        #expect(TaskQuery(collection: .completed, filter: .undated).results(in: tasks, now: today, calendar: calendar).isEmpty)
        #expect(TaskQuery(collection: .upcoming, search: "Late", selectedDay: tomorrow.dueDate).results(in: tasks, now: today, calendar: calendar).isEmpty)
    }
}
