import XCTest
@testable import ChinaTextbookStudy

// MARK: - Wave D: store 与领域层地基
//
// 覆盖：课程会话持久化（upsert / clear / 跨重启恢复 / 完课自动清除）、
// 练习补心封顶、成就领取制（幂等 + 可领取计数 + 分级家族模型）、
// SRS 毕业不删条目且不进 due 队列、护盾消耗数透传到 LessonOutcome、
// joinedDate 回填、任务快照纯读取。

@MainActor
final class WaveDStoreTests: XCTestCase {
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

    private func makeSession(lessonId: String = "g1up-u1-kp1") -> ActiveLessonSession {
        ActiveLessonSession(
            bookId: "g1up",
            lessonId: lessonId,
            queueIds: [3, 4, 5],
            solvedIds: [1, 2],
            missedIds: [3],
            combo: 2,
            maxCombo: 2,
            sessionXp: 20,
            startedAt: "2026-03-02T08:00:00Z"
        )
    }

    private func makeQuestion(id: Int) -> Question {
        Question(
            id: id, type: .choice, score: 1, difficulty: 1, knowledgePoint: "kp",
            question: "q", options: ["A", "B"], answer: "A", explanation: "", audio: nil
        )
    }

    // MARK: - Lesson session persistence (parity-13)

    func testSessionUpsertReadAndClear() {
        XCTAssertNil(store.activeSession(for: "g1up-u1-kp1"))

        let session = makeSession()
        store.upsertLessonSession(session)
        XCTAssertEqual(store.activeSession(for: "g1up-u1-kp1"), session)
        // A different lesson never sees someone else's session.
        XCTAssertNil(store.activeSession(for: "g1up-u1-kp2"))

        // Upsert replaces in place (only one suspended session is kept).
        var updated = session
        updated.queueIds = [4, 5]
        updated.solvedIds = [1, 2, 3]
        store.upsertLessonSession(updated)
        XCTAssertEqual(store.activeSession(for: "g1up-u1-kp1"), updated)

        store.clearLessonSession()
        XCTAssertNil(store.activeSession(for: "g1up-u1-kp1"))
        XCTAssertNil(store.progress.activeLesson)
    }

    func testSessionSurvivesRelaunch() {
        let session = makeSession()
        store.upsertLessonSession(session)
        // Boot a second store from the same save file — the suspended session
        // must come back field-for-field.
        let rebooted = ProgressStore()
        XCTAssertEqual(rebooted.activeSession(for: session.lessonId), session)
    }

    func testCompletingTheLessonDropsItsSession() {
        store.upsertLessonSession(makeSession(lessonId: "l1"))
        store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertNil(store.progress.activeLesson, "a finished lesson has nothing to resume")
    }

    func testCompletingAnotherLessonKeepsForeignSession() {
        let session = makeSession(lessonId: "l1")
        store.upsertLessonSession(session)
        store.completeLesson(lessonId: "l2", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(store.activeSession(for: "l1"), session)
    }

    // MARK: - addHeart (ios-economy-4)

    func testAddHeartCapsAtMax() {
        // Burn two hearts, win them back one at a time.
        store.loseHeart(now: day("2026-03-02"))
        store.loseHeart(now: day("2026-03-02"))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts - 2)

        store.addHeart(now: day("2026-03-02"))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts - 1)

        // Overshooting clamps to the cap and stops the recharge timer.
        store.addHeart(3, now: day("2026-03-02"))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts)
        XCTAssertNil(store.nextHeartAt, "full hearts must not keep a recharge timer running")

        // At the cap it is a no-op; non-positive n is ignored.
        store.addHeart(now: day("2026-03-02"))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts)
        store.loseHeart(now: day("2026-03-02"))
        store.addHeart(0, now: day("2026-03-02"))
        store.addHeart(-2, now: day("2026-03-02"))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts - 1)
    }

    // MARK: - Achievement claiming (ios-retention-10 / ios-economy-18)

    func testClaimAchievementIsIdempotent() {
        // Unlock first-lesson + perfect-1; neither pays at unlock time.
        let outcome = store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertTrue(outcome.newAchievements.contains { $0.id == "first-lesson" })
        XCTAssertEqual(store.gems, outcome.gemsGained)
        XCTAssertEqual(store.claimableAchievementCount, 2)

        let before = store.gems
        XCTAssertEqual(store.claimAchievement("first-lesson"), 20)
        XCTAssertEqual(store.claimAchievement("first-lesson"), 0, "second claim must pay nothing")
        XCTAssertEqual(store.claimAchievement("first-lesson"), 0)
        XCTAssertEqual(store.gems, before + 20)
        XCTAssertEqual(store.claimableAchievementCount, 1)
        XCTAssertTrue(store.claimedAchievementIds.contains("first-lesson"))
    }

    func testClaimRequiresUnlock() {
        XCTAssertEqual(store.claimAchievement("streak-100"), 0)
        XCTAssertEqual(store.claimAchievement("bogus"), 0)
        XCTAssertEqual(store.gems, 0)
        XCTAssertTrue(store.claimedAchievementIds.isEmpty)
    }

    func testClaimSurvivesRelaunchWithoutDoublePay() {
        store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-02"))
        XCTAssertEqual(store.claimAchievement("first-lesson"), 20)
        let rebooted = ProgressStore()
        XCTAssertEqual(rebooted.claimAchievement("first-lesson"), 0, "claim ledger persists across launches")
        XCTAssertTrue(rebooted.claimableAchievementIds.contains("perfect-1"), "unclaimed ones stay claimable")
    }

    func testFamiliesCoverEveryAchievementExactlyOnce() {
        let tierIds = Achievements.families.flatMap { $0.tiers.map(\.id) }
        XCTAssertEqual(tierIds.count, Set(tierIds).count, "no achievement may sit in two families")
        XCTAssertEqual(Set(tierIds), Set(Achievements.all.map(\.id)), "families must cover the whole catalog")
        // Tiers ascend by goal so「下一档」is well-defined.
        for family in Achievements.families {
            let goals = family.tiers.map(\.goal)
            XCTAssertEqual(goals, goals.sorted(), "\(family.id) tiers must ascend by goal")
        }
    }

    func testFamilyTierHelpers() {
        let streak = Achievements.family(containing: "streak-7")
        XCTAssertEqual(streak?.id, "streak")
        let unlocked: Set<String> = ["streak-3", "streak-7"]
        XCTAssertEqual(streak?.highestUnlocked(unlockedIds: unlocked)?.id, "streak-7")
        XCTAssertEqual(streak?.nextTier(unlockedIds: unlocked)?.id, "streak-30")
        XCTAssertEqual(streak?.unlockedTierCount(unlockedIds: unlocked), 2)
        XCTAssertNil(streak?.highestUnlocked(unlockedIds: []))
        XCTAssertNil(Achievements.family(containing: "first-review")?.nextTier(unlockedIds: ["first-review"]))
    }

    // MARK: - SRS graduation keeps the entry (parity-7)

    func testGraduationKeepsEntryOutOfDueQueue() {
        store.recordMistake(lessonId: "l1", lessonTitle: nil, question: makeQuestion(id: 7), now: day("2026-03-02"))
        XCTAssertEqual(store.dueMistakes.count, 1)

        // box 1→2 (not graduated yet), box 2→3 with correctCount 2 → graduates.
        XCTAssertFalse(store.reviewMistake(lessonId: "l1", questionId: 7, isCorrect: true, now: day("2026-03-02")))
        XCTAssertTrue(store.reviewMistake(lessonId: "l1", questionId: 7, isCorrect: true, now: day("2026-03-03")))

        XCTAssertEqual(store.progress.mistakesBank.count, 1, "graduated entry must stay in the bank")
        XCTAssertEqual(store.progress.mistakesBank[0].graduated, true)
        XCTAssertEqual(store.graduatedMistakes.count, 1)
        // Even far in the future the graduated entry never comes due.
        XCTAssertTrue(SRS.dueEntries(store.progress.mistakesBank, now: day("2026-06-01")).count >= 1,
                      "sanity: the raw scheduler would surface it…")
        XCTAssertTrue(store.dueMistakes.isEmpty, "…but the store filters graduated entries out")
        // Achievement snapshot keeps counting the reviewed entry.
        XCTAssertEqual(store.achievementSnapshot.reviewedMistakeCount, 1)
        // An already-graduated entry cannot "newly graduate" again.
        XCTAssertFalse(store.reviewMistake(lessonId: "l1", questionId: 7, isCorrect: true, now: day("2026-03-10")))
        XCTAssertEqual(store.progress.mistakesBank[0].graduated, true)
    }

    func testWrongAnswerSendsGraduateBackToOven() {
        store.recordMistake(lessonId: "l1", lessonTitle: nil, question: makeQuestion(id: 9), now: day("2026-03-02"))
        XCTAssertFalse(store.reviewMistake(lessonId: "l1", questionId: 9, isCorrect: true, now: day("2026-03-02")))
        XCTAssertTrue(store.reviewMistake(lessonId: "l1", questionId: 9, isCorrect: true, now: day("2026-03-03")))
        XCTAssertEqual(store.graduatedMistakes.count, 1)

        // Defensive parity with web: a wrong answer clears the flag and the
        // entry re-enters the review loop (box 1, due today).
        XCTAssertFalse(store.reviewMistake(lessonId: "l1", questionId: 9, isCorrect: false, now: day("2026-03-10")))
        XCTAssertEqual(store.progress.mistakesBank[0].graduated, false)
        XCTAssertEqual(store.dueMistakes.count, 1)
    }

    func testUngraduatedEntryStillComesDue() {
        store.recordMistake(lessonId: "l1", lessonTitle: nil, question: makeQuestion(id: 8), now: day("2026-03-02"))
        // A wrong review keeps it in box 1, due today.
        XCTAssertFalse(store.reviewMistake(lessonId: "l1", questionId: 8, isCorrect: false, now: day("2026-03-02")))
        XCTAssertEqual(store.dueMistakes.count, 1)
        XCTAssertNotEqual(store.progress.mistakesBank[0].graduated, true)
    }

    // MARK: - freezesConsumed passthrough (ios-economy-6)

    func testFreezesConsumedReachesLessonOutcome() {
        store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5, now: day("2026-03-03"))
        XCTAssertEqual(store.streakFreezes, 2)

        // Miss 03-04 (gap 2): one shield covers the missed day.
        let shielded = store.completeLesson(lessonId: "l2", correctCount: 5, questionCount: 5, now: day("2026-03-05"))
        XCTAssertEqual(shielded.freezesConsumed, 1)
        XCTAssertEqual(shielded.streakAfter, 2)
        XCTAssertEqual(store.streakFreezes, 1)

        // A plain consecutive day consumes nothing.
        let plain = store.completeLesson(lessonId: "l3", correctCount: 5, questionCount: 5, now: day("2026-03-06"))
        XCTAssertEqual(plain.freezesConsumed, 0)

        // A broken chain (gap beyond shields) resets without consuming.
        let broken = store.completeLesson(lessonId: "l4", correctCount: 5, questionCount: 5, now: day("2026-03-20"))
        XCTAssertEqual(broken.freezesConsumed, 0)
        XCTAssertEqual(broken.streakAfter, 1)
        XCTAssertEqual(store.streakFreezes, 1, "insufficient shields are kept, not burned")
    }

    // MARK: - joinedDate (ios-retention-12)

    func testFreshSaveJoinsToday() {
        XCTAssertEqual(store.joinedDate, SRS.todayString())
        XCTAssertEqual(store.progress.joinedDate, SRS.todayString())
    }

    func testLegacySaveBackfillsJoinedDateFromEarliestLesson() throws {
        var p = UserProgress(
            xp: 100, streak: 0, lastActiveDate: "2026-02-10",
            completedLessons: [
                "l1": LessonResult(lessonId: "l1", stars: 3, accuracy: 1, completedAt: "2026-01-05T10:00:00Z"),
                "l2": LessonResult(lessonId: "l2", stars: 2, accuracy: 0.8, completedAt: "2026-02-10T09:00:00Z"),
            ],
            mistakesBank: []
        )
        p.freezesMigrated = true
        let s = try bootStore(with: p)
        XCTAssertEqual(s.joinedDate, "2026-01-05")
    }

    // MARK: - Quests snapshot (ios-retention-4)

    func testQuestsSnapshotIsAPureRead() {
        let before = store.questsSnapshot()
        XCTAssertEqual(before.count, 3)
        XCTAssertTrue(before.allSatisfy { $0.progress == 0 && !$0.claimed })

        // Snapshotting twice changes nothing (pure read).
        XCTAssertEqual(store.questsSnapshot(), before)

        // After a lesson the diff shows up while quest identity is stable.
        store.completeLesson(lessonId: "l1", correctCount: 5, questionCount: 5)
        let after = store.questsSnapshot()
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        let xpBefore = before.first { $0.quest.kind == .earnXP }!
        let xpAfter = after.first { $0.quest.kind == .earnXP }!
        XCTAssertGreaterThan(xpAfter.progress, xpBefore.progress)
    }

    func testClaimableQuestCountMatchesCardLogic() {
        XCTAssertEqual(store.claimableQuestCount, 0)
        // A big perfect lesson satisfies at minimum the XP quest (max target
        // 100 ≤ 10×10+bonuses) and the 1-lesson quest when today offers one.
        store.completeLesson(lessonId: "l1", correctCount: 10, questionCount: 10)
        let expected = store.todayQuests.filter {
            store.isQuestComplete($0) && !store.isQuestClaimed($0)
        }.count
        XCTAssertEqual(store.claimableQuestCount, expected)
        XCTAssertGreaterThanOrEqual(store.claimableQuestCount, 1)

        // Claiming drops the count one by one.
        if let claimable = store.todayQuests.first(where: { store.isQuestComplete($0) && !store.isQuestClaimed($0) }) {
            XCTAssertTrue(store.claimQuest(claimable))
            XCTAssertEqual(store.claimableQuestCount, expected - 1)
        }
    }
}
