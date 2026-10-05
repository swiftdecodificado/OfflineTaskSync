import XCTest

@MainActor
final class CategoryBlocksUITests: XCTestCase {
    private func launch(dark: Bool = false, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launchArguments = ["-settings.language", "en", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
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

    private func create(_ title: String, icon: String = "none", in app: XCUIApplication) {
        app.buttons["task.new"].tap()
        let field = app.descendants(matching: .any)["task.newTitle"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(title)
        XCTAssertFalse(app.buttons["task.iconPicker"].exists)
        revealCategoryBlock(icon, in: app).tap()
        capture(app, "Inline category blocks - creation")
        app.buttons["task.create"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
    }

    private func filter(_ name: String, in app: XCUIApplication) -> XCUIElement {
        revealCategoryBlock(name, in: app, prefix: "tasks.category", stripID: "tasks.categoryFilter")
    }

    private func expectProgress(_ completed: Int, total: Int, pending: Int, in app: XCUIApplication) {
        let chart = app.descendants(matching: .any)["home.progress"]
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        let predicate = NSPredicate(format: "value CONTAINS %@ AND value CONTAINS %@",
                                    "\(completed) of \(total)", "Remaining: \(pending)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: chart)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
    }

    func testBlocksFilterEveryCollectionAndChartUsesTheSameCategory() {
        let app = launch()
        create("Work item", icon: "briefcase.fill", in: app)
        create("Study item", icon: "book.closed.fill", in: app)
        create("Loose item", in: app)
        expectProgress(0, total: 3, pending: 3, in: app)
        capture(app, "Home - category blocks and two progress bars")
        filter("briefcase.fill", in: app).tap()
        expectProgress(0, total: 1, pending: 1, in: app)
        XCTAssertTrue(app.staticTexts["Work item"].exists)
        XCTAssertFalse(app.staticTexts["Study item"].exists)
        let complete = app.buttons["Complete Work item"]
        XCTAssertTrue(complete.isHittable)
        complete.tap()
        expectProgress(1, total: 1, pending: 0, in: app)
        capture(app, "Category graph - one completed, zero pending")
        app.buttons["task.undoCompletion"].tap()
        expectProgress(0, total: 1, pending: 1, in: app)
        app.buttons["tab.upcoming"].tap()
        XCTAssertTrue(filter("briefcase.fill", in: app).isSelected)
        filter("book.closed.fill", in: app).tap()
        capture(app, "Upcoming - horizontal category blocks")
        app.buttons["tab.today"].tap()
        expectProgress(0, total: 1, pending: 1, in: app)
        XCTAssertTrue(app.staticTexts["Study item"].exists)
        XCTAssertFalse(app.staticTexts["Work item"].exists)
        app.buttons["tab.all"].tap()
        XCTAssertTrue(filter("book.closed.fill", in: app).isSelected)
        XCTAssertTrue(app.staticTexts["Study item"].exists)
        filter("music.note", in: app).tap()
        XCTAssertTrue(app.staticTexts["No matching tasks"].waitForExistence(timeout: 5))
        filter("none", in: app).tap()
        XCTAssertTrue(app.staticTexts["Loose item"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Work item"].exists)
        filter("all", in: app).tap()
        XCTAssertTrue(app.staticTexts["Work item"].exists)
        XCTAssertTrue(app.staticTexts["Study item"].exists)
        capture(app, "All - horizontal category blocks")
    }

    func testInlineCategoryAndEditorBlocksKeepTheSavedChoice() {
        let app = launch(dark: true)
        create("Block editing", icon: "briefcase.fill", in: app)
        app.staticTexts["Block editing"].tap()
        app.buttons["task.iconPicker"].tap()
        XCTAssertTrue(revealCategoryBlock("briefcase.fill", in: app).isSelected)
        capture(app, "Editor - category blocks")
        revealCategoryBlock("heart.fill", in: app).tap()
        let save = app.buttons["task.saveDocument"]
        save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.buttons["tab.all"].tap()
        app.staticTexts["Block editing"].tap()
        XCTAssertEqual(app.buttons["task.iconPicker"].value as? String, "Health")
        app.buttons["task.iconPicker"].tap()
        XCTAssertTrue(revealCategoryBlock("heart.fill", in: app).isSelected)
    }

    func testDarkLargeTextKeepsAllBlocksReachable() {
        let app = launch(dark: true, large: true)
        create("Large chart", icon: "briefcase.fill", in: app)
        expectProgress(0, total: 1, pending: 1, in: app)
        capture(app, "Progress bars - maximum text")
        for tab in ["today", "upcoming", "all"] {
            app.buttons["tab.\(tab)"].tap()
            let music = filter("music.note", in: app)
            XCTAssertGreaterThanOrEqual(music.frame.width, 44)
            XCTAssertGreaterThanOrEqual(music.frame.height, 44)
            music.tap()
            XCTAssertTrue(music.isSelected)
            capture(app, "\(tab) category blocks - Dark maximum text")
            filter("all", in: app).tap()
        }
        app.buttons["task.new"].tap()
        let music = revealCategoryBlock("music.note", in: app)
        music.tap()
        XCTAssertTrue(music.isSelected)
        capture(app, "Inline category blocks - maximum text")
    }
}
