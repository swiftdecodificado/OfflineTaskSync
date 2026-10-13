import XCTest

@MainActor
final class HomeProgressUITests: XCTestCase {
    func testProfileAndDetachedCreationKeepTheCurrentCollection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchEnvironment["TASKS_REGRESSION_TEST_HOST"] = "1"
        app.launchEnvironment["TASKS_REGRESSION_STORE_ID"] = UUID().uuidString
        app.launchEnvironment["TASKS_REGRESSION_COLOR_SCHEME"] = "dark"
        app.launchEnvironment["TASKS_REGRESSION_LOCALE"] = "en_US"
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["task.new"].waitForExistence(timeout: 10))
        let navigation = app.otherElements["app.navigation"]
        XCTAssertEqual(navigation.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "tab.")).count, 2)
        XCTAssertFalse(navigation.buttons["task.new"].exists)
        for collection in ["all", "upcoming"] {
            let tab = navigation.buttons["tab.\(collection)"]
            tab.tap()
            if collection == "upcoming" {
                app.buttons["upcoming.options"].tap()
            } else if collection == "all" {
                app.buttons["collection.options"].tap()
            }
            app.buttons["settings.open"].tap()
            XCTAssertTrue(app.textFields["settings.profileName"].waitForExistence(timeout: 5))
            app.buttons["Done"].tap()
            XCTAssertTrue(tab.isSelected)
            let create = app.buttons["task.new"]
            XCTAssertTrue(create.isHittable)
            XCTAssertGreaterThanOrEqual(create.frame.minX, navigation.frame.maxX)
            create.tap()
            let title = app.textFields["task.title"]
            XCTAssertTrue(title.waitForExistence(timeout: 5))
            app.buttons["Close"].tap()
            XCTAssertTrue(title.waitForNonExistence(timeout: 5))
            XCTAssertTrue(tab.isSelected)
        }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Detached creation and profile - English Dark"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
