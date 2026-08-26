import XCTest
@testable import ChinaTextbookStudy

// MARK: - Streak (pure domain)

final class StreakTests: XCTestCase {
    func testSameDayNoChange() {
        let adv = Streak.advance(streak: 4, streakFreezes: 2, lastActiveDate: "2026-03-02", today: "2026-03-02")
        XCTAssertEqual(adv, Streak.Advance(streak: 4, streakFreezes: 2, lastActiveDate: "2026-03-02", freezesConsumed: 0))
    }

    func testFirstEverStartsAtOne() {
        let adv = Streak.advance(streak: 0, streakFreezes: 0, lastActiveDate: "", today: "2026-03-02")
        XCTAssertEqual(adv.streak, 1)
        XCTAssertEqual(adv.lastActiveDate, "2026-03-02")
    }

    func testConsecutiveDayIncrements() {
        // 2026-03-03 is a Tuesday — no Monday top-up in play.
        let adv = Streak.advance(streak: 4, streakFreezes: 1, lastActiveDate: "2026-03-02", today: "2026-03-03")
        XCTAssertEqual(adv.streak, 5)
        XCTAssertEqual(adv.streakFreezes, 1)
        XCTAssertEqual(adv.freezesConsumed, 0)
    }

    func testMondayTopUpOnConsecutiveDay() {
        // 2026-03-02 is a Monday: a gap-1 advance refills one shield slot.
        let adv = Streak.advance(streak: 4, streakFreezes: 1, lastActiveDate: "2026-03-01", today: "2026-03-02")
        XCTAssertEqual(adv.streak, 5)
        XCTAssertEqual(adv.streakFreezes, 2)
        XCTAssertEqual(adv.freezesConsumed, 0)
    }

    func testMondayTopUpCapsAtMax() {
        let adv = Streak.advance(streak: 4, streakFreezes: 2, lastActiveDate: "2026-03-01", today: "2026-03-02")
        XCTAssertEqual(adv.streakFreezes, 2)
    }

    func testMondayTopUpOnlyAppliesToGapOne() {
        // Monday 2026-03-02 with a 2-day gap: shields are consumed, not topped.
        let adv = Streak.advance(streak: 4, streakFreezes: 1, lastActiveDate: "2026-02-28", today: "2026-03-02")
        XCTAssertEqual(adv.streak, 5)
        XCTAssertEqual(adv.streakFreezes, 0)
        XCTAssertEqual(adv.freezesConsumed, 1)
    }

    func testGapResetsWithoutFreezes() {
        let adv = Streak.advance(streak: 9, streakFreezes: 0, lastActiveDate: "2026-03-01", today: "2026-03-03")
        XCTAssertEqual(adv.streak, 1)
        XCTAssertEqual(adv.lastActiveDate, "2026-03-03")
    }

    func testFreezesCoverMissedDays() {
        // Missed 03-02 and 03-03 (gap 3) with 2 shields banked.
        let adv = Streak.advance(streak: 5, streakFreezes: 2, lastActiveDate: "2026-03-01", today: "2026-03-04")
        XCTAssertEqual(adv.streak, 6)
        XCTAssertEqual(adv.streakFreezes, 0)
        XCTAssertEqual(adv.freezesConsumed, 2)
    }

    func testInsufficientFreezesResetKeepsShields() {
        // Web keeps the (insufficient) shields when the streak resets; mirror that.
        let adv = Streak.advance(streak: 5, streakFreezes: 1, lastActiveDate: "2026-03-01", today: "2026-03-04")
        XCTAssertEqual(adv.streak, 1)
        XCTAssertEqual(adv.streakFreezes, 1)
        XCTAssertEqual(adv.freezesConsumed, 0)
    }

    func testUnparseableDateResets() {
        let adv = Streak.advance(streak: 5, streakFreezes: 3, lastActiveDate: "garbage", today: "2026-03-04")
        XCTAssertEqual(adv.streak, 1)
        XCTAssertEqual(adv.streakFreezes, 3)
    }
}

// MARK: - Outline → path lesson metas → chest slots

final class PathLessonMetasTests: XCTestCase {
    private func outline(kpCount: Int) -> Outline {
        Outline(textbook: "T", units: [
            Unit(unitNumber: 1, title: "U1", knowledgePoints: (1...kpCount).map {
                KnowledgePoint(name: "kp\($0)", description: "", difficulty: 1, questionTypes: [])
            }),
        ])
    }

    func testMetasUseDataLoaderLessonIdConvention() {
        let metas = outline(kpCount: 3).pathLessonMetas(bookId: "g1up")
        XCTAssertEqual(metas.map(\.id), ["g1up-u1-kp1", "g1up-u1-kp2", "g1up-u1-kp3"])
        XCTAssertEqual(metas[0].unitTitle, "U1")
    }

    func testChestAfterFifthLessonOnly() {
        let metas = outline(kpCount: 6).pathLessonMetas(bookId: "g1up")
        XCTAssertNil(Chest.chestAfter(bookId: "g1up", lessons: metas, lessonId: "g1up-u1-kp4"))
        XCTAssertEqual(
            Chest.chestAfter(bookId: "g1up", lessons: metas, lessonId: "g1up-u1-kp5")?.id,
            "g1up-u1-chest-0"
        )
    }
}

// MARK: - ProgressStore economy (streak freeze / review counting / gem drip)

@MainActor
final class ProgressStoreEconomyTests: XCTestCase {
    private var savedProgress: Data?
    private var savedPrefs: Data?
    private var store: ProgressStore!

    override func setUp() async throws {
        // The store persists to real files under Application Support/cstf/ —
        // stash whatever is there and restore it in tearDown.
        savedProgress = try? Data(contentsOf: PersistenceService.url(for: "progress.json"))
        savedPrefs = try? Data(contentsOf: PersistenceService.url(for: "prefs.json"))
        store = ProgressStore()
        store.resetProgress()
    }

    override func tearDown() async throws {
        for (name, data) in [("progress.json", savedProgress), ("prefs.json", savedPrefs)] {
            let url = PersistenceService.url(for: name)
            if let data { try? data.write(to: url) } else { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func day(_ s: String) -> Date { SRS.dateFormatter.date(from: s)! }

    func testStreakFreezeIsConsumedOnMissedDay() {
        // Wave B baseline: a fresh save starts with 2 shields.
        XCTAssertEqual(store.streakFreezes, 2)

        store.completeLesson(lessonId: "t-l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(store.progress.streak, 1)

        // Miss 03-03 entirely; one shield keeps the streak alive.
        store.completeLesson(lessonId: "t-l2", correctCount: 5, questionCount: 5, now: day("2026-03-04"))
        XCTAssertEqual(store.progress.streak, 2)
        XCTAssertEqual(store.streakFreezes, 1)
    }

    func testAllWrongReviewSessionStillCounts() {
        store.awardReviewXP(0, reviewedCount: 3, now: day("2026-03-02"))
        XCTAssertEqual(store.progress.dailyReviews, 3)
        XCTAssertEqual(store.progress.streak, 1)
        XCTAssertEqual(store.progress.xp, 0)
    }

    func testLessonXpMatchesUnifiedFormula() {
        // Weekday (Mon 2026-03-02), 4/5 first-try correct: 4 × 10 = 40 XP.
        let outcome = store.completeLesson(lessonId: "t-l1", correctCount: 4, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(outcome.xpGained, 40)
        XCTAssertEqual(outcome.stars, 2)
        XCTAssertFalse(outcome.weekendDoubled)
    }

    func testPerfectFirstThreeStarXp() {
        // 5/5 perfect + first-ever 3 stars on a weekday: 50 + 5 + 5 = 60.
        let outcome = store.completeLesson(lessonId: "t-l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(outcome.xpGained, 60)
        XCTAssertEqual(outcome.stars, 3)

        // Same-day replay: still perfect but no first-perfect bonus → 55.
        let again = store.completeLesson(lessonId: "t-l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(again.xpGained, 55)
    }

    func testWeekendDoublesLessonXp() {
        // 2026-03-01 is a Sunday: (50 + 5 + 5) × 2 = 120, flagged for the UI.
        let outcome = store.completeLesson(lessonId: "t-l1", correctCount: 5, questionCount: 5, now: day("2026-03-01"))
        XCTAssertEqual(outcome.xpGained, 120)
        XCTAssertTrue(outcome.weekendDoubled)
    }

    func testLessonGemDripMatchesWebEconomy() {
        // First 3-star clear of 5 questions: 3 base + 10 three-star + 15 first
        // perfect + 20 first daily-goal cross (60 XP ≥ default goal 50) = 48.
        let outcome = store.completeLesson(lessonId: "t-l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(outcome.gemsGained, 48)
        XCTAssertFalse(outcome.newAchievements.isEmpty)
        // Balance = drip + achievement rewards (first-lesson 20 + perfect-1 20).
        XCTAssertEqual(store.gems, 48 + 40)

        // Same-day replay: still 3 stars but no first-perfect / goal bonus
        // (the +20 must not repeat) → 3 + 10. Total XP crosses 100 here
        // (60 + 55 = 115) so the xp-100 badge legitimately unlocks now.
        let again = store.completeLesson(lessonId: "t-l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(again.gemsGained, 13)
        XCTAssertEqual(again.newAchievements.map(\.id), ["xp-100"])
        XCTAssertEqual(store.gems, 48 + 40 + 13 + 20)
    }
}
