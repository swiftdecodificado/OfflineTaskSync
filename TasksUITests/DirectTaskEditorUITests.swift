import XCTest

@MainActor
final class DirectTaskEditorUITests: XCTestCase {
    func testCreateDirectlyInFullEditorWithGroupedTools() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = "pt_BR"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = "light"
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        app.buttons["task.new"].tap()
        let title = app.textFields["task.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["task.newTitle"].exists)
        XCTAssertFalse(app.buttons["task.openFullEditor"].exists)
        title.typeText("Planejar a entrega")
        app.buttons["task.iconPicker"].tap()
        let category = app.buttons["task.icon.option.book.closed.fill"]
        XCTAssertTrue(category.waitForExistence(timeout: 5))
        let categoryName = category.label
        category.tap()
        XCTAssertTrue(category.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["task.iconPicker"].value as? String, categoryName)
        app.buttons["task.editor.date"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.buttons["task.property.cancel"].tap()
        app.buttons["task.editor.time"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.buttons["task.property.cancel"].tap()
        let calendar = app.buttons["task.editor.calendar"]
        calendar.tap()
        XCTAssertEqual(calendar.label, "Não adicionar ao calendário")
        XCTAssertFalse(app.descendants(matching: .any)["task.editor.calendarPanel"].exists)
        calendar.tap()
        XCTAssertEqual(calendar.label, "Adicionar ao calendário")
        app.buttons["task.editor.reminder"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.buttons["task.property.cancel"].tap()
        app.buttons["task.editor.attachments"].tap()
        XCTAssertTrue(app.buttons["Adicionar foto"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Adicionar vídeo"].exists)
        XCTAssertTrue(app.buttons["Adicionar arquivo"].exists)
        app.buttons["Inserir link"].tap()
        app.alerts.firstMatch.buttons["Cancelar"].tap()
        let document = app.textViews["task.document"]
        document.tap()
        document.typeText("Revisar os arquivos.")
        capture(app, "Full editor - direct creation and grouped keyboard tools")
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Planejar a entrega"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Revisar os arquivos."].exists)
        capture(app, "Home - task saved from the full editor")
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.open.", "Planejar a entrega")).firstMatch.tap()
        let readingTitle = app.staticTexts["task.readTitle"]
        XCTAssertTrue(readingTitle.waitForExistence(timeout: 5))
        XCTAssertEqual(readingTitle.label, "Planejar a entrega")
        XCTAssertFalse(title.exists)
        XCTAssertFalse(app.buttons["task.saveDocument"].exists)
        XCTAssertTrue((document.value as? String)?.contains("Revisar os arquivos.") == true)
        document.tap()
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        capture(app, "Saved task - read only")
        app.buttons["task.editDocument"].tap()
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Planejar a entrega")
        XCTAssertEqual(app.buttons["task.iconPicker"].value as? String, categoryName)
        title.typeText(" revisada")
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Planejar a entrega revisada"].waitForExistence(timeout: 5))
        capture(app, "Home - task changed only after choosing Edit")
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
