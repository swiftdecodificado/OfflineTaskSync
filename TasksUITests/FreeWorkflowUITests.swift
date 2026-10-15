import XCTest

@MainActor
final class FreeWorkflowUITests: XCTestCase {
    private func launchApp(largeText: Bool = false) -> XCUIApplication {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = "light"
        if largeText {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.otherElements["app.navigation"].buttons["Today"].isSelected)
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func audit(_ app: XCUIApplication) throws {
        try app.performAccessibilityAudit { issue in
            print("Accessibility issue: \(issue.detailedDescription)")
            print("Element: \(issue.element?.debugDescription ?? "unavailable")")
            return false
        }
    }

    func testQuickCreationDetailsDeadlineAndNativeShare() throws {
        let app = launchApp()
        app.otherElements["app.navigation"].buttons["All"].tap()
        app.buttons["task.new"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch
        input.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { input.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        input.typeText("Plan the next release")
        app.buttons["task.create"].tap()
        let title = app.staticTexts["Plan the next release"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        app.staticTexts["Plan the next release"].press(forDuration: 1)
        app.buttons["Change Due Date"].tap()
        XCTAssertFalse(app.switches["Deadline"].exists)
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        try audit(app)
        app.buttons["Done"].tap()
        title.tap()
        let description = app.descendants(matching: .any).matching(identifier: "task.description").firstMatch
        XCTAssertTrue(description.waitForExistence(timeout: 5))
        description.tap()
        description.typeText("Write the release notes")
        app.swipeUp()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Tasks"].tap()
        app.staticTexts["Plan the next release"].tap()
        attach(app, name: "Task details title and saved description")
        let delete = app.buttons["Delete Task"]
        let navigation = app.otherElements["app.navigation"]
        for _ in 0..<4 where !delete.isHittable || delete.frame.maxY > navigation.frame.minY { app.swipeUp() }
        XCTAssertTrue(delete.isHittable)
        XCTAssertLessThanOrEqual(delete.frame.maxY, navigation.frame.minY)
        try audit(app)
        attach(app, name: "Task details and deadline")
        app.buttons["Tasks"].tap()
        app.buttons["More"].tap()
        app.buttons["Export tasks"].tap()
        XCTAssertTrue(app.buttons["Share JSON"].waitForExistence(timeout: 10))
        try audit(app)
        app.buttons["Share JSON"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10)
            || app.buttons["Copy"].exists || app.buttons["Save to Files"].exists)
        attach(app, name: "Native JSON sharing")
    }

    func testAccessibilityOfEmptyAndPopulatedLists() throws {
        let app = launchApp()
        attach(app, name: "Today in Light Mode")
        try audit(app)
        app.otherElements["app.navigation"].buttons["All"].tap()
        app.buttons["task.new"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch
        input.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { input.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        input.typeText("A task that can be completed offline")
        app.buttons["task.create"].tap()
        app.buttons["Complete A task that can be completed offline"].tap()
        XCTAssertTrue(app.staticTexts["No tasks here"].waitForExistence(timeout: 5))
        app.buttons["tab.all"].tap()
        app.segmentedControls.buttons["Completed"].tap()
        XCTAssertTrue(app.staticTexts["A task that can be completed offline"].waitForExistence(timeout: 5))
        try audit(app)
        attach(app, name: "Completed tasks accessibility")
    }

    func testLargestDynamicTypeKeepsCreationReachable() throws {
        let app = launchApp(largeText: true)
        attach(app, name: "Today with accessibility XXXL")
        app.buttons["task.new"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch.isHittable)
        XCTAssertTrue(app.buttons["task.create"].isHittable)
        app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch.typeText("Large text task")
        XCTAssertTrue(app.buttons["task.create"].isHittable)
        attach(app, name: "Accessibility XXXL")
        try audit(app)
    }
    func testTabsKeepDetailsAndComposerCanBeCancelled() {
        let app = launchApp()
        for name in ["Today", "Upcoming", "All"] {
            app.otherElements["app.navigation"].buttons[name].tap()
            XCTAssertTrue(app.otherElements["app.navigation"].buttons[name].isSelected)
            app.buttons["task.new"].tap()
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch.waitForExistence(timeout: 5))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["task.create"].isEnabled)
            app.buttons["Cancel"].tap()
        }
        app.otherElements["app.navigation"].buttons["All"].tap()
        app.buttons["task.new"].tap()
        app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch.typeText("Keep this detail open")
        app.buttons["task.create"].tap()
        app.staticTexts["Keep this detail open"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.title").firstMatch.waitForExistence(timeout: 5))
        app.otherElements["app.navigation"].buttons["Upcoming"].tap()
        app.otherElements["app.navigation"].buttons["All"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.title").firstMatch.exists)
    }

    func testCreationWithDescriptionDeadlineAndTimeInDarkMode() throws {
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = "dark"
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.otherElements["app.navigation"].buttons["All"].tap()
        app.buttons["task.new"].tap()
        let title = app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Task with details")
        let notes = app.descendants(matching: .any).matching(identifier: "task.newDescription").firstMatch
        notes.tap()
        notes.typeText("Keep these notes")
        app.buttons["Due date"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.newDueDate").firstMatch.waitForExistence(timeout: 5))
        app.buttons["Add due time"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.newDueTime").firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "Dark creation with required time")
        try audit(app)
        app.buttons["task.create"].tap()
        XCTAssertTrue(app.staticTexts["Task with details"].waitForExistence(timeout: 10))
        app.staticTexts["Task with details"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.title").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "task.description").firstMatch.value as? String, "Keep these notes")
    }

    func testCreationKeepsIndependentReminder() throws {
        let app = launchApp()
        app.otherElements["app.navigation"].buttons["All"].tap()
        app.buttons["task.new"].tap()
        let title = app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Task with an independent reminder")
        XCTAssertFalse(app.buttons["Add to Calendar"].isEnabled)
        app.buttons["Reminder"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.newReminder").firstMatch.waitForExistence(timeout: 5))
        attach(app, name: "Independent reminder in creation")
        app.buttons["task.create"].tap()
        XCTAssertTrue(app.staticTexts["Task with an independent reminder"].waitForExistence(timeout: 10))
        app.staticTexts["Task with an independent reminder"].tap()
        XCTAssertTrue(app.switches["Reminder"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.switches["Reminder"].value as? String, "1")
        XCTAssertFalse(app.switches["Deadline"].exists)
    }

    func testTasksSurviveTerminatingAndRelaunchingTheProcess() {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.otherElements["app.navigation"].buttons["All"].tap()
        app.buttons["task.new"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        if !app.keyboards.firstMatch.waitForExistence(timeout: 3) { input.tap() }
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        input.typeText("Survive a process restart")
        app.buttons["task.create"].tap()
        XCTAssertTrue(app.staticTexts["Survive a process restart"].waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.otherElements["app.navigation"].buttons["All"].tap()
        XCTAssertTrue(app.staticTexts["Survive a process restart"].waitForExistence(timeout: 10))
        attach(app, name: "Persisted after process restart")
    }

}
