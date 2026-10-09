import XCTest

@MainActor
final class AllTasksLayoutUITests: XCTestCase {
    private func launch(dark: Bool = false, large: Bool = false, samples: Bool = true, pending: Bool = false) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = "pt_BR"
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = dark ? "dark" : "light"
        if samples { app.launchEnvironment["TASKS_REPLACE_WITH_SAMPLE_DATA"] = UUID().uuidString }
        app.launchArguments += ["-AppleLanguages", "(pt-BR)", "-AppleLocale", "pt_BR"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        app.launch()
        XCTAssertTrue(app.buttons["tab.all"].waitForExistence(timeout: 15))
        app.buttons["tab.all"].tap()
        XCTAssertTrue(app.textFields["tasks.search"].waitForExistence(timeout: 5))
        if pending { app.segmentedControls["tasks.status"].buttons["Pendentes"].tap() }
        return app
    }

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let navigation = app.otherElements["app.navigation"]
        for _ in 0..<15 {
            if element.isHittable, element.frame.maxY <= navigation.frame.minY { break }
            app.swipeUp()
        }
        XCTAssertTrue(element.isHittable)
        XCTAssertLessThanOrEqual(element.frame.maxY, navigation.frame.minY + 0.5)
    }

    private func chooseCategory(_ id: String, in app: XCUIApplication) {
        app.buttons["tasks.filters"].tap()
        XCTAssertTrue(app.buttons["tasks.filters.done"].waitForExistence(timeout: 5))
        let category = app.buttons["tasks.category.\(id)"]
        for _ in 0..<10 where !category.isHittable { app.swipeUp() }
        category.tap()
        app.buttons["tasks.filters.done"].tap()
        XCTAssertTrue(app.buttons["tasks.filters.done"].waitForNonExistence(timeout: 5))
    }

    private func row(_ title: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.open.", title)).firstMatch
    }

    func testLightListStartsWithTasksAndConsistentCompletionControls() {
        let app = launch()
        XCTAssertTrue(app.segmentedControls["tasks.status"].buttons["Todas"].isSelected)
        XCTAssertTrue(app.buttons["Reabrir Caminhada da manhã"].exists)
        XCTAssertFalse(app.otherElements["tasks.categoryFilter"].exists)
        XCTAssertFalse(app.buttons["tasks.section.book.closed.fill"].exists)
        XCTAssertTrue(row("Revisar o projeto", in: app).isHittable)
        XCTAssertTrue(app.buttons["Concluir Estudar Swift"].isHittable)
        XCTAssertFalse(app.staticTexts["Conferir as entregas e anotar os próximos passos."].exists)
        capture(app, "All tasks - Light - direct list")
        app.segmentedControls["tasks.status"].buttons["Pendentes"].tap()
        app.buttons["Concluir Revisar o projeto"].tap()
        XCTAssertTrue(row("Revisar o projeto", in: app).waitForNonExistence(timeout: 10))
        app.buttons["task.undoCompletion"].tap()
        XCTAssertTrue(row("Revisar o projeto", in: app).waitForExistence(timeout: 10))
    }

    func testClearingCategoryFiltersPreservesSearchAndStatus() {
        let app = launch(dark: true, pending: true)
        let search = app.textFields["tasks.search"]
        search.tap()
        search.typeText("projeto")
        chooseCategory("book.closed.fill", in: app)
        XCTAssertTrue(app.buttons["tasks.clearCategory"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tasks.clearFilters"].exists)
        XCTAssertFalse(row("Revisar o projeto", in: app).exists)
        capture(app, "All tasks - Dark - active filter and no results")
        app.buttons["tasks.clearFilters"].tap()
        XCTAssertEqual(search.value as? String, "projeto")
        XCTAssertTrue(app.segmentedControls["tasks.status"].buttons["Pendentes"].isSelected)
        XCTAssertTrue(row("Revisar o projeto", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tasks.clearCategory"].exists)
        app.buttons["tasks.clearSearch"].tap()
        XCTAssertTrue(row("Estudar Swift", in: app).exists)
        capture(app, "All tasks - Dark - filters and search cleared separately")
    }

    func testSearchCanExpandToCompletedTasksAndShowTheMatchingNotes() {
        let app = launch(pending: true)
        app.textFields["tasks.search"].tap()
        app.textFields["tasks.search"].typeText("água")
        let all = app.buttons["tasks.searchAll"]
        reveal(all, in: app)
        all.tap()
        XCTAssertTrue(app.segmentedControls["tasks.status"].buttons["Todas"].isSelected)
        XCTAssertTrue(row("Caminhada da manhã", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "task.notes.", "água")).firstMatch.exists)
        capture(app, "All tasks - matching notes in a completed task")
    }

    func testCompletedEmptyStateAndNewTaskCreationHaveDifferentActions() {
        let app = launch(samples: false)
        app.segmentedControls["tasks.status"].buttons["Concluídas"].tap()
        XCTAssertTrue(app.staticTexts["Nenhuma tarefa concluída ainda"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tasks.empty.create"].exists)
        capture(app, "All tasks - completed empty state")
        app.segmentedControls["tasks.status"].buttons["Pendentes"].tap()
        app.buttons["tasks.empty.create"].tap()
        let title = app.textFields["task.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Preparar a entrega")
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(row("Preparar a entrega", in: app).waitForExistence(timeout: 5))
        app.buttons["Concluir Preparar a entrega"].tap()
        XCTAssertTrue(row("Preparar a entrega", in: app).waitForNonExistence(timeout: 10))
        app.segmentedControls["tasks.status"].buttons["Concluídas"].tap()
        XCTAssertTrue(app.buttons["Reabrir Preparar a entrega"].waitForExistence(timeout: 5))
        app.buttons["Reabrir Preparar a entrega"].tap()
        XCTAssertTrue(app.staticTexts["Nenhuma tarefa concluída ainda"].waitForExistence(timeout: 5))
    }

    func testDeadlineFilterCanBeRemovedWithoutOpeningTheSheetAgain() {
        let app = launch()
        app.buttons["tasks.filters"].tap()
        let undated = app.buttons["Sem prazo"]
        for _ in 0..<12 where !undated.isHittable { app.swipeUp() }
        XCTAssertTrue(undated.isHittable)
        undated.tap()
        app.buttons["tasks.filters.done"].tap()
        let clear = app.buttons["tasks.clearDeadline"]
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        XCTAssertFalse(row("Revisar o projeto", in: app).exists)
        clear.tap()
        XCTAssertTrue(row("Revisar o projeto", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(clear.exists)
    }

    func testFilteredCreationKeepsTheSelectedCategory() {
        let app = launch(samples: false)
        chooseCategory("book.closed.fill", in: app)
        app.buttons["task.new"].tap()
        let title = app.textFields["task.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["task.iconPicker"].value as? String, "Estudos")
        title.tap()
        title.typeText("Praticar Swift")
        app.buttons["task.saveDocument"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 10))
        XCTAssertTrue(row("Praticar Swift", in: app).waitForExistence(timeout: 5))
    }

    func testMaximumTextKeepsFiltersAndTasksReachable() {
        let app = launch(large: true)
        XCTAssertTrue(app.buttons["tasks.filters"].isHittable)
        XCTAssertTrue(app.segmentedControls["tasks.status"].buttons["Concluídas"].isHittable)
        reveal(app.buttons["Concluir Estudar Swift"], in: app)
        XCTAssertTrue(app.buttons["task.new"].isHittable)
        capture(app, "All tasks - maximum text - readable list")
    }

    func testTaskActionsKeepDeadlineEditingAndDeletionAvailable() {
        let app = launch()
        let task = row("Revisar o projeto", in: app)
        task.swipeLeft()
        app.buttons["task.swipe.deadline"].tap()
        XCTAssertTrue(app.datePickers.firstMatch.waitForExistence(timeout: 5))
        app.buttons["Concluído"].tap()
        task.swipeLeft()
        app.buttons["task.swipe.edit"].tap()
        let title = app.textFields["task.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertEqual(title.value as? String, "Revisar o projeto")
        app.buttons["Fechar"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        task.press(forDuration: 1.2)
        app.buttons["Excluir tarefa"].tap()
        let alert = app.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancelar"].tap()
        XCTAssertTrue(task.exists)
        task.press(forDuration: 1.2)
        app.buttons["Excluir tarefa"].tap()
        alert.buttons["Excluir tarefa"].tap()
        XCTAssertTrue(task.waitForNonExistence(timeout: 10))
        XCTAssertTrue(row("Estudar Swift", in: app).exists)
    }

    func testExportStillOpensTheNativeShareSheet() {
        let app = launch()
        app.buttons["collection.options"].tap()
        app.buttons["Exportar tarefas"].tap()
        let share = app.buttons["Compartilhar JSON"]
        XCTAssertTrue(share.waitForExistence(timeout: 10))
        share.tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 10)
                      || app.buttons["Copy"].exists || app.buttons["Copiar"].exists
                      || app.buttons["Save to Files"].exists)
        capture(app, "All tasks - native JSON sharing")
    }

    func testSortMenuChangesTheVisibleOrder() {
        let app = launch()
        app.buttons["collection.options"].tap()
        app.buttons["tasks.sort"].tap()
        app.buttons["Título"].tap()
        let shopping = row("Comprar frutas", in: app)
        let study = row("Estudar Swift", in: app)
        XCTAssertTrue(shopping.waitForExistence(timeout: 5))
        XCTAssertLessThan(shopping.frame.minY, study.frame.minY)
        capture(app, "All tasks - title ordering")
        app.buttons["collection.options"].tap()
        app.buttons["tasks.sort"].tap()
        app.buttons["Prazo"].tap()
        XCTAssertLessThan(row("Revisar o projeto", in: app).frame.minY, shopping.frame.minY)
    }

    func testOptionalCategoryGroupingDoesNotHideSearchResults() {
        let app = launch(dark: true)
        app.buttons["collection.options"].tap()
        app.buttons["tasks.grouping"].tap()
        app.buttons["Por categoria"].tap()
        XCTAssertTrue(app.buttons["tasks.section.book.closed.fill"].waitForExistence(timeout: 5))
        let search = app.textFields["tasks.search"]
        search.tap()
        search.typeText("Swift")
        XCTAssertTrue(row("Estudar Swift", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tasks.section.book.closed.fill"].exists)
        capture(app, "All tasks - direct search with grouping enabled")
    }
}
