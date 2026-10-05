import XCTest

@MainActor
final class UpcomingUITests: XCTestCase {
    private func launch(portuguese: Bool = false, dark: Bool = false, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = portuguese ? "pt_BR" : "en_US"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launchArguments += ["-AppleLanguages", portuguese ? "(pt-BR)" : "(en)",
                                "-AppleLocale", portuguese ? "pt_BR" : "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    private func top(_ app: XCUIApplication) {
        for _ in 0..<8 where !app.buttons["upcoming.options"].isHittable { app.swipeDown() }
    }

    private func mode(_ name: String, in app: XCUIApplication) {
        top(app)
        app.buttons["upcoming.options"].tap()
        app.buttons[name].tap()
    }

    private func create(_ title: String, in app: XCUIApplication) {
        let slot = app.buttons["agenda.slot.0.0"]
        reveal(slot, in: app)
        slot.tap()
        let field = app.descendants(matching: .any)["task.schedule.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(title)
        app.buttons["task.schedule.save"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
    }

    func testSelectedDayStaysConsistentAcrossAgendaListAndOverview() {
        let app = launch()
        app.buttons["tab.upcoming"].tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming.day.")).count, 7)
        let original = app.buttons["upcoming.day.1"].label
        app.buttons["upcoming.nextWeek"].tap()
        XCTAssertNotEqual(app.buttons["upcoming.day.1"].label, original)
        app.buttons["upcoming.previousWeek"].tap()
        XCTAssertEqual(app.buttons["upcoming.day.1"].label, original)
        app.buttons["upcoming.nextWeek"].tap()
        app.buttons["upcoming.day.7"].tap()
        create("Plan the release", in: app)
        let task = app.buttons["Complete Plan the release"]
        reveal(task, in: app)
        capture(app, "Planning - English Light - selected day agenda")
        mode("List", in: app)
        reveal(task, in: app)
        mode("All upcoming tasks", in: app)
        XCTAssertFalse(app.buttons["upcoming.chooseDate"].exists)
        reveal(task, in: app)
        mode("Agenda", in: app)
        XCTAssertTrue(app.buttons["upcoming.day.7"].isSelected)
        task.tap()
        XCTAssertTrue(app.buttons["task.undoCompletion"].waitForExistence(timeout: 5))
        app.buttons["task.undoCompletion"].tap()
        reveal(task, in: app)
        app.buttons["tab.today"].tap()
        XCTAssertFalse(app.buttons["home.highlight"].exists)
        reveal(app.buttons["home.next"], in: app)
        app.buttons["home.next"].tap()
        reveal(app.buttons["home.highlight"].firstMatch, in: app)
        capture(app, "Today - upcoming preview on demand")
    }

    func testTaskSwipeReschedulingUsesDeadlineSheet() {
        let app = launch()
        app.buttons["tab.upcoming"].tap()
        app.buttons["upcoming.nextWeek"].tap()
        create("Move this task", in: app)
        let task = app.buttons["Complete Move this task"]
        reveal(task, in: app)
        let row = app.buttons["Move this task"]
        row.swipeLeft()
        app.buttons["task.swipe.deadline"].tap()
        let deadline = app.switches["Deadline"]
        XCTAssertTrue(deadline.waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers.firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["task.title"].exists)
        deadline.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForNonExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))
        app.buttons["tab.all"].tap()
        reveal(task, in: app)
        capture(app, "Rescheduled task remains saved without a deadline")
    }

    func testTimedTasksKeepIndependentSwipeActions() {
        let app = launch()
        app.buttons["tab.upcoming"].tap()
        app.buttons["upcoming.nextWeek"].tap()
        app.buttons["task.new"].tap()
        let title = app.descendants(matching: .any)["task.newTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Timed review")
        revealCategoryBlock("none", in: app).tap()
        let time = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Time")).firstMatch
        let save = app.buttons["task.create"]
        for _ in 0..<6 where !time.isHittable || time.frame.maxY > save.frame.minY {
            app.scrollViews.firstMatch.swipeUp()
        }
        XCTAssertTrue(time.isHittable)
        time.tap()
        XCTAssertTrue(app.pickerWheels.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        app.buttons["task.create"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        create("Another timed review", in: app)
        let timed = app.buttons["Complete Timed review"]
        let another = app.buttons["Complete Another timed review"]
        reveal(timed, in: app)
        capture(app, "Planning - timed task on the quarter-hour grid")
        app.buttons["Timed review"].swipeLeft()
        app.buttons["task.swipe.deadline"].tap()
        XCTAssertTrue(app.switches["Deadline"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        mode("List", in: app)
        reveal(timed, in: app)
        reveal(another, in: app)
        XCTAssertFalse(app.staticTexts["No time"].exists)
    }

    func testPastDateTasksAppearAsOverdueOnToday() {
        let app = launch()
        app.buttons["tab.upcoming"].tap()
        app.buttons["upcoming.previousWeek"].tap()
        create("Follow up overdue work", in: app)
        app.buttons["tab.today"].tap()
        let task = app.buttons["Complete Follow up overdue work"]
        reveal(task, in: app)
        XCTAssertTrue(app.staticTexts["Overdue"].exists)
        capture(app, "Today - overdue task")
    }

    func testPortugueseDarkMonthSelectionAndWeekRollover() throws {
        let app = launch(portuguese: true, dark: true)
        app.buttons["tab.upcoming"].tap()
        app.buttons["upcoming.chooseDate"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.buttons["DatePicker.NextMonth"].tap()
        let first = app.datePickers.buttons.matching(NSPredicate(format: "label CONTAINS %@", ", 1 de ")).firstMatch
        XCTAssertTrue(first.exists)
        first.tap()
        app.buttons["upcoming.confirmDate"].tap()
        let selected = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming.day."))
            .allElementsBoundByIndex.filter(\.isSelected)
        XCTAssertEqual(selected.count, 1)
        let selectedDate = app.staticTexts["upcoming.selectedDate"].label
        app.buttons["upcoming.previousWeek"].tap()
        XCTAssertNotEqual(app.staticTexts["upcoming.selectedDate"].label, selectedDate)
        app.buttons["upcoming.nextWeek"].tap()
        XCTAssertEqual(app.staticTexts["upcoming.selectedDate"].label, selectedDate)
        capture(app, "Planning - Portuguese Dark - native month selection")
        try app.performAccessibilityAudit(for: [.contrast, .textClipped, .trait, .hitRegion]) { issue in
            print("Accessibility issue: \(issue.detailedDescription)")
            print("Element: \(issue.element?.debugDescription ?? "unavailable")")
            return false
        }
    }

    func testMaximumDynamicTypeKeepsDatesAndActionsReachable() throws {
        let app = launch(portuguese: true, large: true)
        app.buttons["tab.upcoming"].tap()
        app.buttons["upcoming.nextWeek"].tap()
        capture(app, "Planning - maximum Dynamic Type - top")
        let dates = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming.day."))
        for day in dates.allElementsBoundByIndex {
            let strip = app.scrollViews["upcoming.week"]
            for _ in 0..<7 where day.frame.minX < app.frame.minX || day.frame.maxX > app.frame.maxX {
                if day.frame.minX < app.frame.minX { strip.swipeRight() }
                else { strip.swipeLeft() }
            }
            XCTAssertTrue(day.isHittable)
            day.tap()
            XCTAssertTrue(day.isSelected)
            XCTAssertGreaterThanOrEqual(day.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(day.frame.maxX, app.frame.maxX)
        }
        reveal(app.buttons["agenda.slot.0.0"], in: app)
        capture(app, "Planning - maximum Dynamic Type - quarter-hour grid")
        XCTAssertTrue(app.buttons["task.new"].isHittable)
        try app.performAccessibilityAudit(for: [.contrast, .textClipped, .trait, .hitRegion]) { issue in
            print("Accessibility issue: \(issue.detailedDescription)")
            print("Element: \(issue.element?.debugDescription ?? "unavailable")")
            return false
        }
    }
}
