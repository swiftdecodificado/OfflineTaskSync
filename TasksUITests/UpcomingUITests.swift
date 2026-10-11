import XCTest

@MainActor
final class UpcomingUITests: XCTestCase {
    private func launch(portuguese: Bool = false, dark: Bool = false, large: Bool = false, seedSamples: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        if seedSamples {
            app.launchEnvironment["TASKS_REPLACE_WITH_SAMPLE_DATA"] = UUID().uuidString
        }
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = portuguese ? "pt_BR" : "en_US"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launchArguments += ["-AppleLanguages", portuguese ? "(pt-BR)" : "(en)",
                                "-AppleLocale", portuguese ? "pt_BR" : "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.buttons["tab.upcoming"].tap()
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

    private func select(_ period: String, in app: XCUIApplication) {
        top(app)
        app.segmentedControls["upcoming.period"].buttons[period].tap()
    }

    private func create(_ title: String, in app: XCUIApplication) {
        let slot = app.buttons["agenda.slot.0.0"]
        reveal(slot, in: app)
        slot.tap()
        let field = app.descendants(matching: .any)["task.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(title)
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
    }

    func testCompactWeekAndPersistentMonthSelection() {
        let app = launch(seedSamples: true)
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Week"].isSelected)
        XCTAssertFalse(app.buttons["agenda.slot.0.0"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["tasks.categoryFilter"].exists)
        capture(app, "Calendar - compact week")
        select("Day", in: app)
        app.buttons["upcoming.nextPeriod"].tap()
        let grid = app.buttons["upcoming.timeGrid"]
        reveal(grid, in: app)
        grid.tap()
        create("Plan the release", in: app)
        let task = app.buttons["Complete Plan the release"]
        reveal(task, in: app)
        XCTAssertFalse(app.buttons["agenda.slot.0.0"].exists)
        capture(app, "Calendar - compact day after timed creation")
        select("Week", in: app)
        reveal(task, in: app)
        XCTAssertFalse(app.buttons["agenda.slot.0.0"].exists)
        select("Month", in: app)
        reveal(task, in: app)
        capture(app, "Calendar - month and selected day tasks")
        top(app)
        app.buttons["upcoming.monthDay.1"].tap()
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Month"].isSelected)
        XCTAssertTrue(app.buttons["upcoming.monthDay.1"].isSelected)
        capture(app, "Calendar - month keeps selection")
    }

    func testWeekDateOpensDayWithoutChangingMonthSelectionBehavior() {
        let app = launch()
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Week"].isSelected)
        app.buttons["upcoming.day.1"].tap()
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Day"].isSelected)
        select("Month", in: app)
        app.buttons["upcoming.monthDay.1"].tap()
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Month"].isSelected)
    }

    func testMoveTaskToTomorrowKeepsItsTime() {
        let app = launch(seedSamples: true)
        select("Day", in: app)
        let title = app.staticTexts["Revisar o projeto"].firstMatch
        reveal(title, in: app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.open.", "Revisar o projeto")).firstMatch
        let originalLabel = row.label
        title.press(forDuration: 1.2)
        app.buttons["Move to…"].tap()
        app.buttons["Tomorrow"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        top(app)
        app.buttons["upcoming.nextPeriod"].tap()
        reveal(title, in: app)
        XCTAssertEqual(row.label, originalLabel)
        capture(app, "Calendar - task moved with time preserved")
    }

    func testQuickCreationAndReschedulingAlwaysKeepATime() {
        let app = launch()
        select("Day", in: app)
        app.buttons["upcoming.nextPeriod"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming.addDay.")).firstMatch.tap()
        let field = app.descendants(matching: .any)["task.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Required time activity")
        XCTAssertTrue(app.buttons["task.saveDocument"].isEnabled)
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        let task = app.buttons["Complete Required time activity"]
        reveal(task, in: app)
        capture(app, "Calendar - quick activity created on the selected day")
        top(app)
        app.buttons["upcoming.previousPeriod"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 5))
        app.buttons["upcoming.nextPeriod"].tap()
        reveal(task, in: app)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.open.", "Required time activity")).firstMatch.swipeLeft()
        app.buttons["task.swipe.deadline"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Deadline"].exists)
        XCTAssertFalse(app.buttons["Remove due time"].exists)
        capture(app, "Calendar - required date and time when rescheduling")
        app.buttons["Done"].tap()
    }

    func testSampleReplacementRunsOnceAndKeepsNewActivitiesAfterRelaunch() {
        let app = launch(seedSamples: true)
        app.buttons["tab.all"].tap()
        reveal(app.staticTexts["Revisar o projeto"].firstMatch, in: app)
        app.buttons["task.new"].tap()
        let field = app.descendants(matching: .any)["task.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("Keep my new activity")
        XCTAssertTrue(app.buttons["task.saveDocument"].isEnabled)
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab.all"].waitForExistence(timeout: 10))
        app.buttons["tab.all"].tap()
        reveal(app.staticTexts["Keep my new activity"].firstMatch, in: app)
        capture(app, "Calendar - new activity survives reopening after sample replacement")
    }

    func testMonthSelectionAndPeriodNavigationInPortugueseDark() {
        let app = launch(portuguese: true, dark: true, seedSamples: true)
        select("Semana", in: app)
        let original = app.buttons["upcoming.day.1"].label
        app.buttons["upcoming.nextPeriod"].tap()
        XCTAssertNotEqual(app.buttons["upcoming.day.1"].label, original)
        app.buttons["upcoming.previousPeriod"].tap()
        XCTAssertEqual(app.buttons["upcoming.day.1"].label, original)
        select("Mês", in: app)
        let month = app.buttons["upcoming.chooseDate"].value as? String
        app.buttons["upcoming.nextPeriod"].tap()
        XCTAssertNotEqual(app.buttons["upcoming.chooseDate"].value as? String, month)
        app.buttons["upcoming.previousPeriod"].tap()
        XCTAssertEqual(app.buttons["upcoming.chooseDate"].value as? String, month)
        capture(app, "Calendar - Portuguese Dark month")
        app.buttons["upcoming.monthDay.1"].tap()
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Mês"].isSelected)
        XCTAssertTrue(app.staticTexts["upcoming.selectedDate"].exists)
        app.buttons["upcoming.chooseDate"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.buttons["upcoming.confirmDate"].tap()
        capture(app, "Calendar - Portuguese Dark selected day")
    }

    func testMaximumDynamicTypeKeepsPeriodControlsReachable() {
        let app = launch(portuguese: true, large: true)
        capture(app, "Calendar - maximum Dynamic Type week")
        select("Semana", in: app)
        app.buttons["upcoming.nextPeriod"].tap()
        select("Mês", in: app)
        capture(app, "Calendar - maximum Dynamic Type month")
        let first = app.buttons["upcoming.monthDay.1"]
        let month = app.scrollViews["upcoming.month"]
        if month.exists {
            for _ in 0..<7 where !first.isHittable { month.swipeLeft() }
        }
        XCTAssertTrue(first.isHittable)
        first.tap()
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Mês"].isSelected)
        XCTAssertTrue(app.buttons["task.new"].isHittable)
    }
}
