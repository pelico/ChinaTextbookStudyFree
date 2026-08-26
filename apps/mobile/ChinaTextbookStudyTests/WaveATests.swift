import XCTest
@testable import ChinaTextbookStudy

// MARK: - Wave A regressions (honest streak display + heart economy)

/// Covers the Wave A fixes: `displayStreak` / `salvageableStreak` never shows
/// a streak that is already gone, and `buyHeartRefill` settles the recharge
/// timer before charging so recharged hearts are never sold back for gems.
@MainActor
final class WaveATests: XCTestCase {
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

    // MARK: displayStreak tri-state

    func testDisplayStreakShowsCurrentStreakWhenStudiedToday() {
        store.completeLesson(lessonId: "t-l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(store.salvageableStreak(now: day("2026-03-02")), 1)
    }

    func testDisplayStreakHoldsWhileTodayCanStillContinueIt() {
        store.completeLesson(lessonId: "t-l1", correctCount: 5, questionCount: 5, now: day("2026-03-01"))
        store.completeLesson(lessonId: "t-l2", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(store.progress.streak, 2)
        // Next morning, nothing studied yet: the 2-day streak is still savable.
        XCTAssertEqual(store.salvageableStreak(now: day("2026-03-03")), 2)
    }

    func testDisplayStreakDropsToZeroWhenShieldsCannotCoverTheGap() {
        store.completeLesson(lessonId: "t-l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        // Wave B baseline: fresh saves carry 2 shields.
        XCTAssertEqual(store.streakFreezes, 2)
        // Missed 03-03/03-04/03-05 — three days, only 2 shields: the chain is
        // gone, show 0 — even though the stored streak field still says 1
        // until the next study writes it.
        XCTAssertEqual(store.salvageableStreak(now: day("2026-03-06")), 0)
        XCTAssertEqual(store.progress.streak, 1)
    }

    func testDisplayStreakSurvivesGapCoveredByShields() {
        // The 2 starter shields cover a 2-day absence.
        store.completeLesson(lessonId: "t-l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        // Missed 03-03 + 03-04 with 2 shields banked: still savable today.
        XCTAssertEqual(store.salvageableStreak(now: day("2026-03-05")), 1)
    }

    // MARK: buyHeartRefill settles recharge before charging

    func testBuyHeartRefillDoesNotChargeWhenHeartsRechargedOffscreen() {
        let t0 = day("2026-03-02")
        store.addGems(400)
        store.loseHeart(now: t0)
        XCTAssertEqual(store.hearts, 4)
        // Half an hour later the heart is long back (5 min each) — buying
        // must be refused without spending a single gem.
        XCTAssertFalse(store.buyHeartRefill(cost: 350, now: t0.addingTimeInterval(30 * 60)))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts)
        XCTAssertEqual(store.gems, 400)
    }

    func testBuyHeartRefillStillChargesWhenHeartsAreMissing() {
        let t0 = day("2026-03-02")
        store.addGems(400)
        store.loseHeart(now: t0)
        store.loseHeart(now: t0)
        // One minute later nothing has recharged yet: purchase goes through.
        XCTAssertTrue(store.buyHeartRefill(cost: 350, now: t0.addingTimeInterval(60)))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts)
        XCTAssertEqual(store.gems, 50)
    }

    // MARK: refreshForNow catches up after inactivity

    func testRefreshForNowRestoresHeartsAfterTimePassed() {
        let t0 = day("2026-03-02")
        store.loseHeart(now: t0)
        store.loseHeart(now: t0)
        XCTAssertEqual(store.hearts, 3)
        // App slept through the recharge window — refresh settles the timer.
        store.refreshForNow(now: t0.addingTimeInterval(30 * 60))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts)
    }
}
