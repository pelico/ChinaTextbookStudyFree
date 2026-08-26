import XCTest
@testable import ChinaTextbookStudy

/// 跨端经济黄金向量 —— 读取 packages/core/spec/golden-vectors.json（与 TS 端
/// goldenVectors.test.ts 消费同一份文件），逐条断言 Swift 实现与 core 的
/// economy.ts / srs.ts / chestLogic.ts 完全一致。任何数值改动必须双端同步。
final class GoldenVectorTests: XCTestCase {

    // MARK: - Vector file loading

    private struct Vectors: Codable {
        let version: Int
        let stars: [StarVector]
        let xp: [XpVector]
        let gemDrip: [GemDripVector]
        let streakAdvance: [StreakAdvanceVector]
        let srsReview: [SrsReviewVector]
        let dailyReward: [DailyRewardVector]
        let milestone: [MilestoneVector]
        let chestSlot: [ChestSlotVector]
    }

    private struct StarVector: Codable {
        let accuracy: Double
        let expStars: Int
    }

    private struct XpVector: Codable {
        let correctCount: Int
        let perfect: Bool
        let firstPerfect: Bool
        let isWeekend: Bool
        let expXp: Int
    }

    private struct GemDripVector: Codable {
        let stars: Int
        let isFirstPerfect: Bool
        let crossedDailyGoal: Bool
        let expGems: Int
    }

    private struct StreakAdvanceVector: Codable {
        let streak: Int
        let freezes: Int
        let gapDays: Int
        let isMonday: Bool
        let expStreak: Int
        let expFreezes: Int
        let expConsumed: Int
    }

    private struct SrsReviewVector: Codable {
        let box: Int
        let isCorrect: Bool
        let expBox: Int
        let expIntervalDays: Int
    }

    private struct DailyRewardVector: Codable {
        let streak: Int
        let expGems: Int
    }

    private struct MilestoneVector: Codable {
        let streakAfter: Int
        let expGems: Int
    }

    private struct ChestSlotVector: Codable {
        let lessonsCompletedInUnit: Int
        let expChests: Int
    }

    /// packages/core/spec/golden-vectors.json, located from this file's path:
    /// apps/mobile/ChinaTextbookStudyTests/… → repo root is 3 directories up.
    private static func vectorFileURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ChinaTextbookStudyTests/
            .deletingLastPathComponent()   // apps/mobile/
            .deletingLastPathComponent()   // apps/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("packages/core/spec/golden-vectors.json")
    }

    private func loadVectors() throws -> Vectors {
        let url = Self.vectorFileURL()
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Vectors.self, from: data)
    }

    // MARK: - Assertions per vector group

    func testStarVectors() throws {
        for v in try loadVectors().stars {
            XCTAssertEqual(
                Economy.starsFromAccuracy(v.accuracy), v.expStars,
                "starsFromAccuracy(\(v.accuracy))"
            )
        }
    }

    func testXpVectors() throws {
        for v in try loadVectors().xp {
            XCTAssertEqual(
                Economy.xpForLesson(
                    correctCount: v.correctCount,
                    perfect: v.perfect,
                    firstPerfect: v.firstPerfect,
                    isWeekend: v.isWeekend
                ),
                v.expXp,
                "xpForLesson(correct: \(v.correctCount), perfect: \(v.perfect), first: \(v.firstPerfect), weekend: \(v.isWeekend))"
            )
        }
    }

    func testGemDripVectors() throws {
        for v in try loadVectors().gemDrip {
            XCTAssertEqual(
                Economy.lessonGemDrip(
                    stars: v.stars,
                    isFirstPerfect: v.isFirstPerfect,
                    crossedDailyGoal: v.crossedDailyGoal
                ),
                v.expGems,
                "lessonGemDrip(stars: \(v.stars), first: \(v.isFirstPerfect), crossed: \(v.crossedDailyGoal))"
            )
        }
    }

    func testStreakAdvanceVectors() throws {
        for v in try loadVectors().streakAdvance {
            let r = Economy.advanceStreak(
                streak: v.streak,
                freezes: v.freezes,
                gapDays: v.gapDays,
                isMonday: v.isMonday
            )
            XCTAssertEqual(r.streak, v.expStreak, "streak for gap \(v.gapDays), freezes \(v.freezes), monday \(v.isMonday)")
            XCTAssertEqual(r.freezes, v.expFreezes, "freezes for gap \(v.gapDays), freezes \(v.freezes), monday \(v.isMonday)")
            XCTAssertEqual(r.freezesConsumed, v.expConsumed, "consumed for gap \(v.gapDays), freezes \(v.freezes), monday \(v.isMonday)")
        }
    }

    func testSrsReviewVectors() throws {
        let now = SRS.dateFormatter.date(from: "2026-03-02")!
        let question = Question(
            id: 1, type: .choice, score: 1, difficulty: 1, knowledgePoint: "kp",
            question: "q", options: ["A", "B"], answer: "A", explanation: "", audio: nil
        )
        for v in try loadVectors().srsReview {
            var entry = SRS.newEntry(lessonId: "l1", question: question, now: now)
            entry.box = v.box
            let next = SRS.review(entry: entry, isCorrect: v.isCorrect, now: now)
            XCTAssertEqual(next.box, v.expBox, "box after review(box: \(v.box), correct: \(v.isCorrect))")
            XCTAssertEqual(
                next.nextReviewDate,
                SRS.dateString(daysFromNow: v.expIntervalDays, now: now),
                "interval after review(box: \(v.box), correct: \(v.isCorrect))"
            )
        }
    }

    func testDailyRewardVectors() throws {
        for v in try loadVectors().dailyReward {
            XCTAssertEqual(
                Economy.dailyRewardForStreak(v.streak), v.expGems,
                "dailyRewardForStreak(\(v.streak))"
            )
        }
    }

    func testMilestoneVectors() throws {
        for v in try loadVectors().milestone {
            XCTAssertEqual(
                Economy.streakMilestoneReward(v.streakAfter), v.expGems,
                "streakMilestoneReward(\(v.streakAfter))"
            )
        }
    }

    func testChestSlotVectors() throws {
        for v in try loadVectors().chestSlot {
            let lessons = (1...v.lessonsCompletedInUnit).map { i in
                PathLessonMeta(
                    id: "g1up-u1-kp\(i)", title: "kp\(i)", unitNumber: 1,
                    unitTitle: "U1", kpIndex: i, kpTotal: v.lessonsCompletedInUnit,
                    questionCount: 5
                )
            }
            XCTAssertEqual(
                Chest.slots(bookId: "g1up", lessons: lessons).count, v.expChests,
                "chest slots after \(v.lessonsCompletedInUnit) lessons"
            )
        }
    }

    // MARK: - Constant parity (values not exercised by a vector group)

    func testEconomyConstantsMatchSpec() {
        XCTAssertEqual(Economy.maxHearts, 5)
        XCTAssertEqual(Economy.heartRegenSeconds, 300)
        XCTAssertEqual(Economy.heartRefillCost, 350)
        XCTAssertEqual(Economy.freezeCost, 200)
        XCTAssertEqual(Economy.maxFreezes, 2)
        XCTAssertEqual(Economy.initialFreezes, 2)
        XCTAssertEqual(Economy.streakMakeupCost, 50)
        XCTAssertEqual(Economy.dailyGoalOptions, [20, 50, 100, 200])
        XCTAssertEqual(Economy.defaultDailyGoal, 50)
        XCTAssertEqual(Economy.ReadingXP.listen, 5)
        XCTAssertEqual(Economy.ReadingXP.followup, 10)
        XCTAssertEqual(Economy.ReadingXP.storyGood, 15)
        XCTAssertEqual(Economy.ReadingXP.storyBase, 5)
        XCTAssertEqual(Economy.ReadingXP.goodThreshold, 0.8)
        XCTAssertEqual(Economy.storyQuizXp(accuracy: 0.8), 15)
        XCTAssertEqual(Economy.storyQuizXp(accuracy: 0.79), 5)
        XCTAssertEqual(
            Economy.streakMilestoneRewards,
            [3: 30, 7: 80, 14: 150, 30: 300, 60: 500, 100: 800]
        )
        XCTAssertEqual(Economy.dailyRewardTable, [5, 5, 8, 12, 15, 20, 25, 30])
    }
}
