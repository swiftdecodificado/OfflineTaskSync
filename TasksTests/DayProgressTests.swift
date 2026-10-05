import Foundation
import Testing
@testable import Tasks

@Suite struct DayProgressTests {
    @Test func progressCountsOnlyTasksDueOnTheSelectedDay() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date.now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let tasks = [
            TaskSnapshot(id: UUID(), title: "Open", isDone: false, updatedAt: today, pendingSync: true, dueDate: today),
            TaskSnapshot(id: UUID(), title: "Done", isDone: true, updatedAt: today, pendingSync: true, dueDate: today),
            TaskSnapshot(id: UUID(), title: "Tomorrow", isDone: true, updatedAt: today, pendingSync: true, dueDate: tomorrow),
            TaskSnapshot(id: UUID(), title: "No date", isDone: true, updatedAt: today, pendingSync: true)
        ]
        let progress = DayProgress(tasks: tasks, date: today, calendar: calendar)
        #expect(progress.completedCount == 1)
        #expect(progress.totalCount == 2)
        #expect(progress.fraction == 0.5)
        #expect(DayProgress(tasks: [], date: today).fraction == 0)
        let visible = TaskQuery(collection: .today, selectedDay: today, includeCompleted: true)
            .results(in: tasks, now: today, calendar: calendar)
        #expect(Set(visible.map(\.title)) == ["Open", "Done"])
    }

    @Test func categoryProgressKeepsCompletedAndPendingOnTheSameTotal() {
        let today = Calendar.current.startOfDay(for: .now)
        let open = TaskSnapshot(id: UUID(), title: "Work", isDone: false, updatedAt: today, pendingSync: true,
                                dueDate: today, iconName: TaskIcon.work.rawValue)
        let done = TaskSnapshot(id: UUID(), title: "Done", isDone: true, updatedAt: today, pendingSync: true,
                                dueDate: today, iconName: TaskIcon.work.rawValue)
        let study = TaskSnapshot(id: UUID(), title: "Study", isDone: true, updatedAt: today, pendingSync: true,
                                 dueDate: today, iconName: TaskIcon.study.rawValue)
        let work = TaskCategoryFilter.category(.work)
        let progress = DayProgress(tasks: [open, done, study].filter(work.includes), date: today)
        #expect(progress.completedCount == 1)
        #expect(progress.pendingCount == 1)
        #expect(progress.completedCount + progress.pendingCount == progress.totalCount)
        let completedOpen = TaskSnapshot(id: open.id, title: open.title, isDone: true, updatedAt: today, pendingSync: true,
                                         dueDate: today, iconName: TaskIcon.work.rawValue)
        let complete = DayProgress(tasks: [completedOpen, done, study].filter(work.includes), date: today)
        #expect(complete.completedCount == 2)
        #expect(complete.pendingCount == 0)
        #expect(complete.totalCount == 2)
        let empty = DayProgress(tasks: [], date: today)
        #expect(empty.totalCount == 0 && empty.pendingCount == 0 && empty.completedCount == 0)
    }

    @Test func dailyTaskOrderStaysStableWhenATaskIsCompleted() {
        let today = Calendar.current.startOfDay(for: .now)
        let firstID = UUID()
        let second = TaskSnapshot(id: UUID(), title: "Later", isDone: false, updatedAt: today, pendingSync: true,
                                  dueDate: today, dueTime: today.addingTimeInterval(7200))
        let first = TaskSnapshot(id: firstID, title: "Earlier", isDone: false, updatedAt: today, pendingSync: true,
                                 dueDate: today, dueTime: today.addingTimeInterval(3600))
        let completed = TaskSnapshot(id: firstID, title: first.title, isDone: true, updatedAt: .now, pendingSync: true,
                                     dueDate: today, dueTime: first.dueTime)
        let query = TaskQuery(collection: .today, selectedDay: today, includeCompleted: true)
        #expect(query.results(in: [first, second]).map(\.id) == [firstID, second.id])
        #expect(query.results(in: [completed, second]).map(\.id) == [firstID, second.id])
    }
}
