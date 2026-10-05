import Foundation
import SwiftData
import Testing
@testable import Tasks

@Suite @MainActor struct TaskScheduleTests {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/New_York")!
        return value
    }
    private var day: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 26))! }

    @Test func gridCoversDaylightSavingChangesWithoutDuplicateIDs() {
        for (month, date, count) in [(10, 26, 96), (3, 8, 92), (11, 1, 100)] {
            let day = calendar.date(from: DateComponents(year: 2026, month: month, day: date))!
            let grid = AgendaTimeGrid(day: day, calendar: calendar)
            #expect(grid.starts.count == count)
            #expect(Set(grid.starts).count == count)
            #expect(zip(grid.starts, grid.starts.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 900 })
            #expect(grid.ends(after: grid.starts.last!).first == grid.interval.end)
        }
    }

    @Test func overlappingTasksUseSeparateColumnsAndUntimedTasksStayOutsideTheGrid() {
        let grid = AgendaTimeGrid(day: day, calendar: calendar)
        func task(_ title: String, start: Int, end: Int) -> TaskSnapshot {
            TaskSnapshot(id: UUID(), title: title, isDone: false, updatedAt: day, pendingSync: true,
                         dueDate: day, dueEndTime: grid.starts[end], dueTime: grid.starts[start])
        }
        let first = task("First", start: 36, end: 40)
        let second = task("Second", start: 37, end: 39)
        let separate = task("Separate", start: 44, end: 45)
        let untimed = TaskSnapshot(id: UUID(), title: "No time", isDone: false, updatedAt: day, pendingSync: true, dueDate: day)
        let plan = AgendaTimelinePlan(tasks: [untimed, separate, second, first], day: day, calendar: calendar)
        #expect(plan.placements.map(\.task.id) == [first.id, second.id, separate.id])
        #expect(plan.placements.map(\.columns) == [2, 2, 1])
        #expect(plan.placements.map(\.column) == [0, 1, 0])
        #expect(!plan.placements.contains { $0.task.id == untimed.id })
    }

    @Test func offGridAndLegacyTimesAppearOnceAndUntimedDaysStillHaveLines() {
        let first = TaskSnapshot(id: UUID(), title: "Off grid", isDone: false, updatedAt: day, pendingSync: true,
                                 dueDate: day, dueTime: calendar.date(bySettingHour: 9, minute: 7, second: 0, of: day))
        let otherDay = calendar.date(byAdding: .day, value: -7, to: day)!
        let legacy = TaskSnapshot(id: UUID(), title: "Legacy time", isDone: false, updatedAt: day, pendingSync: true,
                                  dueDate: day, dueTime: calendar.date(bySettingHour: 23, minute: 59, second: 0, of: otherDay))
        let untimed = TaskSnapshot(id: UUID(), title: "No time", isDone: false, updatedAt: day, pendingSync: true, dueDate: day)
        let plan = AgendaTimelinePlan(tasks: [legacy, untimed, first], day: day, calendar: calendar)
        #expect(plan.placements.map(\.task.id) == [first.id, legacy.id])
        #expect(plan.placements.allSatisfy { calendar.isDate($0.start, inSameDayAs: day) })
        #expect(plan.placements.last?.end == AgendaTimeGrid(day: day, calendar: calendar).interval.end)
        let empty = AgendaTimelinePlan(tasks: [untimed], day: day, calendar: calendar)
        #expect(empty.placements.isEmpty)
        #expect(empty.entries.count == 96)
    }

    @Test func todayStartsAtTheCurrentHourEvenWithoutTasks() throws {
        let now = try #require(calendar.date(bySettingHour: 17, minute: 42, second: 0, of: day))
        let plan = AgendaTimelinePlan(tasks: [], day: day, calendar: calendar, now: now)
        #expect(plan.grid.starts.first == calendar.date(bySettingHour: 17, minute: 0, second: 0, of: day))
        #expect(plan.grid.starts.count == 28)
        #expect(plan.entries.count == 28)
        #expect(plan.placements.isEmpty)
        let nextHour = AgendaTimeGrid(day: day, calendar: calendar, now: now.addingTimeInterval(18 * 60))
        #expect(calendar.component(.hour, from: try #require(nextHour.starts.first)) == 18)
    }

    @Test func otherDaysKeepTheirFullTimeline() throws {
        let now = try #require(calendar.date(bySettingHour: 17, minute: 42, second: 0, of: day))
        for offset in [-1, 1, 7] {
            let selected = try #require(calendar.date(byAdding: .day, value: offset, to: day))
            let grid = AgendaTimeGrid(day: selected, calendar: calendar, now: now)
            #expect(grid.starts.first == calendar.startOfDay(for: selected))
            #expect(grid.starts.count == 96)
        }
    }

    @Test func ongoingTasksStayVisibleWhenPastHoursAreHidden() throws {
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
        }
        func task(_ title: String, start: Date, end: Date) -> TaskSnapshot {
            TaskSnapshot(id: UUID(), title: title, isDone: false, updatedAt: day, pendingSync: true,
                         dueDate: day, dueEndTime: end, dueTime: start)
        }
        let past = task("Past", start: at(15), end: at(16))
        let ongoing = task("Ongoing", start: at(16, 30), end: at(17, 30))
        let future = task("Future", start: at(18), end: at(19))
        let plan = AgendaTimelinePlan(tasks: [past, ongoing, future], day: day, calendar: calendar, now: at(17, 5))
        #expect(plan.placements.map(\.task.id) == [ongoing.id, future.id])
        let visible = try #require(plan.placements.first)
        #expect(visible.start == at(17))
        #expect(visible.end == at(17, 30))
        #expect(visible.task.dueTime == at(16, 30))
        #expect(visible.columns == 1)
        let rowIDs = plan.entries.compactMap { entry -> UUID? in
            if case .task(let task) = entry.content { return task.id }
            return nil
        }
        #expect(rowIDs == [ongoing.id, future.id])
    }

    @Test func durationSurvivesReopenCompletionAndExport() async throws {
        let disk = try DiskStoreFixture()
        defer { disk.close() }
        let store = SwiftDataTaskRepository(store: try disk.open())
        var draft = TaskDraft()
        draft.title = "Scheduled task"
        draft.color = .lavender
        draft.dueDate = Calendar.current.startOfDay(for: .now)
        draft.dueTime = Calendar.current.date(bySettingHour: 9, minute: 15, second: 0, of: draft.dueDate!)!
        draft.dueEndTime = draft.dueTime!.addingTimeInterval(2700)
        try await store.saveDraft(draft, creating: true)
        try disk.disconnect()
        let reopened = SwiftDataTaskRepository(store: try disk.open())
        var task = try #require(try await reopened.snapshot(id: draft.id))
        #expect(task.dueEndTime == draft.dueEndTime)
        #expect(task.color == .lavender)
        let session = TaskEditingSession(task: task, mediaStore: makeTestMediaStore())
        #expect(session.draft.dueEndTime == draft.dueEndTime)
        try await reopened.toggleDone(id: draft.id)
        task = try #require(try await reopened.snapshot(id: draft.id))
        #expect(task.isDone)
        #expect(task.dueEndTime == draft.dueEndTime)
        let export = try TaskExport(tasks: [task])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        let archive = try decoder.decode(TaskArchive.self, from: export.data)
        #expect(archive.formatVersion == 3)
        #expect(archive.tasks.first?.dueEndTime == draft.dueEndTime)
    }

    @Test func reschedulingPreservesDurationAndRemovingTimeClearsTheEnd() async throws {
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true))
        var draft = TaskDraft()
        draft.title = "Move me"
        let cal = Calendar.current
        draft.dueDate = cal.startOfDay(for: .now)
        draft.dueTime = cal.date(bySettingHour: 9, minute: 0, second: 0, of: draft.dueDate!)!
        draft.dueEndTime = draft.dueTime!.addingTimeInterval(3600)
        try await store.saveDraft(draft, creating: true)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: draft.dueDate!)!
        try await store.setDueDate(id: draft.id, date: tomorrow)
        let moved = try #require(try await store.snapshot(id: draft.id))
        #expect(cal.isDate(moved.dueTime!, inSameDayAs: tomorrow))
        #expect(moved.dueEndTime!.timeIntervalSince(moved.dueTime!) == 3600)
        try await store.setDueTime(id: draft.id, date: cal.date(bySettingHour: 23, minute: 45, second: 0, of: tomorrow))
        let last = try #require(try await store.snapshot(id: draft.id))
        #expect(last.dueEndTime == cal.date(byAdding: .day, value: 1, to: tomorrow))
        try await store.setDueDate(id: draft.id, date: nil)
        let cleared = try #require(try await store.snapshot(id: draft.id))
        #expect(cleared.dueTime == nil)
        #expect(cleared.dueEndTime == nil)
    }

    @Test func invalidEndAndSaveFailureKeepTheOriginalTask() async throws {
        var fail = false
        let store = SwiftDataTaskRepository(store: try PersistenceContainer(inMemory: true), beforeSave: {
            if fail { throw CocoaError(.fileWriteUnknown) }
        })
        var draft = TaskDraft()
        draft.title = "Original"
        draft.dueTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: draft.dueDate!)!
        draft.dueEndTime = draft.dueTime!.addingTimeInterval(900)
        try await store.saveDraft(draft, creating: true)
        let original = try await store.snapshot(id: draft.id)
        draft.title = "Changed"
        draft.dueEndTime = draft.dueTime
        await #expect(throws: TaskScheduleError.self) { try await store.saveDraft(draft, creating: false) }
        #expect(try await store.snapshot(id: draft.id) == original)
        draft.dueEndTime = draft.dueTime!.addingTimeInterval(1800)
        fail = true
        await #expect(throws: CocoaError.self) { try await store.saveDraft(draft, creating: false) }
        #expect(try await store.snapshot(id: draft.id) == original)
    }

    @Test func versionSixMigrationKeepsTaskFieldsAndStartsWithNoEndTime() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Tasks.store")
        let id = UUID()
        try autoreleasepool {
            let schema = Schema(versionedSchema: TasksSchemaV6.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let record = TasksSchemaV6.StoredTask(id: id, title: "Keep this task", isDone: true, updatedAt: day, pendingSync: false)
            record.notes = "Keep the notes"
            record.colorID = "pink"
            record.iconName = TaskIcon.work.rawValue
            record.dueDate = day
            record.dueTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)
            context.insert(record)
            try context.save()
        }
        let container = try PersistenceContainer(storeURL: url)
        defer { container.disconnect() }
        let reader = SwiftDataTaskRepository(store: container)
        let migrated = try #require(try await reader.snapshot(id: id))
        #expect(migrated.title == "Keep this task")
        #expect(migrated.notes == "Keep the notes")
        #expect(migrated.isDone && !migrated.pendingSync)
        #expect(migrated.color == .pink && migrated.icon == .work)
        #expect(migrated.dueDate == day)
        #expect(migrated.dueEndTime == nil)
    }
}
