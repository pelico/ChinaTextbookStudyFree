import XCTest
@testable import ChinaTextbookStudy

// MARK: - Wave B: 回访奖励链 + 经济单一事实源的行为测试
//
// 覆盖：连胜里程碑只发一次、每日登录奖励每日一次（断签按 0 档）、
// 护盾上限/新档初始/老档迁移、周一自动补给、连胜补卡条件、
// 成就永久账本防「回锁」+ 奖励只发一次。

@MainActor
final class WaveBTests: XCTestCase {
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

    /// Write a crafted save file and boot a fresh store from it (exercises the
    /// same load/migration path a real relaunch takes).
    private func bootStore(with progress: UserProgress) throws -> ProgressStore {
        try PersistenceService.write(progress, to: "progress.json")
        return ProgressStore()
    }

    // MARK: - Streak milestones (once per tier)

    func testStreakMilestonePaidOnceViaLedger() {
        // Three consecutive study days → streak 3 milestone pays 30 gems.
        store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        store.completeLesson(lessonId: "l2", correctCount: 5, questionCount: 5, now: day("2026-03-03"))
        let third = store.completeLesson(lessonId: "l3", correctCount: 5, questionCount: 5, now: day("2026-03-04"))
        XCTAssertEqual(third.streakAfter, 3)
        XCTAssertEqual(third.milestoneGems, 30)
        XCTAssertEqual(store.progress.claimedStreakRewards, [3])

        // Break the chain (5 missed days > 2 shields) and climb back to 3:
        // the tier is already on the ledger — never paid again.
        store.completeLesson(lessonId: "l4", correctCount: 5, questionCount: 5, now: day("2026-03-10"))
        XCTAssertEqual(store.progress.streak, 1)
        store.completeLesson(lessonId: "l5", correctCount: 5, questionCount: 5, now: day("2026-03-11"))
        let reclimbed = store.completeLesson(lessonId: "l6", correctCount: 5, questionCount: 5, now: day("2026-03-12"))
        XCTAssertEqual(reclimbed.streakAfter, 3)
        XCTAssertEqual(reclimbed.milestoneGems, 0)
        XCTAssertEqual(store.progress.claimedStreakRewards, [3])
    }

    func testNonMilestoneDayPaysNothing() {
        store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        let second = store.completeLesson(lessonId: "l2", correctCount: 5, questionCount: 5, now: day("2026-03-03"))
        XCTAssertEqual(second.streakAfter, 2)
        XCTAssertEqual(second.milestoneGems, 0)
    }

    // MARK: - Daily login reward (once per local day)

    func testDailyRewardClaimsOncePerDay() {
        let before = store.gems
        store.claimDailyRewardIfDue(now: day("2026-03-02"))
        // Fresh save, no streak → tier 0 = 5 gems; card copy must not brag.
        XCTAssertEqual(store.gems, before + 5)
        XCTAssertEqual(store.pendingDailyReward, ProgressStore.DailyRewardClaim(gems: 5, effectiveStreak: 0))
        XCTAssertEqual(store.progress.lastDailyRewardDate, "2026-03-02")

        // Second claim the same day is a no-op.
        store.pendingDailyReward = nil
        store.claimDailyRewardIfDue(now: day("2026-03-02"))
        XCTAssertEqual(store.gems, before + 5)
        XCTAssertNil(store.pendingDailyReward)
    }

    func testDailyRewardTierFollowsSalvageableStreak() {
        // Build a 3-day streak, then open the app next morning (not studied
        // yet — the streak is still savable): tier 3 = 12 gems.
        store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        store.completeLesson(lessonId: "l2", correctCount: 5, questionCount: 5, now: day("2026-03-03"))
        store.completeLesson(lessonId: "l3", correctCount: 5, questionCount: 5, now: day("2026-03-04"))
        let before = store.gems
        store.claimDailyRewardIfDue(now: day("2026-03-05"))
        XCTAssertEqual(store.gems, before + 12)
        XCTAssertEqual(store.pendingDailyReward, ProgressStore.DailyRewardClaim(gems: 12, effectiveStreak: 3))
    }

    func testDailyRewardHonestAfterBrokenChain() throws {
        // A dead 10-day streak (gap beyond shields) must claim at tier 0 and
        // report effectiveStreak 0 — the card never brags about a lost chain.
        var p = UserProgress(xp: 0, streak: 10, lastActiveDate: "2026-02-20", completedLessons: [:], mistakesBank: [])
        p.streakFreezes = 2
        p.freezesMigrated = true
        let s = try bootStore(with: p)
        s.claimDailyRewardIfDue(now: day("2026-03-02"))
        XCTAssertEqual(s.pendingDailyReward, ProgressStore.DailyRewardClaim(gems: 5, effectiveStreak: 0))
    }

    // MARK: - Shields: initial balance / cap / migration / Monday top-up

    func testFreshSaveStartsWithTwoShieldsAndCapBlocksPurchase() {
        XCTAssertEqual(store.streakFreezes, 2)
        store.addGems(400)
        XCTAssertFalse(store.buyStreakFreeze(), "full shields (2/2) must refuse a purchase")
        XCTAssertEqual(store.gems, 400, "no gems may be spent on a refused purchase")
        XCTAssertEqual(store.streakFreezes, 2)
    }

    func testBuySucceedsBelowCap() throws {
        var p = UserProgress(xp: 0, streak: 1, lastActiveDate: "2026-03-02", completedLessons: [:], mistakesBank: [])
        p.streakFreezes = 1
        p.freezesMigrated = true
        p.gems = 250
        let s = try bootStore(with: p)
        XCTAssertTrue(s.buyStreakFreeze())
        XCTAssertEqual(s.streakFreezes, 2)
        XCTAssertEqual(s.gems, 50)
        XCTAssertFalse(s.buyStreakFreeze(), "now full — capped at 2")
    }

    func testLegacySaveMigratesShieldsUpToTwo() throws {
        var p = UserProgress(xp: 50, streak: 4, lastActiveDate: "2026-03-01", completedLessons: [:], mistakesBank: [])
        p.streakFreezes = 0   // old economy: no starter shields
        let s = try bootStore(with: p)
        XCTAssertEqual(s.streakFreezes, 2)
        XCTAssertEqual(s.progress.freezesMigrated, true)
    }

    func testLegacySaveAboveCapKeepsShieldsButBlocksBuying() throws {
        var p = UserProgress(xp: 50, streak: 4, lastActiveDate: "2026-03-01", completedLessons: [:], mistakesBank: [])
        p.streakFreezes = 4   // hoarded under the old no-cap economy
        p.gems = 500
        let s = try bootStore(with: p)
        XCTAssertEqual(s.streakFreezes, 4, "shields above the cap are never confiscated")
        XCTAssertFalse(s.buyStreakFreeze(), "…but new purchases are blocked")
        XCTAssertEqual(s.gems, 500)
    }

    func testMigrationRunsOnlyOnce() throws {
        // A migrated save that legitimately spent its shields must NOT be
        // topped back up on the next launch.
        var p = UserProgress(xp: 50, streak: 4, lastActiveDate: "2026-03-01", completedLessons: [:], mistakesBank: [])
        p.streakFreezes = 0
        p.freezesMigrated = true
        let s = try bootStore(with: p)
        XCTAssertEqual(s.streakFreezes, 0)
    }

    func testMondayShieldTopUpThroughTheStore() throws {
        // Streak alive, one shield slot free, next study lands on Monday
        // 2026-03-02 with a 1-day gap → auto top-up to 2.
        var p = UserProgress(xp: 0, streak: 3, lastActiveDate: "2026-03-01", completedLessons: [:], mistakesBank: [])
        p.streakFreezes = 1
        p.freezesMigrated = true
        let s = try bootStore(with: p)
        s.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(s.progress.streak, 4)
        XCTAssertEqual(s.streakFreezes, 2)
    }

    // MARK: - Streak make-up (50 gems, broken chain only)

    func testMakeUpRevivesABrokenStreak() {
        let outcome = store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertGreaterThanOrEqual(store.gems, Economy.streakMakeupCost)
        _ = outcome
        // Missed 03-03/03-04/03-05: 3 days > 2 shields → chain is dead.
        XCTAssertEqual(store.salvageableStreak(now: day("2026-03-06")), 0)

        let gemsBefore = store.gems
        XCTAssertTrue(store.makeUpYesterdayStreak(now: day("2026-03-06")))
        XCTAssertEqual(store.gems, gemsBefore - Economy.streakMakeupCost)
        XCTAssertEqual(store.progress.lastActiveDate, "2026-03-05")
        // The flame is immediately savable again (study today to continue it).
        XCTAssertEqual(store.salvageableStreak(now: day("2026-03-06")), 1)

        // Already revived → a second make-up is refused.
        XCTAssertFalse(store.makeUpYesterdayStreak(now: day("2026-03-06")))
    }

    func testMakeUpRefusedWhenStreakIsNotBroken() {
        store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        // Same day: studied today → no.
        XCTAssertFalse(store.makeUpYesterdayStreak(now: day("2026-03-02")))
        // Next day (gap 1): the streak just continues by studying → no.
        XCTAssertFalse(store.makeUpYesterdayStreak(now: day("2026-03-03")))
        // Gap 2 but shields can still cover it → no (not actually broken).
        XCTAssertFalse(store.makeUpYesterdayStreak(now: day("2026-03-04")))
    }

    func testMakeUpRefusedWithoutEnoughGems() {
        // A 1-star lesson banks 3 drip + 20 first-lesson reward = 23 < 50.
        store.completeLesson(lessonId: "l1", correctCount: 0, questionCount: 5, now: day("2026-03-02"))
        XCTAssertLessThan(store.gems, Economy.streakMakeupCost)
        XCTAssertEqual(store.salvageableStreak(now: day("2026-03-06")), 0)
        XCTAssertFalse(store.makeUpYesterdayStreak(now: day("2026-03-06")))
        XCTAssertEqual(store.progress.lastActiveDate, "2026-03-02", "a refused make-up must not touch the date")
    }

    // MARK: - Achievement ledger (permanent, pays once)

    func testAchievementLedgerNeverRelocks() {
        // Reach streak-3 → achievement unlocks with its gem reward.
        store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        store.completeLesson(lessonId: "l2", correctCount: 5, questionCount: 5, now: day("2026-03-03"))
        let third = store.completeLesson(lessonId: "l3", correctCount: 5, questionCount: 5, now: day("2026-03-04"))
        XCTAssertTrue(third.newAchievements.contains { $0.id == "streak-3" })
        XCTAssertTrue((store.progress.unlockedAchievements ?? []).contains("streak-3"))

        // Chain collapses; live snapshot no longer satisfies streak-3 — the
        // ledger keeps it unlocked and no second payout happens.
        let afterBreak = store.completeLesson(lessonId: "l4", correctCount: 5, questionCount: 5, now: day("2026-03-12"))
        XCTAssertEqual(store.progress.streak, 1)
        XCTAssertFalse(afterBreak.newAchievements.contains { $0.id == "streak-3" })
        XCTAssertTrue(store.unlockedAchievementIds.contains("streak-3"))
        XCTAssertTrue((store.progress.unlockedAchievements ?? []).contains("streak-3"))
    }

    func testAchievementRewardPaidExactlyOnce() {
        // first-lesson (20💎) pays on the unlocking lesson…
        let first = store.completeLesson(lessonId: "l1", correctCount: 0, questionCount: 5, now: day("2026-03-02"))
        XCTAssertTrue(first.newAchievements.contains { $0.id == "first-lesson" })
        let gemsAfterFirst = store.gems
        // …and never again on later lessons.
        let second = store.completeLesson(lessonId: "l2", correctCount: 0, questionCount: 5, now: day("2026-03-02"))
        XCTAssertFalse(second.newAchievements.contains { $0.id == "first-lesson" })
        XCTAssertEqual(store.gems, gemsAfterFirst + second.gemsGained)
    }

    func testFirstReviewSurvivesGraduation() {
        // Reviewing a mistake unlocks first-review; when the entry graduates
        // out of the bank the snapshot count falls back to 0 — the ledger
        // keeps the badge.
        let q = Question(
            id: 7, type: .choice, score: 1, difficulty: 1, knowledgePoint: "kp",
            question: "q", options: ["A", "B"], answer: "A", explanation: "", audio: nil
        )
        store.recordMistake(lessonId: "l1", lessonTitle: nil, question: q, now: day("2026-03-02"))
        // Three correct reviews graduate the entry (box 3 + correctCount ≥ 2).
        store.reviewMistake(lessonId: "l1", questionId: 7, isCorrect: true, now: day("2026-03-02"))
        store.reviewMistake(lessonId: "l1", questionId: 7, isCorrect: true, now: day("2026-03-03"))
        store.reviewMistake(lessonId: "l1", questionId: 7, isCorrect: true, now: day("2026-03-06"))
        XCTAssertTrue(store.progress.mistakesBank.isEmpty, "entry should have graduated")
        XCTAssertTrue(store.unlockedAchievementIds.contains("first-review"))
    }

    // MARK: - Daily goal options

    func testDailyGoalOptionsAndLegacyValuePreserved() {
        XCTAssertEqual(Economy.dailyGoalOptions, [20, 50, 100, 200])
        // A legacy 学霸 who chose 500 keeps that value — only the option list
        // changed, nothing rewrites the stored goal.
        store.setDailyGoal(500)
        XCTAssertEqual(store.dailyGoal, 500)
    }
}
