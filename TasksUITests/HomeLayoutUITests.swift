import XCTest

@MainActor
final class HomeLayoutUITests: XCTestCase {
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
        XCTAssertTrue(app.buttons["tasks.focus.today"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["tab.all"].isSelected)
        XCTAssertFalse(app.buttons["tab.today"].exists)
        let navigation = app.otherElements["app.navigation"]
        XCTAssertEqual(navigation.buttons.count, 2)
        XCTAssertTrue(navigation.buttons["tab.all"].staticTexts["Tarefas"].exists)
        XCTAssertTrue(navigation.buttons["tab.upcoming"].staticTexts["Calendário"].exists)
        XCTAssertTrue(app.buttons["task.new"].isHittable)
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
        for _ in 0..<18 {
            if element.isHittable, element.frame.maxY <= navigation.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertLessThanOrEqual(element.frame.maxY, navigation.frame.minY + 0.5)
    }

    private func create(_ title: String, in app: XCUIApplication) {
        app.buttons["task.new"].tap()
        let field = app.textFields["task.title"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(title)
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
    }

    func testTasksIsTheStartingPageWithTwoDestinations() {
        let app = launch()
        XCTAssertTrue(app.segmentedControls["tasks.status"].buttons["Todas"].isSelected)
        XCTAssertEqual(app.buttons["tasks.focus.today"].label, "4 pendentes hoje")
        XCTAssertFalse(app.descendants(matching: .any)["home.progress"].exists)
        XCTAssertTrue(app.buttons["Reabrir Caminhada da manhã"].exists)
        capture(app, "Unified tasks - Light - starting page")
    }

    func testTodayShortcutFiltersTheSameListAndKeepsRemindersAvailable() {
        let app = launch(dark: true)
        app.buttons["tasks.focus.today"].tap()
        XCTAssertTrue(app.buttons["tab.all"].isSelected)
        XCTAssertTrue(app.segmentedControls["tasks.status"].buttons["Pendentes"].isSelected)
        XCTAssertTrue(app.buttons["Concluir Revisar o projeto"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Reabrir Caminhada da manhã"].exists)
        XCTAssertFalse(app.buttons["Concluir Treino"].exists)
        XCTAssertTrue(app.buttons["tasks.clearDateScope"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["home.progress"].exists)
        capture(app, "Unified tasks - Dark - Today focus and daily progress")
        app.buttons["tasks.clearDateScope"].tap()
        XCTAssertTrue(app.buttons["Concluir Treino"].waitForExistence(timeout: 5))
        app.buttons["collection.options"].tap()
        app.buttons["tasks.reminders"].tap()
        XCTAssertTrue(app.staticTexts["Nenhum lembrete"].waitForExistence(timeout: 5))
    }

    func testOverdueShortcutShowsTheTaskScheduledForYesterday() {
        let app = launch(dark: true, samples: false)
        app.buttons["tab.upcoming"].tap()
        XCTAssertTrue(app.buttons["upcoming.chooseDate"].waitForExistence(timeout: 5))
        app.segmentedControls["upcoming.period"].buttons["Dia"].tap()
        app.buttons["upcoming.previousPeriod"].tap()
        create("Resolver pendência", in: app)
        app.buttons["tab.all"].tap()
        XCTAssertEqual(app.buttons["tasks.focus.overdue"].label, "1 atrasada")
        app.buttons["tasks.focus.overdue"].tap()
        XCTAssertTrue(app.segmentedControls["tasks.status"].buttons["Pendentes"].isSelected)
        XCTAssertTrue(app.buttons["Concluir Resolver pendência"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tasks.clearDateScope"].exists)
        capture(app, "Unified tasks - overdue focus")
    }

    func testTodayEmptyCompletionAndUndoKeepTheDailyContext() {
        let app = launch(samples: false)
        app.buttons["tasks.focus.today"].tap()
        XCTAssertTrue(app.staticTexts["Nenhuma tarefa planejada"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["home.progress"].exists)
        create("Concluir hoje", in: app)
        let complete = app.buttons["Concluir Concluir hoje"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        let summary = app.descendants(matching: .any).matching(identifier: "tasks.dayComplete").firstMatch
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        let progress = app.descendants(matching: .any).matching(identifier: "home.progress").firstMatch
        XCTAssertTrue((progress.value as? String)?.contains("1 de 1") == true)
        capture(app, "Unified tasks - daily tasks complete")
        app.buttons["task.undoCompletion"].tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["tasks.clearDateScope"].exists)
        XCTAssertTrue(summary.waitForNonExistence(timeout: 5))
    }

    func testMaximumTextKeepsDailyFocusAndCalendarReachable() {
        let app = launch(large: true)
        app.buttons["tasks.focus.today"].tap()
        reveal(app.buttons["Concluir Estudar Swift"], in: app)
        XCTAssertTrue(app.buttons["task.new"].isHittable)
        capture(app, "Unified tasks - maximum text - daily list")
        app.buttons["tab.upcoming"].tap()
        XCTAssertTrue(app.buttons["upcoming.chooseDate"].waitForExistence(timeout: 5))
        app.buttons["tab.all"].tap()
        XCTAssertTrue(app.buttons["tasks.clearDateScope"].exists)
    }
}
