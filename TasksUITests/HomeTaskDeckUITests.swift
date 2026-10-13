import XCTest

@MainActor
final class HomeTaskDeckUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["TASKS_REPLACE_WITH_SAMPLE_DATA"] = UUID().uuidString
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = "pt_BR"
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["tasks.focus.today"].waitForExistence(timeout: 5))
        app.buttons["tasks.focus.today"].tap()
        XCTAssertTrue(app.buttons["Concluir Revisar o projeto"].waitForExistence(timeout: 5))
        return app
    }

    private func task(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.open.", title)).firstMatch
    }

    func testAnyTaskOpensWithoutCompletingTheFirst() {
        let app = launch()
        task("Estudar Swift", in: app).tap()
        let title = app.staticTexts["task.readTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Estudar Swift")
        app.buttons["Fechar"].tap()
        XCTAssertTrue(app.buttons["Concluir Revisar o projeto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Concluir Estudar Swift"].exists)
    }

    func testCompletionAndUndoPreserveTheOtherTasks() {
        let app = launch()
        let complete = app.buttons["Concluir Revisar o projeto"]
        complete.tap()
        XCTAssertTrue(complete.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Concluir Estudar Swift"].exists)
        XCTAssertTrue(app.buttons["task.undoCompletion"].waitForExistence(timeout: 5))
        app.buttons["task.undoCompletion"].tap()
        XCTAssertTrue(complete.waitForExistence(timeout: 10))
    }
}
