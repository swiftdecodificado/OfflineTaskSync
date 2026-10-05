import XCTest

@MainActor
final class CategoryPaletteUITests: XCTestCase {
    private func launch(dark: Bool, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
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

    func testLightCategoryPalette() throws {
        try workflow(dark: false)
    }

    func testDarkCategoryPalette() throws {
        try workflow(dark: true)
    }

    private func workflow(dark: Bool) throws {
        let app = launch(dark: dark)
        let appearance = dark ? "Dark" : "Light"
        app.buttons["task.new"].firstMatch.tap()
        let title = app.descendants(matching: .any)["task.newTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["task.create"].isEnabled)
        XCTAssertFalse(app.buttons["task.color.yellow"].exists)
        capture(app, "Disabled action - \(appearance)")
        title.tap()
        title.typeText("Revisar categorias")
        let study = revealCategoryBlock("book.closed.fill", in: app)
        XCTAssertTrue(study.waitForExistence(timeout: 5))
        for symbol in ["dumbbell.fill", "book.closed.fill", "briefcase.fill", "cart.fill", "figure.walk", "heart.fill", "house.fill", "music.note"] {
            XCTAssertTrue(app.buttons["task.icon.option.\(symbol)"].exists)
        }
        capture(app, "Eight category colors - \(appearance)")
        try app.performAccessibilityAudit(for: .contrast)
        study.tap()
        XCTAssertTrue(study.waitForExistence(timeout: 5))
        XCTAssertTrue(study.isSelected)
        capture(app, "Selected category - \(appearance)")
        try app.performAccessibilityAudit(for: .contrast)
        study.tap()
        app.buttons["task.create"].tap()
        XCTAssertTrue(app.buttons["task.new"].firstMatch.waitForExistence(timeout: 5))
        capture(app, "Category on neutral task - \(appearance)")
        try app.performAccessibilityAudit(for: .contrast)
        for tab in ["upcoming", "all"] {
            app.buttons["tab.\(tab)"].tap()
            capture(app, "\(tab) - \(appearance)")
            try app.performAccessibilityAudit(for: .contrast)
        }
        app.staticTexts["Revisar categorias"].firstMatch.tap()
        app.buttons["task.iconPicker"].tap()
        XCTAssertTrue(study.waitForExistence(timeout: 5))
        XCTAssertTrue(study.isSelected)
        let health = revealCategoryBlock("heart.fill", in: app)
        health.tap()
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(app.buttons["task.new"].firstMatch.waitForExistence(timeout: 5))
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].firstMatch.waitForExistence(timeout: 10))
        app.buttons["tab.all"].tap()
        app.staticTexts["Revisar categorias"].firstMatch.tap()
        app.buttons["task.iconPicker"].tap()
        XCTAssertTrue(revealCategoryBlock("heart.fill", in: app).isSelected)
    }

    func testSettingsContrastInBothAppearances() throws {
        for dark in [false, true] {
            let app = launch(dark: dark)
            app.buttons["settings.open"].tap()
            capture(app, dark ? "Settings - Dark" : "Settings - Light")
            try app.performAccessibilityAudit(for: .contrast)
            app.terminate()
        }
    }

    func testLargeTextCategorySelection() throws {
        let app = launch(dark: true, large: true)
        app.buttons["task.new"].firstMatch.tap()
        let study = revealCategoryBlock("book.closed.fill", in: app)
        XCTAssertTrue(study.isHittable)
        capture(app, "Category colors - Accessibility text size")
        study.tap()
        XCTAssertTrue(study.isSelected)
    }
}
