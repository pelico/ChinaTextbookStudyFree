import XCTest

/// Covers the earn → spend → express loop: buying a cosmetic must equip it and
/// the equipped state must survive navigating away and back.
final class CosmeticsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uitest")   // hermetic state, 500 gems
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

    @MainActor
    func testBuyingCosmeticEquipsItAndPersists() throws {
        try skipIfIPad()
        let app = launchApp()

        XCTAssertTrue(app.buttons["tab-shop"].waitForExistence(timeout: 15))
        app.buttons["tab-shop"].tap()
        XCTAssertTrue(app.navigationBars["商店"].waitForExistence(timeout: 5))
        attach(name: "01-shop-before")

        // The stock skin starts equipped; the graduation cap costs 80 gems.
        let stock = app.buttons["cosmetic-skin_default"]
        XCTAssertTrue(stock.waitForExistence(timeout: 5))
        XCTAssertTrue(stock.label.contains("使用中"), "stock skin should start equipped")

        let cap = app.buttons["cosmetic-skin_graduate"]
        XCTAssertTrue(cap.waitForExistence(timeout: 3))
        XCTAssertFalse(cap.label.contains("使用中"), "graduation cap should not start equipped")
        cap.tap()

        // Buying equips it immediately.
        XCTAssertTrue(cap.label.contains("使用中"),
                      "buying a skin should equip it — label was: \(cap.label)")
        XCTAssertFalse(stock.label.contains("使用中"),
                       "the previously equipped skin should have been unequipped")
        attach(name: "02-shop-skin-equipped")

        // Buy a theme too (樱花粉, 200 gems) — repaints the brand color app-wide.
        // The shop list is lazy and the theme section sits below the fold
        // (Wave B added the power-up section up top), so scroll until it exists.
        let theme = app.buttons["cosmetic-theme_sakura"]
        var scrolls = 0
        while !theme.exists && scrolls < 6 {
            app.swipeUp()
            scrolls += 1
        }
        XCTAssertTrue(theme.waitForExistence(timeout: 3))
        theme.tap()
        XCTAssertTrue(theme.label.contains("使用中"), "buying a theme should equip it")
        attach(name: "03-shop-theme-equipped")

        // The equipped skin must show on the profile avatar.
        app.buttons["tab-profile"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        attach(name: "04-profile-themed")

        // …and still be equipped when we come back to the shop.
        app.buttons["tab-shop"].tap()
        XCTAssertTrue(app.navigationBars["商店"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["cosmetic-skin_graduate"].label.contains("使用中"),
                      "equipped skin did not persist across tab switches")
    }

    /// A cosmetic you cannot afford must not be granted.
    @MainActor
    func testUnaffordableCosmeticIsNotGranted() throws {
        try skipIfIPad()
        let app = launchApp()

        app.buttons["tab-shop"].tap()
        XCTAssertTrue(app.navigationBars["商店"].waitForExistence(timeout: 5))

        // 宇航员头盔 costs 500; buy 学士帽 (80) first so the balance drops below it.
        app.buttons["cosmetic-skin_graduate"].tap()

        let helmet = app.buttons["cosmetic-skin_astronaut"]
        XCTAssertTrue(helmet.waitForExistence(timeout: 3))
        helmet.tap()
        XCTAssertFalse(helmet.label.contains("使用中"),
                       "an unaffordable cosmetic must not be equipped")
    }
}
