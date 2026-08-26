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
        let examXp: [ExamXpVector]
        let league: LeagueVectors
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

    private struct ExamXpVector: Codable {
        let correctCount: Int
        let perfect: Bool
        let firstPerfect: Bool
        let isWeekend: Bool
        let isExam: Bool
        let expXp: Int
    }

    /// 联赛黄金向量：固定 weekKey/tier/salt 下 15 个 bot 的完整名单 +
    /// 3 个 bot 的周目标与两个时间点（周三 12:00 / 周日 23:59）的累计 XP。
    private struct LeagueVectors: Codable {
        let weekKey: String
        let tier: String
        let salt: String
        let names: [String]
        let bots: [LeagueBotVector]
    }

    private struct LeagueBotVector: Codable {
        let botIndex: Int
        let expName: String
        let expGoal: Int
        let expXpWednesdayNoon: Int
        let expXpSundayNight: Int
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

    // MARK: - Wave E1: exam XP ×2

    func testExamXpVectors() throws {
        for v in try loadVectors().examXp {
            XCTAssertEqual(
                Economy.xpForLesson(
                    correctCount: v.correctCount,
                    perfect: v.perfect,
                    firstPerfect: v.firstPerfect,
                    isWeekend: v.isWeekend,
                    isExam: v.isExam
                ),
                v.expXp,
                "xpForLesson(correct: \(v.correctCount), perfect: \(v.perfect), first: \(v.firstPerfect), weekend: \(v.isWeekend), exam: \(v.isExam))"
            )
        }
    }

    // MARK: - Wave E1: league determinism (bot 名单 / 周目标 / XP 曲线)

    /// 本地时区 weekKey + dayOffset 天的某时刻。
    private func leagueDate(weekKey: String, dayOffset: Int, hour: Int, minute: Int) -> Date {
        let monday = SRS.dateFormatter.date(from: weekKey)!
        let cal = Calendar.current
        let day = cal.date(byAdding: .day, value: dayOffset, to: cal.startOfDay(for: monday))!
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    func testLeagueBotNameVectors() throws {
        let v = try loadVectors().league
        let tier = League.tier(v.tier).id
        XCTAssertEqual(tier.rawValue, v.tier, "向量段位 id 必须有效")
        let bots = League.botsForWeek(weekKey: v.weekKey, tier: tier, salt: v.salt)
        XCTAssertEqual(bots.map(\.name), v.names, "15 个 bot 名单必须逐字同序")
        XCTAssertEqual(Set(bots.map(\.name)).count, bots.count, "组内名字必须去重")
        for (i, bot) in bots.enumerated() {
            XCTAssertEqual(bot.id, "bot-\(v.weekKey)-\(v.tier)-\(i)")
        }
    }

    func testLeagueBotXpVectors() throws {
        let v = try loadVectors().league
        let tier = League.tier(v.tier).id
        let wednesdayNoon = leagueDate(weekKey: v.weekKey, dayOffset: 2, hour: 12, minute: 0)
        let sundayNight = leagueDate(weekKey: v.weekKey, dayOffset: 6, hour: 23, minute: 59)
        let bots = League.botsForWeek(weekKey: v.weekKey, tier: tier, salt: v.salt)

        for b in v.bots {
            XCTAssertEqual(bots[b.botIndex].name, b.expName, "bot \(b.botIndex) 名字")
            XCTAssertEqual(
                League.botWeeklyGoal(weekKey: v.weekKey, tier: tier, salt: v.salt, botIndex: b.botIndex),
                b.expGoal,
                "bot \(b.botIndex) 周目标"
            )
            XCTAssertEqual(
                League.botXpAt(weekKey: v.weekKey, tier: tier, salt: v.salt, botIndex: b.botIndex, date: wednesdayNoon),
                b.expXpWednesdayNoon,
                "bot \(b.botIndex) 周三 12:00 累计 XP"
            )
            XCTAssertEqual(
                League.botXpAt(weekKey: v.weekKey, tier: tier, salt: v.salt, botIndex: b.botIndex, date: sundayNight),
                b.expXpSundayNight,
                "bot \(b.botIndex) 周日 23:59 累计 XP（= 周目标全额）"
            )
        }
    }

    func testLeagueConstantsMatchSpec() {
        XCTAssertEqual(League.tiers.map(\.id.rawValue), ["bronze", "silver", "gold", "sapphire", "ruby", "diamond"])
        XCTAssertEqual(League.tiers.map(\.name), ["青铜联赛", "白银联赛", "黄金联赛", "蓝宝石联赛", "红宝石联赛", "钻石联赛"])
        XCTAssertEqual(
            League.tiers.map(\.colorHex),
            [0xCD7F32, 0xA8B8C8, 0xFFC800, 0x1CB0F6, 0xE0115F, 0x54D7EC]
        )
        XCTAssertEqual(League.unlockLessons, 10)
        XCTAssertEqual(League.groupSize, 16)
        XCTAssertEqual(League.botCount, 15)
        XCTAssertEqual(League.promoteZone, 5)
        XCTAssertEqual(League.demoteZone, 5)
        XCTAssertEqual(League.rankGemRewards, [1: 100, 2: 80, 3: 60, 4: 40, 5: 40])
        XCTAssertEqual(League.promotionBonusGems, 20)
        XCTAssertEqual(League.botNamePool.count, 36)
        XCTAssertEqual(Set(League.botNamePool).count, 36, "名池不得有重复")
        XCTAssertEqual(League.tierXpRanges[.bronze]?.min, 40)
        XCTAssertEqual(League.tierXpRanges[.bronze]?.max, 260)
        XCTAssertEqual(League.tierXpRanges[.silver]?.min, 80)
        XCTAssertEqual(League.tierXpRanges[.silver]?.max, 420)
        XCTAssertEqual(League.tierXpRanges[.gold]?.min, 120)
        XCTAssertEqual(League.tierXpRanges[.gold]?.max, 600)
        XCTAssertEqual(League.tierXpRanges[.sapphire]?.min, 160)
        XCTAssertEqual(League.tierXpRanges[.sapphire]?.max, 800)
        XCTAssertEqual(League.tierXpRanges[.ruby]?.min, 200)
        XCTAssertEqual(League.tierXpRanges[.ruby]?.max, 1000)
        XCTAssertEqual(League.tierXpRanges[.diamond]?.min, 240)
        XCTAssertEqual(League.tierXpRanges[.diamond]?.max, 1200)
        XCTAssertEqual(Economy.examXpMultiplier, 2)
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
