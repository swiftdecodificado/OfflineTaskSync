import XCTest

@MainActor
final class TaskEditorSmokeTests: XCTestCase {
    func testFullEditorKeepsCategoryAndContentAfterRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = "en_US"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = "light"
        app.launchArguments = ["-settings.language", "en"]
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.buttons["task.new"].tap()
        let title = app.descendants(matching: .any)["task.newTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.typeText("Review editor note")
        revealCategoryBlock("briefcase.fill", in: app).tap()
        let fullEditor = app.buttons["task.openFullEditor"]
        for _ in 0..<6 where !fullEditor.isHittable || fullEditor.frame.maxY > app.buttons["task.create"].frame.minY { app.swipeUp() }
        fullEditor.tap()
        let document = app.textViews["task.document"]
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        for _ in 0..<3 where !document.isHittable { app.swipeUp() }
        document.tap()
        document.typeText("Content kept after reopening.")
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(app.buttons["task.saveDocument"].waitForNonExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["tab.all"].waitForExistence(timeout: 10))
        app.buttons["tab.all"].tap()
        let row = app.staticTexts["Review editor note"].firstMatch
        if !row.waitForExistence(timeout: 5) {
            print(app.debugDescription)
            let failure = XCTAttachment(screenshot: app.screenshot())
            failure.name = "Task list after editor relaunch"
            failure.lifetime = .keepAlways
            add(failure)
        }
        XCTAssertTrue(row.exists)
        row.tap()
        XCTAssertTrue(document.waitForExistence(timeout: 5))
        XCTAssertTrue((document.value as? String ?? "").contains("Content kept after reopening."))
        XCTAssertEqual(app.buttons["task.iconPicker"].value as? String, "Work")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Editor category and content after relaunch"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["Close"].tap()
    }
}
