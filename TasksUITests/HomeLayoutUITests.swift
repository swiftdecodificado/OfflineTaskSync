import XCTest

@MainActor
final class HomeLayoutUITests: XCTestCase {
    private func launch(portuguese: Bool, dark: Bool, large: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = portuguese ? "pt_BR" : "en_US"
        app.launchArguments += ["-AppleLanguages", portuguese ? "(pt-BR)" : "(en)", "-AppleLocale", portuguese ? "pt_BR" : "en_US"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["home.options"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["upcoming.chooseDate"].exists)
        XCTAssertTrue(app.buttons["task.new"].isHittable)
        let navigation = app.otherElements["app.navigation"]
        let create = app.buttons["task.new"]
        XCTAssertTrue(navigation.buttons["settings.open"].isHittable)
        XCTAssertFalse(navigation.buttons["task.new"].exists)
        XCTAssertGreaterThanOrEqual(create.frame.width, 56)
        XCTAssertGreaterThanOrEqual(create.frame.height, 56)
        XCTAssertGreaterThanOrEqual(create.frame.minX, navigation.frame.maxX)
        XCTAssertLessThanOrEqual(create.frame.maxX, app.frame.maxX)
        for greeting in ["Good morning", "Good afternoon", "Good evening", "Bom dia", "Boa tarde", "Boa noite"] {
            XCTAssertFalse(app.staticTexts[greeting].exists)
        }
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func create(_ title: String, in app: XCUIApplication) {
        app.buttons["task.new"].tap()
        let field = app.descendants(matching: .any)["task.newTitle"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText(title)
        app.buttons["task.create"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 10))
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<10 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable)
    }

    func testEnglishLightTodayCompletionAndUndo() {
        let app = launch(portuguese: false, dark: false)
        XCTAssertFalse(app.descendants(matching: .any)["home.progress"].exists)
        capture(app, "Today - English Light - empty")
        create("Review the release", in: app)
        let task = app.buttons["Complete Review the release"]
        reveal(task, in: app)
        XCTAssertTrue(app.descendants(matching: .any)["home.progress"].exists)
        capture(app, "Today - English Light - tasks and discreet progress")
        task.tap()
        XCTAssertTrue(app.buttons["task.undoCompletion"].waitForExistence(timeout: 5))
        app.buttons["task.undoCompletion"].tap()
        reveal(task, in: app)
    }

    func testPortugueseDarkTodayAndSecondaryActions() {
        let app = launch(portuguese: true, dark: true)
        app.buttons["home.options"].tap()
        app.buttons["home.reminders"].tap()
        XCTAssertTrue(app.staticTexts["Nenhum lembrete"].waitForExistence(timeout: 5))
        app.buttons["Fechar"].tap()
        create("Revisar a entrega", in: app)
        reveal(app.buttons["Concluir Revisar a entrega"], in: app)
        capture(app, "Today - Portuguese Dark - tasks")
    }

    func testMaximumDynamicTypeKeepsTaskAndCreationReachable() {
        let app = launch(portuguese: true, dark: false, large: true)
        create("Revisar os detalhes da entrega com a equipe", in: app)
        reveal(app.buttons["Concluir Revisar os detalhes da entrega com a equipe"], in: app)
        capture(app, "Today - maximum Dynamic Type - readable task")
        XCTAssertTrue(app.buttons["task.new"].isHittable)
    }
}
