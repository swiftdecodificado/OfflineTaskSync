import XCTest

@MainActor
final class TaskScheduleUITests: XCTestCase {
    private func launch(portuguese: Bool = false, dark: Bool = false, large: Bool = false, seedSamples: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        if seedSamples { app.launchEnvironment["TASKS_REPLACE_WITH_SAMPLE_DATA"] = UUID().uuidString }
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = portuguese ? "pt_BR" : "en_US"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launchArguments += ["-AppleLanguages", portuguese ? "(pt-BR)" : "(en)", "-AppleLocale", portuguese ? "pt_BR" : "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.buttons["tab.upcoming"].tap()
        app.segmentedControls["upcoming.period"].buttons[portuguese ? "Dia" : "Day"].tap()
        for _ in 0..<8 where !app.buttons["upcoming.nextPeriod"].isHittable { app.swipeDown() }
        app.buttons["upcoming.nextPeriod"].tap()
        return app
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let navigation = app.otherElements["app.navigation"]
        let navigationBar = app.navigationBars.firstMatch
        let top = navigationBar.exists ? navigationBar.frame.maxY : app.frame.minY + 64
        let bottom = navigation.isHittable ? navigation.frame.minY : app.frame.maxY - 30
        for _ in 0..<22 {
            if element.exists {
                let frame = element.frame
                if element.isHittable, frame.minY >= top, frame.maxY <= bottom { return }
                if frame.height > 0, frame.width > 0, frame.maxY < top { app.swipeDown(); continue }
            }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
    }

    private func openGrid(in app: XCUIApplication) {
        let grid = app.buttons["upcoming.timeGrid"]
        reveal(grid, in: app)
        grid.tap()
        XCTAssertTrue(app.buttons["agenda.slot.0.0"].waitForExistence(timeout: 5))
    }

    private func taskAction(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label))
        let buttons = matches.allElementsBoundByIndex
        return buttons.first(where: { $0.isHittable }) ?? buttons.last ?? matches.firstMatch
    }

    private func openTask(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.open.", title)).firstMatch
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func chooseCategory(_ name: String, in app: XCUIApplication) {
        let strip = app.scrollViews["task.icon.options"].firstMatch
        let block = app.buttons["task.icon.option.\(name)"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        for _ in 0..<20 {
            let bounds = strip.frame
            if block.exists, block.isHittable,
               block.frame.minX >= bounds.minX, block.frame.maxX <= bounds.maxX {
                block.tap()
                return
            }
            let moveRight = block.exists && block.frame.minX < bounds.minX
            let start = strip.coordinate(withNormalizedOffset: CGVector(dx: moveRight ? 0.3 : 0.7, dy: 0.5))
            let end = strip.coordinate(withNormalizedOffset: CGVector(dx: moveRight ? 0.7 : 0.3, dy: 0.5))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0)
        }
        XCTFail("Category could not be reached: \(name)")
    }

    private func create(_ title: String, slot: String = "0.0", end: String? = nil,
                        category: String? = "book.closed.fill", in app: XCUIApplication) {
        openGrid(in: app)
        let time = app.buttons["agenda.slot.\(slot)"]
        reveal(time, in: app)
        time.tap()
        let input = app.descendants(matching: .any)["task.schedule.title"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["task.schedule.save"].isEnabled)
        input.tap()
        input.typeText(title)
        let dismissKeyboard = app.buttons["task.schedule.dismissKeyboard"]
        if dismissKeyboard.exists { dismissKeyboard.tap() }
        if let end {
            app.buttons["task.schedule.end"].tap()
            let pattern = end.replacingOccurrences(of: " ", with: "\\s*")
            app.buttons.matching(NSPredicate(format: "label MATCHES %@", pattern)).firstMatch.tap()
        }
        if let category {
            let strip = app.scrollViews["task.icon.options"].firstMatch
            for _ in 0..<6 {
                let bottom = app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY : app.frame.maxY - 30
                if strip.exists, strip.isHittable, strip.frame.maxY < bottom { break }
                app.swipeUp()
            }
            chooseCategory(category, in: app)
        }
        app.buttons["task.schedule.save"].tap()
        XCTAssertTrue(input.waitForNonExistence(timeout: 10))
    }

    func testGridCreationDurationCategoryPersistenceCompletionAndUndo() {
        let app = launch()
        create("Plan the release", end: "12:45 AM", in: app)
        let open = openTask("Plan the release", in: app)
        openGrid(in: app)
        reveal(open, in: app)
        XCTAssertEqual(open.frame.height, 132, accuracy: 0.5)
        reveal(taskAction("Complete Plan the release", in: app), in: app)
        XCTAssertTrue(taskAction("Complete Plan the release", in: app).isHittable)
        XCTAssertFalse(app.buttons["upcoming.untimed"].exists)
        capture(app, "Task calendar - three quarter-hour block")
        app.buttons["Done"].tap()
        app.buttons["tab.all"].tap()
        XCTAssertTrue(app.staticTexts["Plan the release"].waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.buttons["tab.upcoming"].tap()
        app.segmentedControls["upcoming.period"].buttons["Day"].tap()
        for _ in 0..<8 where !app.buttons["upcoming.nextPeriod"].isHittable { app.swipeDown() }
        app.buttons["upcoming.nextPeriod"].tap()
        openGrid(in: app)
        reveal(open, in: app)
        XCTAssertEqual(open.frame.height, 132, accuracy: 0.5)
        app.buttons["Done"].tap()
        reveal(open, in: app)
        taskAction("Complete Plan the release", in: app).tap()
        XCTAssertTrue(app.buttons["task.undoCompletion"].waitForExistence(timeout: 5))
        app.buttons["task.undoCompletion"].tap()
        reveal(open, in: app)
        capture(app, "Task calendar - restored task before swipe")
        open.swipeLeft()
        app.buttons["task.swipe.deadline"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Deadline"].exists)
        app.buttons["Done"].tap()
        open.tap()
        let category = app.buttons["task.iconPicker"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        XCTAssertEqual(category.value as? String, "Study")
    }

    func testOverlappingTasksKeepTheirOwnActions() {
        let app = launch()
        create("First block", end: "12:30 AM", in: app)
        create("Second block", end: "12:45 AM", category: "figure.walk", in: app)
        openGrid(in: app)
        let first = openTask("First block", in: app)
        let second = openTask("Second block", in: app)
        reveal(first, in: app)
        XCTAssertTrue(second.isHittable)
        XCTAssertTrue(first.frame.maxX <= second.frame.minX || second.frame.maxX <= first.frame.minX)
        capture(app, "Task calendar - overlapping tasks")
        taskAction("Complete Second block", in: app).tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["task.undoCompletion"].waitForExistence(timeout: 5))
        reveal(first, in: app)
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
        create("Planning task", category: nil, in: app)
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
        let app = launch(large: true, seedSamples: true)
        reveal(app.buttons["Complete Treino"], in: app)
        capture(app, "Task calendar - maximum Dynamic Type contrast")
        try app.performAccessibilityAudit(for: [.contrast]) { issue in
            print("Accessibility issue: \(issue.detailedDescription)")
            print("Element: \(issue.element?.debugDescription ?? "unavailable")")
            return false
        }
    }

}
