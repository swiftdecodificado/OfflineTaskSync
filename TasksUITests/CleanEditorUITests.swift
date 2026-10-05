import XCTest

@MainActor
final class CleanEditorUITests: XCTestCase {
    private func launch(dark: Bool = false, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = "en_US"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launchArguments = ["-settings.language", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].firstMatch.waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: id).firstMatch
    }

    private func openFullEditor(_ app: XCUIApplication) {
        app.buttons["task.new"].firstMatch.tap()
        let title = app.descendants(matching: .any)["task.newTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Focused editor")
        let full = app.buttons["task.openFullEditor"]
        for _ in 0..<6 where !full.isHittable || full.frame.maxY > app.buttons["task.create"].frame.minY { app.swipeUp() }
        full.tap()
        capture(app, "Full editor after opening")
        let document = app.textViews["task.document"]
        if !document.waitForExistence(timeout: 5) { print(app.debugDescription) }
        XCTAssertTrue(document.exists)
    }

    private func expectDock(_ app: XCUIApplication) {
        for id in ["task.iconPicker", "task.editor.date", "task.editor.time", "task.editor.reminder", "task.editor.calendar"] {
            let control = button(id, in: app)
            XCTAssertTrue(control.isHittable, id)
            let frame = control.frame
            XCTAssertGreaterThanOrEqual(frame.width, 44, id)
            XCTAssertGreaterThanOrEqual(frame.height, 44, id)
        }
    }

    func testLightEditorKeepsToolsAndContent() {
        workflow(dark: false)
    }

    func testDarkEditorKeepsToolsAndContent() {
        workflow(dark: true)
    }

    private func workflow(dark: Bool) {
        let app = launch(dark: dark)
        openFullEditor(app)
        XCTAssertFalse(app.otherElements["task.editor.properties"].exists)
        XCTAssertFalse(app.buttons["Delete Task"].exists)
        XCTAssertFalse(app.buttons["Done"].exists)
        expectDock(app)
        capture(app, dark ? "Clean full editor - Dark" : "Clean full editor - Light")
        let document = app.textViews["task.document"]
        document.tap()
        document.typeText("Keep notes and direct dock actions.")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        expectDock(app)
        capture(app, dark ? "Keyboard dock - Dark" : "Keyboard dock - Light")
        for property in ["date", "time", "reminder"] {
            if property != "date" { document.tap() }
            button("task.editor.\(property)", in: app).tap()
            let panel = app.descendants(matching: .any)["task.editor.\(property)Panel"]
            XCTAssertTrue(panel.waitForExistence(timeout: 5))
            capture(app, "Direct \(property) tool")
            app.buttons[property == "reminder" ? "task.property.cancel" : "task.property.done"].tap()
            XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        }
        document.tap()
        button("task.editor.calendar", in: app).tap()
        XCTAssertTrue(app.scrollViews["task.editor.calendarPanel"].waitForExistence(timeout: 5))
        capture(app, "Direct Calendar tool")
        app.buttons["task.property.done"].tap()
        button("task.iconPicker", in: app).tap()
        let work = revealCategoryBlock("briefcase.fill", in: app)
        XCTAssertTrue(work.waitForExistence(timeout: 5))
        work.tap()
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(app.buttons["task.new"].firstMatch.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["tab.all"].tap()
        app.staticTexts["Focused editor"].firstMatch.tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        XCTAssertTrue((document.value as? String ?? "").contains("Keep notes and direct dock actions."))
        XCTAssertEqual(button("task.iconPicker", in: app).value as? String, "Work")
        XCTAssertFalse(app.buttons["Delete Task"].exists)
        capture(app, "Clean editor after relaunch")
    }

    func testLargeTextKeepsDockToolsVisible() {
        let app = launch(dark: true, large: true)
        openFullEditor(app)
        expectDock(app)
        let document = app.textViews["task.document"]
        document.tap()
        document.typeText("Accessible notes")
        expectDock(app)
        capture(app, "Keyboard dock - maximum Dynamic Type")
    }

    func testTodayHasCurrentHourLinesWithoutPastHours() {
        let app = launch()
        app.buttons["tab.upcoming"].tap()
        let hour = Calendar.current.component(.hour, from: .now)
        let current = app.buttons["agenda.slot.\(hour).0"]
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertTrue(current.isHittable)
        if hour > 0 { XCTAssertFalse(app.buttons["agenda.slot.\(hour - 1).0"].exists) }
        capture(app, "Today - current hour grid")
        current.tap()
        XCTAssertTrue(app.descendants(matching: .any)["task.schedule.title"].waitForExistence(timeout: 5))
    }
}
