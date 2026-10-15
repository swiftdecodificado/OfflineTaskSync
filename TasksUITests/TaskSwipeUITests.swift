import XCTest

@MainActor
final class TaskSwipeUITests: XCTestCase {
    private func launch(portuguese: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = portuguese ? "dark" : "light"
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = portuguese ? "pt_BR" : "en_US"
        app.launchArguments += ["-AppleLanguages", portuguese ? "(pt-BR)" : "(en)", "-AppleLocale", portuguese ? "pt_BR" : "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        return app
    }

    private func create(_ title: String, in app: XCUIApplication) {
        app.buttons["task.new"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "task.newTitle").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.typeText(title)
        app.buttons["task.create"].tap()
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 10))
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = name
        image.lifetime = .keepAlways
        add(image)
    }

    func testNativeSwipeUpdatesChartEditsDeadlineAndTask() throws {
        let app = launch()
        create("Read a chapter", in: app)
        create("Write a note", in: app)
        let row = app.cells.containing(.button, identifier: "Complete Read a chapter").firstMatch
        row.swipeRight()
        XCTAssertTrue(app.buttons["Complete"].waitForExistence(timeout: 5))
        capture(app, "Light - native complete swipe")
        app.buttons["Complete"].tap()
        let progress = app.descendants(matching: .any).matching(identifier: "home.progress").firstMatch
        let half = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Completed 1 of 2"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [half], timeout: 5), .completed)
        capture(app, "Light - Swift Charts half-complete progress")
        let completedRow = app.cells.containing(.button, identifier: "Reopen Read a chapter").firstMatch
        completedRow.swipeRight()
        XCTAssertTrue(app.buttons["Reopen"].waitForExistence(timeout: 5))
        app.buttons["Reopen"].tap()
        row.swipeLeft()
        XCTAssertTrue(app.buttons["task.swipe.deadline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["task.swipe.edit"].exists)
        XCTAssertFalse(app.buttons["task.swipe.delete"].exists)
        capture(app, "Light - native deadline and edit swipe")
        app.buttons["task.swipe.deadline"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["Deadline"].exists)
        app.buttons["Done"].tap()
        row.swipeLeft()
        app.buttons["task.swipe.edit"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.title").firstMatch.waitForExistence(timeout: 5))
        capture(app, "Light - edit from native swipe")
    }

    func testNativeSwipeInAllAndCompletedCollections() {
        let app = launch()
        create("Check the filtered lists", in: app)
        let navigation = app.otherElements["app.navigation"]
        navigation.buttons["All"].tap()
        let pending = app.cells.containing(.button, identifier: "Complete Check the filtered lists").firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        pending.swipeRight()
        app.buttons["Complete"].tap()
        XCTAssertTrue(app.staticTexts["No tasks here"].waitForExistence(timeout: 5))
        app.buttons["tab.all"].tap()
        app.segmentedControls.buttons["Completed"].tap()
        let completed = app.cells.containing(.button, identifier: "Reopen Check the filtered lists").firstMatch
        XCTAssertTrue(completed.waitForExistence(timeout: 5))
        completed.swipeRight()
        app.buttons["Reopen"].tap()
        XCTAssertTrue(app.staticTexts["No tasks here"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Active"].tap()
        XCTAssertTrue(app.staticTexts["Check the filtered lists"].waitForExistence(timeout: 5))
    }

    func testPortugueseDarkSwipeAndChart() {
        let app = launch(portuguese: true)
        create("Revisar o plano", in: app)
        create("Preparar a entrega", in: app)
        let row = app.cells.containing(.button, identifier: "Concluir Revisar o plano").firstMatch
        row.swipeRight()
        XCTAssertTrue(app.buttons["Concluir"].waitForExistence(timeout: 5))
        capture(app, "Portuguese Dark - complete swipe")
        app.buttons["Concluir"].tap()
        let progress = app.descendants(matching: .any).matching(identifier: "home.progress").firstMatch
        let half = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "Concluídas: 1 de 2"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [half], timeout: 5), .completed)
        capture(app, "Portuguese Dark - Swift Charts progress")
        let completedRow = app.cells.containing(.button, identifier: "Reabrir Revisar o plano").firstMatch
        completedRow.swipeLeft()
        XCTAssertTrue(app.buttons["task.swipe.deadline"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["task.swipe.edit"].exists)
        XCTAssertEqual(app.buttons["task.swipe.deadline"].label, "Alterar prazo")
        XCTAssertEqual(app.buttons["task.swipe.edit"].label, "Editar tarefa")
        capture(app, "Portuguese Dark - deadline and edit swipe")
        app.buttons["task.swipe.edit"].tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "task.title").firstMatch.waitForExistence(timeout: 5))
    }
}
