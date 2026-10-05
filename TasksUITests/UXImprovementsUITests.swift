import XCTest

@MainActor
final class UXImprovementsUITests: XCTestCase {
    private func launch(portuguese: Bool = false, dark: Bool = false, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launchArguments += ["-AppleLanguages", portuguese ? "(pt-BR)" : "(en)", "-AppleLocale", portuguese ? "pt_BR" : "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        return app
    }

    func testDraftRequiresDiscardAndDeadlineDoesNotRequestCalendar() {
        let app = launch()
        app.buttons["task.new"].tap()
        let title = app.descendants(matching: .any)["task.newTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Keep this draft")
        XCTAssertFalse(app.buttons["Remove Calendar request"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.alerts["Discard draft?"].waitForExistence(timeout: 5))
        app.buttons["Keep editing"].tap()
        XCTAssertEqual(title.value as? String, "Keep this draft")
        app.buttons["Cancel"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        app.buttons["task.new"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
    }
    func testHomeOrderFiltersAndUpcomingModes() throws {
        let app = launch()
        app.buttons["task.new"].tap()
        let title = app.descendants(matching: .any)["task.newTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Review the release")
        app.buttons["task.create"].tap()
        XCTAssertTrue(app.staticTexts["Today tasks"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["home.highlight"].exists)
        XCTAssertEqual(app.buttons["tab.all"].label, "All")
        app.buttons["tab.all"].tap()
        app.buttons["More"].tap()
        app.buttons["Without deadline"].tap()
        XCTAssertTrue(app.buttons["tasks.clearFilters"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["No matching tasks"].exists)
        app.buttons["tasks.clearFilters"].tap()
        XCTAssertTrue(app.staticTexts["Review the release"].waitForExistence(timeout: 5))
        app.buttons["tab.upcoming"].tap()
        XCTAssertFalse(app.buttons["upcoming.day.1"].exists)
        app.segmentedControls.buttons["Agenda"].tap()
        XCTAssertTrue(app.buttons["upcoming.day.1"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Overview"].tap()
        XCTAssertFalse(app.buttons["upcoming.day.1"].exists)
        try app.performAccessibilityAudit(for: [.contrast, .textClipped, .hitRegion]) { issue in
            print("Accessibility issue: \(issue.detailedDescription)")
            print("Element: \(issue.element?.debugDescription ?? "unavailable")")
            return false
        }
    }

    func testCompletionCanBeUndoneAcrossTabs() {
        let app = launch(portuguese: true, dark: true)
        app.buttons["task.new"].tap()
        let title = app.descendants(matching: .any)["task.newTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Revisar a entrega")
        app.buttons["task.create"].tap()
        let complete = app.buttons["Concluir Revisar a entrega"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        let undo = app.buttons["task.undoCompletion"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        app.buttons["tab.all"].tap()
        app.segmentedControls.buttons["Concluídas"].tap()
        XCTAssertTrue(app.staticTexts["Revisar a entrega"].waitForExistence(timeout: 5))
        undo.tap()
        XCTAssertTrue(app.staticTexts["Nenhuma tarefa aqui"].waitForExistence(timeout: 5))
        app.buttons["tab.today"].tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
    }

    func testPortugueseLargeNavigationAndDateSelectionAccessibility() throws {
        let app = launch(portuguese: true, large: true)
        for name in ["today", "upcoming", "all"] {
            let tab = app.buttons["tab.\(name)"]
            XCTAssertTrue(tab.isHittable)
            XCTAssertGreaterThanOrEqual(tab.frame.minX, app.frame.minX)
            XCTAssertLessThanOrEqual(tab.frame.maxX, app.frame.maxX)
        }
        app.buttons["tab.upcoming"].tap()
        app.segmentedControls.buttons["Agenda"].tap()
        XCTAssertTrue(app.buttons["upcoming.day.1"].waitForExistence(timeout: 5))
        let navigation = app.otherElements["app.navigation"]
        XCTAssertLessThan(navigation.frame.height, app.frame.height / 4)
        let message = app.staticTexts["Escolha uma data para planejar sua próxima tarefa."]
        for _ in 0..<4 where !message.isHittable || message.frame.maxY > navigation.frame.minY {
            app.swipeUp()
        }
        XCTAssertTrue(message.isHittable)
        XCTAssertLessThanOrEqual(message.frame.maxY, navigation.frame.minY)
        try app.performAccessibilityAudit(for: [.contrast, .textClipped, .hitRegion]) { issue in
            print("Accessibility issue: \(issue.detailedDescription)")
            print("Element: \(issue.element?.debugDescription ?? "unavailable")")
            return false
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Portuguese navigation and date mode with accessibility text"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

}
