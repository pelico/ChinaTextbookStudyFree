import XCTest

/// Walks the main surfaces and attaches a screenshot of each, so the rendered
/// state can be reviewed from the test report without driving the simulator by
/// hand. Assertions are deliberately light — this is a capture harness.
final class ScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureMainScreens() throws {
        try skipIfIPad()
        let app = XCUIApplication()
        app.launchArguments.append("-uitest")
        app.launch()

        XCTAssertTrue(app.buttons["lesson-row-g1up-u1-kp1"].waitForExistence(timeout: 15),
                      "path home did not render")
        attach(name: "01-home-path")

        // Start popup over the path.
        app.buttons["lesson-row-g1up-u1-kp1"].firstMatch.tap()
        XCTAssertTrue(app.buttons["lesson-start"].waitForExistence(timeout: 5))
        attach(name: "02-start-popup")

        // Lesson runner + feedback panel.
        app.buttons["lesson-start"].tap()
        XCTAssertTrue(app.buttons["检查答案"].waitForExistence(timeout: 8))
        attach(name: "03-lesson-question")

        app.buttons["tf-对"].firstMatch.tap()
        app.buttons["检查答案"].firstMatch.tap()
        XCTAssertTrue(app.buttons["继续"].firstMatch.waitForExistence(timeout: 5))
        attach(name: "04-lesson-feedback")

        // Leave the lesson.
        app.buttons["关闭"].firstMatch.tap()
        app.buttons["退出练习"].firstMatch.tap()
        XCTAssertTrue(app.buttons["tab-review"].waitForExistence(timeout: 8))

        // Secondary tabs.
        app.buttons["tab-review"].tap()
        XCTAssertTrue(app.navigationBars["错题本"].waitForExistence(timeout: 4))
        attach(name: "05-review")

        app.buttons["tab-shop"].tap()
        XCTAssertTrue(app.navigationBars["商店"].waitForExistence(timeout: 4))
        attach(name: "06-shop")

        app.buttons["tab-profile"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 4))
        attach(name: "07-profile")
    }

    @MainActor
    private func attach(name: String) {
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }
}
