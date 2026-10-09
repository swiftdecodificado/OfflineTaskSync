import Foundation
import Testing
@testable import Tasks

@Suite struct TaskListSortTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 11, day: 1))! }

    private func task(_ title: String, offset: Int? = 0, hour: Int = 9, id: UUID = UUID(),
                      done: Bool = false, updatedAt: Date? = nil, notes: String = "") -> TaskSnapshot {
        let date = offset.flatMap { calendar.date(byAdding: .day, value: $0, to: day) }
        return TaskSnapshot(id: id, title: title, isDone: done, updatedAt: updatedAt ?? day,
                            pendingSync: false, notes: notes, dueDate: date,
                            dueTime: date.flatMap { calendar.date(bySettingHour: hour, minute: 0, second: 0, of: $0) })
    }

    @Test func deadlinesUseDayAndTimeAcrossDaylightSavingAndPutUndatedTasksLast() {
        let early = task("Early", hour: 8)
        let late = task("Late", hour: 15)
        let tomorrow = task("Tomorrow", offset: 1, hour: 7)
        let undated = task("Undated", offset: nil)
        #expect(TaskListSort.deadline.ordered([undated, tomorrow, late, early], calendar: calendar).map(\.id)
                == [early.id, late.id, tomorrow.id, undated.id])
    }

    @Test func editingNotesDoesNotReorderTasksWithTheSameDeadline() {
        let first = task("First")
        let second = task("Second")
        let original = TaskListSort.deadline.ordered([first, second], calendar: calendar).map(\.id)
        let edited = task("First", id: first.id, updatedAt: day.addingTimeInterval(200), notes: "Updated notes")
        #expect(TaskListSort.deadline.ordered([second, edited], calendar: calendar).map(\.id) == original)
    }

    @Test func completionDoesNotChangeTheOrderOfAnAllStatusList() {
        let early = task("Early", hour: 8, done: true)
        let late = task("Late", hour: 16)
        #expect(TaskListSort.deadline.ordered([late, early], calendar: calendar).map(\.id) == [early.id, late.id])
    }

    @Test func titleAndRecentSortsRemainAvailable() {
        let alpha = task("Alpha", offset: 1)
        let beta = task("Beta", offset: -1, updatedAt: day.addingTimeInterval(60))
        #expect(TaskListSort.title.ordered([beta, alpha], calendar: calendar).map(\.id) == [alpha.id, beta.id])
        #expect(TaskListSort.recentlyUpdated.ordered([alpha, beta], calendar: calendar).map(\.id) == [beta.id, alpha.id])
    }
}
