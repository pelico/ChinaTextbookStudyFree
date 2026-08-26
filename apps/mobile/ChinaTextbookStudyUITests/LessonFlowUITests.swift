import XCTest

/// End-to-end smoke test of the core learning loop against the bundled g1up seed:
///   path home → tap node → start popup → lesson runner → answer → feedback.
final class LessonFlowUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launch in the hermetic UI-test state (no onboarding, seed book active).
    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("-uitest")
        app.launch()
        return app
    }

    /// The path *is* the home screen — the first seed lesson node must be there.
    @MainActor
    private func firstNode(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["lesson-row-g1up-u1-kp1"].firstMatch
    }

    @MainActor
    func testPathHomeOpensLessonViaStartPopup() throws {
        try skipIfIPad()
        let app = launchApp()

        let node = firstNode(app)
        XCTAssertTrue(node.waitForExistence(timeout: 15),
                      "current lesson node not found — the path home did not render")
        node.tap()

        // Tapping a node opens the anchored start popup rather than the lesson.
        let start = app.buttons["lesson-start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5),
                      "start popup did not appear after tapping a path node")
        start.tap()

        // Wave E2：首次进课先弹分步知识讲解，翻完才是题目。
        skipLessonIntroIfPresent(app)

        // Lesson runner chrome: check button, close button, question TTS.
        XCTAssertTrue(app.buttons["检查答案"].waitForExistence(timeout: 8),
                      "lesson runner did not render the check button")
        XCTAssertTrue(app.buttons["关闭"].firstMatch.waitForExistence(timeout: 2),
                      "close button missing from the lesson header")
        XCTAssertTrue(app.buttons["tts-play"].firstMatch.waitForExistence(timeout: 2),
                      "TTSButton not visible — seed audio missing or path resolution broken")
    }

    /// Wave E2 (content-2)：首次进课先弹分步知识讲解，翻完（或单页直接）
    /// 「开始做题」后才见到题目；讲解看过一次后不再重复打断。
    @MainActor
    func testKnowledgeIntroShowsOnceBeforeFirstRun() throws {
        try skipIfIPad()
        let app = launchApp()

        XCTAssertTrue(firstNode(app).waitForExistence(timeout: 15))
        firstNode(app).tap()
        XCTAssertTrue(app.buttons["lesson-start"].waitForExistence(timeout: 5))
        app.buttons["lesson-start"].tap()

        // g1up-u1-kp1 自带 knowledge → 讲解必须先出现。
        let start = app.buttons["intro-start"]
        let next = app.buttons["intro-next"]
        XCTAssertTrue(start.waitForExistence(timeout: 5) || next.exists,
                      "knowledge intro did not appear before the first run")
        skipLessonIntroIfPresent(app)
        XCTAssertTrue(app.buttons["检查答案"].waitForExistence(timeout: 8),
                      "intro CTA did not hand over to the question runner")

        // 退出（零进度直接回路径），再进同一课：讲解不再打断。
        app.buttons["关闭"].firstMatch.tap()
        XCTAssertTrue(firstNode(app).waitForExistence(timeout: 8))
        firstNode(app).tap()
        XCTAssertTrue(app.buttons["lesson-start"].waitForExistence(timeout: 5))
        app.buttons["lesson-start"].tap()
        XCTAssertTrue(app.buttons["检查答案"].waitForExistence(timeout: 8),
                      "a seen intro must not interrupt the lesson again")
        XCTAssertFalse(app.buttons["intro-start"].exists)
        XCTAssertFalse(app.buttons["intro-next"].exists)
    }

    /// Answering correctly must surface the feedback panel.
    @MainActor
    func testAnsweringShowsFeedbackPanel() throws {
        try skipIfIPad()
        let app = launchApp()

        XCTAssertTrue(firstNode(app).waitForExistence(timeout: 15))
        firstNode(app).tap()
        XCTAssertTrue(app.buttons["lesson-start"].waitForExistence(timeout: 5))
        app.buttons["lesson-start"].tap()
        skipLessonIntroIfPresent(app)
        XCTAssertTrue(app.buttons["检查答案"].waitForExistence(timeout: 8))

        // g1up-u1-kp1 opens with a true/false question whose answer is 对.
        let yes = app.buttons["tf-对"].firstMatch
        XCTAssertTrue(yes.waitForExistence(timeout: 3), "true/false tile not found")
        yes.tap()
        app.buttons["检查答案"].firstMatch.tap()

        // The feedback panel replaces the check footer with a continue CTA.
        XCTAssertTrue(app.buttons["继续"].firstMatch.waitForExistence(timeout: 5),
                      "feedback panel did not appear after checking a correct answer")
    }

    /// Quitting mid-lesson must show the custom hold-on overlay (mascot +
    /// 「继续学习」 on top, ghost 「退出」) before discarding progress.
    @MainActor
    func testQuittingMidLessonAsksForConfirmation() throws {
        try skipIfIPad()
        let app = launchApp()

        XCTAssertTrue(firstNode(app).waitForExistence(timeout: 15))
        firstNode(app).tap()
        XCTAssertTrue(app.buttons["lesson-start"].waitForExistence(timeout: 5))
        app.buttons["lesson-start"].tap()
        skipLessonIntroIfPresent(app)
        XCTAssertTrue(app.buttons["检查答案"].waitForExistence(timeout: 8))

        // Answer once so there is progress worth protecting.
        app.buttons["tf-对"].firstMatch.tap()
        app.buttons["检查答案"].firstMatch.tap()
        XCTAssertTrue(app.buttons["继续"].firstMatch.waitForExistence(timeout: 5))

        app.buttons["关闭"].firstMatch.tap()
        XCTAssertTrue(app.buttons["lesson-quit"].firstMatch.waitForExistence(timeout: 3),
                      "quit hold-on overlay did not appear")
        // The keep-learning CTA sits on top of the overlay.
        XCTAssertTrue(app.buttons["继续学习"].firstMatch.exists,
                      "keep-learning CTA missing from the quit overlay")
        app.buttons["lesson-quit"].firstMatch.tap()

        // Back on the path.
        XCTAssertTrue(firstNode(app).waitForExistence(timeout: 8),
                      "did not return to the path home after quitting")
    }

    /// With zero progress (no question answered) closing must exit directly —
    /// no hold-on overlay.
    @MainActor
    func testQuittingWithZeroProgressExitsDirectly() throws {
        try skipIfIPad()
        let app = launchApp()

        XCTAssertTrue(firstNode(app).waitForExistence(timeout: 15))
        firstNode(app).tap()
        XCTAssertTrue(app.buttons["lesson-start"].waitForExistence(timeout: 5))
        app.buttons["lesson-start"].tap()
        skipLessonIntroIfPresent(app)
        XCTAssertTrue(app.buttons["检查答案"].waitForExistence(timeout: 8))

        app.buttons["关闭"].firstMatch.tap()
        XCTAssertTrue(firstNode(app).waitForExistence(timeout: 8),
                      "zero-progress close should return straight to the path")
        XCTAssertFalse(app.buttons["lesson-quit"].exists,
                       "quit overlay must not appear when nothing was answered")
    }
}
