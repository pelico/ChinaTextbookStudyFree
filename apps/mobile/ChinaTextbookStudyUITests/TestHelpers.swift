import XCTest
import UIKit

extension XCTestCase {
    /// Skip the current test on iPad destinations. Several tests were written
    /// against the iPhone-style single NavigationStack; the iPad
    /// NavigationSplitView has a different back-navigation model and needs
    /// its own coverage in `LayoutUITests`.
    func skipIfIPad() throws {
        if UIDevice.current.userInterfaceIdiom == .pad {
            throw XCTSkip("Test is iPhone-only; iPad layout covered by LayoutUITests")
        }
    }

    /// Wave E2 (content-2)：首次进入带 knowledge 的课会先弹分步讲解。
    /// 需要直达题目的老流程用这个助手翻完讲解（最多 6 页）再继续；
    /// 没弹讲解（已看过 / 无 knowledge）时直接返回。
    @MainActor
    func skipLessonIntroIfPresent(_ app: XCUIApplication) {
        let start = app.buttons["intro-start"]
        let next = app.buttons["intro-next"]
        // 等讲解（任一按钮）出现；3 秒没出现就当没有讲解。
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && !start.exists && !next.exists {
            usleep(200_000)
        }
        for _ in 0..<6 {
            if start.exists { start.tap(); return }
            guard next.exists else { return }
            next.tap()
        }
        if start.exists { start.tap() }
    }
}
