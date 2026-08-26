import XCTest

/// Shell / layout coverage.
/// iPhone runs exercise the compact NavigationStack + bottom tab bar;
/// iPad runs exercise the NavigationSplitView sidebar.
final class LayoutUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp(extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uitest")
        app.launchArguments.append(contentsOf: extraArgs)
        app.launch()
        return app
    }

    @MainActor
    private func attach(name: String) {
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    /// Every tab must be reachable from the bottom bar on compact width.
    @MainActor
    func testBottomTabBarReachesEveryTab() throws {
        try skipIfIPad()
        let app = launchApp()

        XCTAssertTrue(app.buttons["tab-learn"].waitForExistence(timeout: 15),
                      "bottom tab bar did not render")
        attach(name: "shell-launch")

        app.buttons["tab-review"].tap()
        XCTAssertTrue(app.navigationBars["错题本"].waitForExistence(timeout: 4),
                      "review tab did not open 错题本")

        app.buttons["tab-shop"].tap()
        XCTAssertTrue(app.navigationBars["商店"].waitForExistence(timeout: 4),
                      "shop tab did not open 商店")

        app.buttons["tab-profile"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 4),
                      "profile tab did not open 我的")

        // Back to the path.
        app.buttons["tab-learn"].tap()
        XCTAssertTrue(app.buttons["lesson-row-g1up-u1-kp1"].waitForExistence(timeout: 6),
                      "learn tab did not return to the path")
    }

    /// Scroll until the element can actually be tapped — the profile is long
    /// enough that its lower rows start below the fold.
    @MainActor
    private func revealAndTap(_ app: XCUIApplication, _ element: XCUIElement, tries: Int = 6) {
        var attempts = 0
        while !element.isHittable && attempts < tries {
            app.swipeUp()
            attempts += 1
        }
        XCTAssertTrue(element.isHittable, "could not reveal \(element) after \(tries) swipes")
        element.tap()
    }

    /// Profile is the entry point to both the achievement wall and settings.
    @MainActor
    func testProfileReachesAchievementsAndSettings() throws {
        try skipIfIPad()
        let app = launchApp()

        XCTAssertTrue(app.buttons["tab-profile"].waitForExistence(timeout: 15))
        app.buttons["tab-profile"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 4))

        let achievements = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "成就墙")).firstMatch
        XCTAssertTrue(achievements.waitForExistence(timeout: 4))
        revealAndTap(app, achievements)
        XCTAssertTrue(app.navigationBars["成就墙"].waitForExistence(timeout: 4),
                      "profile did not navigate to 成就墙")
        app.navigationBars.buttons.firstMatch.tap()

        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 4))
        let settings = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "设置")).firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 4))
        revealAndTap(app, settings)
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 4),
                      "profile did not navigate to 设置")
    }

    /// Profile surfaces the daily quests and the weekly report.
    @MainActor
    func testProfileShowsQuestsAndWeeklyReport() throws {
        try skipIfIPad()
        let app = launchApp()

        XCTAssertTrue(app.buttons["tab-profile"].waitForExistence(timeout: 15))
        app.buttons["tab-profile"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 4))

        XCTAssertTrue(app.staticTexts["每日任务"].waitForExistence(timeout: 4),
                      "daily quests card missing from profile")
        XCTAssertTrue(app.staticTexts["本周报告"].waitForExistence(timeout: 4),
                      "weekly report card missing from profile")

        // Wave D header: the join date ("加入于 yyyy年M月") must render.
        XCTAssertTrue(app.staticTexts["profile-joined-date"].waitForExistence(timeout: 4),
                      "joined-date line missing from profile header")

        // Fresh state has no progress, so nothing is claimable yet.
        XCTAssertEqual(app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "quest-claim-")
        ).count, 0, "no quest should be claimable at zero progress")
        attach(name: "profile-quests-report")
    }

    /// iPad sidebar exposes the same surfaces as the iPhone tab bar.
    @MainActor
    func testSidebarOnRegularWidth() throws {
        let app = launchApp()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        guard UIDevice.current.userInterfaceIdiom == .pad else {
            // Compact width is covered by the tab-bar test above.
            return
        }

        for label in ["错题本", "商店", "我的", "成就墙"] {
            let cell = app.cells.containing(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
            XCTAssertTrue(cell.waitForExistence(timeout: 4), "sidebar row \(label) not found on iPad")
        }

        app.cells.containing(NSPredicate(format: "label CONTAINS %@", "成就墙")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["成就墙"].waitForExistence(timeout: 4))
        attach(name: "ipad-split-achievements")
    }

    /// The app owns its appearance (light by default), so dark mode is driven by
    /// our own preference key rather than the system style.
    @MainActor
    func testDarkAppearancePreferenceRenders() throws {
        try skipIfIPad()
        // Launch arguments beginning with "-" set NSUserDefaults for this launch.
        let app = launchApp(extraArgs: ["-cstf.appearance", "dark"])

        XCTAssertTrue(app.buttons["lesson-row-g1up-u1-kp1"].waitForExistence(timeout: 15),
                      "path home did not render under the dark appearance preference")
        attach(name: "dark-mode-home")
    }
}
