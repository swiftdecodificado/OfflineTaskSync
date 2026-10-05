import XCTest

@MainActor
final class TaskScheduleUITests: XCTestCase {
    private func launch(portuguese: Bool = false, dark: Bool = false, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = portuguese ? "pt_BR" : "en_US"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launchArguments += ["-AppleLanguages", portuguese ? "(pt-BR)" : "(en)", "-AppleLocale", portuguese ? "pt_BR" : "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.buttons["tab.upcoming"].tap()
        app.buttons["upcoming.nextWeek"].tap()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let navigation = app.otherElements["app.navigation"]
        let top = app.frame.minY + 64
        for _ in 0..<22 {
            if element.exists {
                let frame = element.frame
                if element.isHittable, frame.minY >= top, frame.maxY <= navigation.frame.minY { return }
                if frame.minY < top { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func create(_ title: String, slot: String = "0.0", end: String? = nil,
                        category: String = "book.closed.fill", in app: XCUIApplication) {
        let time = app.buttons["agenda.slot.\(slot)"]
        reveal(time, in: app)
        time.tap()
        let input = app.descendants(matching: .any)["task.schedule.title"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["task.schedule.save"].isEnabled)
        input.tap()
        input.typeText(title)
        if let end {
            app.buttons["task.schedule.end"].tap()
            let pattern = end.replacingOccurrences(of: " ", with: "\\s*")
            app.buttons.matching(NSPredicate(format: "label MATCHES %@", pattern)).firstMatch.tap()
        }
        revealCategoryBlock(category, in: app).tap()
        app.buttons["task.schedule.save"].tap()
        XCTAssertTrue(input.waitForNonExistence(timeout: 10))
    }

    func testGridCreationDurationCategoryPersistenceCompletionAndUndo() {
        let app = launch()
        create("Plan the release", end: "12:45 AM", in: app)
        let open = app.buttons["Plan the release"]
        reveal(open, in: app)
        XCTAssertEqual(open.frame.height, 132, accuracy: 0.5)
        XCTAssertTrue(app.buttons["Complete Plan the release"].isHittable)
        XCTAssertFalse(app.buttons["upcoming.untimed"].exists)
        capture(app, "Task calendar - three quarter-hour block")
        app.buttons["tab.all"].tap()
        XCTAssertTrue(app.staticTexts["Plan the release"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.buttons["tab.upcoming"].tap()
        app.buttons["upcoming.nextWeek"].tap()
        reveal(open, in: app)
        XCTAssertEqual(open.frame.height, 132, accuracy: 0.5)
        app.buttons["Complete Plan the release"].tap()
        XCTAssertTrue(app.buttons["task.undoCompletion"].waitForExistence(timeout: 5))
        app.buttons["task.undoCompletion"].tap()
        reveal(open, in: app)
        capture(app, "Task calendar - restored task before swipe")
        open.swipeLeft()
        app.buttons["task.swipe.deadline"].tap()
        XCTAssertTrue(app.switches["Deadline"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        open.tap()
        app.buttons["task.iconPicker"].tap()
        let study = revealCategoryBlock("book.closed.fill", in: app)
        XCTAssertTrue(study.waitForExistence(timeout: 5))
        XCTAssertTrue(study.isSelected)
    }

    func testOverlappingTasksKeepTheirOwnActions() {
        let app = launch()
        create("First block", end: "12:30 AM", in: app)
        create("Second block", end: "12:45 AM", category: "figure.walk", in: app)
        let first = app.buttons["First block"]
        let second = app.buttons["Second block"]
        reveal(first, in: app)
        XCTAssertTrue(second.isHittable)
        XCTAssertTrue(first.frame.maxX <= second.frame.minX || second.frame.maxX <= first.frame.minX)
        capture(app, "Task calendar - overlapping tasks")
        app.buttons["Complete Second block"].tap()
        XCTAssertTrue(app.buttons["task.undoCompletion"].waitForExistence(timeout: 5))
        XCTAssertTrue(first.isHittable)
    }

    func testPortugueseDarkMidnightAndNoUntimedSection() {
        let app = launch(portuguese: true, dark: true)
        create("Fechar o dia", slot: "23.45", category: "cart.fill", in: app)
        let task = app.buttons["Concluir Fechar o dia"]
        reveal(task, in: app)
        XCTAssertFalse(app.buttons["upcoming.untimed"].exists)
        capture(app, "Task calendar - Portuguese Dark - midnight")
    }

    func testMaximumTextKeepsTasksAndTimeSelectionReachable() throws {
        let app = launch(large: true)
        create("Planning task", category: "house.fill", in: app)
        let complete = app.buttons["Complete Planning task"]
        reveal(complete, in: app)
        capture(app, "Task calendar - maximum Dynamic Type")
        XCTAssertTrue(app.buttons["task.new"].isHittable)
        XCTAssertFalse(app.buttons["upcoming.untimed"].exists)
        try app.performAccessibilityAudit(for: [.textClipped, .trait, .hitRegion]) { issue in
            print("Accessibility issue: \(issue.detailedDescription)")
            print("Element: \(issue.element?.debugDescription ?? "unavailable")")
            return false
        }
        complete.tap()
        XCTAssertTrue(app.buttons["task.undoCompletion"].waitForExistence(timeout: 5))
    }
    func testMaximumTextAutomaticContrastAudit() throws {
        let app = launch(large: true)
        create("Planning task", category: "house.fill", in: app)
        reveal(app.buttons["Complete Planning task"], in: app)
        try app.performAccessibilityAudit(for: [.contrast]) { issue in
            print("Accessibility issue: \(issue.detailedDescription)")
            print("Element: \(issue.element?.debugDescription ?? "unavailable")")
            return false
        }
    }

}
