import XCTest

@MainActor
final class CalendarLayoutUITests: XCTestCase {
    private func launch(dark: Bool = false, large: Bool = false, samples: Bool = true) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = "pt_BR"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        if samples { app.launchEnvironment["TASKS_REPLACE_WITH_SAMPLE_DATA"] = UUID().uuidString }
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["tab.upcoming"].waitForExistence(timeout: 15))
        app.buttons["tab.upcoming"].tap()
        XCTAssertTrue(app.buttons["upcoming.chooseDate"].waitForExistence(timeout: 5))
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let navigation = app.otherElements["app.navigation"]
        for _ in 0..<15 {
            if element.isHittable, element.frame.maxY <= navigation.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertLessThanOrEqual(element.frame.maxY, navigation.frame.minY + 0.5)
    }

    private func top(_ app: XCUIApplication) {
        for _ in 0..<15 where !app.buttons["upcoming.options"].isHittable { app.swipeDown() }
    }

    private func select(_ period: String, in app: XCUIApplication) {
        top(app)
        app.segmentedControls["upcoming.period"].buttons[period].tap()
    }

    private func row(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.open.", title)).firstMatch
    }

    func testCalendarOverviewLight() {
        let app = launch()
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Semana"].isSelected)
        let first = row("Revisar o projeto", in: app)
        XCTAssertTrue(first.isHittable)
        XCTAssertLessThanOrEqual(first.frame.maxY, app.otherElements["app.navigation"].frame.minY)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "upcoming.addDay.")).firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["tasks.categoryFilter"].exists)
        capture(app, "Calendar - Light - week overview")
    }

    func testEmptyWeekAndTimedCreationUseTheSelectedDay() {
        let app = launch(dark: true, samples: false)
        XCTAssertTrue(app.otherElements["upcoming.emptyWeek"].waitForExistence(timeout: 5))
        capture(app, "Calendar - Dark - empty week")
        app.buttons["upcoming.nextPeriod"].tap()
        app.buttons["upcoming.day.1"].tap()
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Dia"].isSelected)
        let selectedDate = app.buttons["upcoming.chooseDate"].value as? String
        XCTAssertFalse(app.buttons["upcoming.day.1"].exists)
        let grid = app.buttons["upcoming.timeGrid"]
        reveal(grid, in: app)
        grid.tap()
        let slot = app.buttons["agenda.slot.0.0"]
        XCTAssertTrue(slot.waitForExistence(timeout: 5))
        slot.tap()
        let title = app.textFields["task.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons["task.editor.time"].value as? String, "00:00")
        title.tap()
        title.typeText("Planejar a entrega")
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        let task = row("Planejar a entrega", in: app)
        XCTAssertTrue(task.waitForExistence(timeout: 5))
        top(app)
        XCTAssertEqual(app.buttons["upcoming.chooseDate"].value as? String, selectedDate)
        capture(app, "Calendar - Dark - selected day with timed task")
        app.buttons["tab.all"].tap()
        app.buttons["tasks.focus.today"].tap()
        XCTAssertFalse(task.exists)
        app.buttons["tab.upcoming"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 5))
    }

    func testMonthSelectionAndDatePickerKeepTheMonthMode() {
        let app = launch(dark: true)
        select("Mês", in: app)
        capture(app, "Calendar - Dark - month and selected day")
        let originalMonth = app.buttons["upcoming.chooseDate"].value as? String
        app.buttons["upcoming.nextPeriod"].tap()
        XCTAssertNotEqual(app.buttons["upcoming.chooseDate"].value as? String, originalMonth)
        app.buttons["upcoming.previousPeriod"].tap()
        XCTAssertEqual(app.buttons["upcoming.chooseDate"].value as? String, originalMonth)
        app.buttons["upcoming.monthDay.1"].tap()
        XCTAssertTrue(app.buttons["upcoming.monthDay.1"].isSelected)
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Mês"].isSelected)
        app.buttons["upcoming.chooseDate"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.buttons["upcoming.confirmDate"].tap()
        XCTAssertTrue(app.segmentedControls["upcoming.period"].buttons["Mês"].isSelected)
        reveal(app.staticTexts["upcoming.selectedDate"], in: app)
        capture(app, "Calendar - Dark - selected date remains visible")
    }

    func testMaximumTextKeepsAllDatesAndTasksReachable() {
        let app = launch(large: true)
        for weekday in 1...7 {
            let date = app.buttons["upcoming.day.\(weekday)"]
            XCTAssertTrue(date.isHittable)
            XCTAssertGreaterThanOrEqual(date.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(date.frame.maxX, app.frame.maxX)
        }
        capture(app, "Calendar - maximum text - complete week strip")
        select("Mês", in: app)
        for day in [1, 28] {
            let date = app.buttons["upcoming.monthDay.\(day)"]
            XCTAssertTrue(date.isHittable)
            XCTAssertGreaterThanOrEqual(date.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(date.frame.maxX, app.frame.maxX)
        }
        capture(app, "Calendar - maximum text - complete month")
        app.buttons["upcoming.today"].tap()
        reveal(app.buttons["Concluir Estudar Swift"], in: app)
        XCTAssertTrue(app.buttons["task.new"].isHittable)
        capture(app, "Calendar - maximum text - readable tasks")
    }

    func testMovingAndCompletingATaskKeepsItsTimeAndUndo() {
        let app = launch()
        select("Dia", in: app)
        let task = row("Revisar o projeto", in: app)
        reveal(task, in: app)
        let label = task.label
        task.press(forDuration: 1.2)
        app.buttons["Mover para…"].tap()
        app.buttons["Amanhã"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 10))
        top(app)
        app.buttons["upcoming.nextPeriod"].tap()
        reveal(task, in: app)
        XCTAssertEqual(task.label, label)
        app.buttons["Concluir Revisar o projeto"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 10))
        app.buttons["task.undoCompletion"].tap()
        XCTAssertTrue(task.waitForExistence(timeout: 10))
        capture(app, "Calendar - task rescheduled with time and completion restored")
    }
}
