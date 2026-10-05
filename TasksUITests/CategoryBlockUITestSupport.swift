import XCTest

@MainActor
extension XCTestCase {
    func revealCategoryBlock(_ name: String, in app: XCUIApplication,
                             prefix: String = "task.icon.option", stripID: String = "task.icon.options") -> XCUIElement {
        let strips = app.descendants(matching: .any).matching(identifier: stripID)
        let strip = strips.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? strips.firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        let block = app.buttons["\(prefix).\(name)"].firstMatch
        for _ in 0..<12 {
            if block.exists {
                let frame = block.frame
                let bounds = strip.frame
                if block.isHittable, frame.minX >= bounds.minX, frame.maxX <= bounds.maxX { return block }
                if frame.minX < bounds.minX { strip.swipeRight(); continue }
            }
            strip.swipeLeft()
        }
        XCTAssertTrue(block.isHittable)
        return block
    }
}
