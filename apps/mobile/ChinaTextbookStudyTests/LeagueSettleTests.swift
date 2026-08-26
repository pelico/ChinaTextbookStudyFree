import XCTest
@testable import ChinaTextbookStudy

// MARK: - Wave E1: 本地联赛（引擎边界 + store 结算）与单元挑战 XP
//
// 覆盖：weekKeyFor 周界 / 晋降级边界与奖励 / 榜单同分排序 / bot XP 单调性、
// store 侧解锁门槛 / 入组 / 每周只结一次 / 晋级降级封顶保底 / 结算幕清除、
// 以及单元挑战 XP ×2（宝石 drip 不翻倍）与路径挑战节点状态机。
// （与 core 的逐位对照在 GoldenVectorTests 的 league / examXp 组。）

@MainActor
final class LeagueSettleTests: XCTestCase {
    private var savedProgress: Data?
    private var savedPrefs: Data?
    private var store: ProgressStore!

    override func setUp() async throws {
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

    // MARK: - Helpers

    private func date(_ y: Int, _ m: Int, _ d: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(
            year: y, month: m, day: d, hour: hour, minute: minute
        ))!
    }

    /// Write a crafted save file and boot a fresh store from it.
    private func bootStore(with progress: UserProgress) throws -> ProgressStore {
        try PersistenceService.write(progress, to: "progress.json")
        return ProgressStore()
    }

    /// A save with `count` completed lessons (the league unlock currency).
    private func progressWithLessons(_ count: Int) -> UserProgress {
        var p = UserProgress(
            xp: 0, streak: 0, lastActiveDate: "",
            completedLessons: [:], mistakesBank: []
        )
        for i in 0..<count {
            let id = "g1up-u1-kp\(i + 1)"
            p.completedLessons[id] = LessonResult(
                lessonId: id, stars: 2, accuracy: 0.85,
                completedAt: "2026-08-01T08:00:00Z"
            )
        }
        p.unlockedAchievements = []
        p.claimedAchievements = []
        p.freezesMigrated = true
        p.joinedDate = "2026-08-01"
        return p
    }

    // MARK: - weekKeyFor（本地时区周一）

    func testWeekKeyForMondayReturnsSameDay() {
        XCTAssertEqual(League.weekKeyFor(date(2026, 8, 24, 0, 0)), "2026-08-24")
        XCTAssertEqual(League.weekKeyFor(date(2026, 8, 24, 23, 59)), "2026-08-24")
    }

    func testWeekKeyForMidweekFallsBackToMonday() {
        XCTAssertEqual(League.weekKeyFor(date(2026, 8, 26, 12, 0)), "2026-08-24")
        // 周日仍属同一周，下周一才换周
        XCTAssertEqual(League.weekKeyFor(date(2026, 8, 30, 23, 59)), "2026-08-24")
        XCTAssertEqual(League.weekKeyFor(date(2026, 8, 31, 0, 0)), "2026-08-31")
    }

    func testWeekKeyForCrossesMonthAndYear() {
        // 2026-08-01 是周六，其周一在 7 月
        XCTAssertEqual(League.weekKeyFor(date(2026, 8, 1)), "2026-07-27")
        // 2027-01-01 是周五，其周一在 2026-12-28
        XCTAssertEqual(League.weekKeyFor(date(2027, 1, 1)), "2026-12-28")
    }

    // MARK: - 段位晋降（钻石封顶 / 青铜保底）

    func testTierLadder() {
        XCTAssertEqual(League.nextTierId(.bronze), .silver)
        XCTAssertEqual(League.nextTierId(.ruby), .diamond)
        XCTAssertEqual(League.nextTierId(.diamond), .diamond)
        XCTAssertEqual(League.prevTierId(.diamond), .ruby)
        XCTAssertEqual(League.prevTierId(.silver), .bronze)
        XCTAssertEqual(League.prevTierId(.bronze), .bronze)
        XCTAssertEqual(League.tier("legendary").id, .bronze, "无效 id 容错落回青铜")
    }

    // MARK: - settleRank 边界与奖励

    func testSettleRankBoundaries() {
        // 第 5 名是晋级区最后一名；第 6 名原地。
        XCTAssertTrue(League.settleRank(5, tierId: .gold).promoted)
        XCTAssertFalse(League.settleRank(6, tierId: .gold).promoted)
        // 第 11 名原地；第 12 名进降级区。
        XCTAssertFalse(League.settleRank(11, tierId: .gold).demoted)
        XCTAssertTrue(League.settleRank(12, tierId: .gold).demoted)
        XCTAssertTrue(League.settleRank(16, tierId: .gold).demoted)
    }

    func testSettleRankGems() {
        XCTAssertEqual(League.settleRank(1, tierId: .gold).gems, 120)   // 100 + 晋级 20
        XCTAssertEqual(League.settleRank(2, tierId: .gold).gems, 100)   // 80 + 20
        XCTAssertEqual(League.settleRank(3, tierId: .gold).gems, 80)    // 60 + 20
        XCTAssertEqual(League.settleRank(4, tierId: .gold).gems, 60)    // 40 + 20
        XCTAssertEqual(League.settleRank(5, tierId: .gold).gems, 60)    // 40 + 20
        XCTAssertEqual(League.settleRank(6, tierId: .gold).gems, 0)
        XCTAssertEqual(League.settleRank(16, tierId: .gold).gems, 0)
    }

    func testSettleRankDiamondCapAndBronzeFloor() {
        let diamondTop = League.settleRank(1, tierId: .diamond)
        XCTAssertFalse(diamondTop.promoted, "钻石封顶不再晋级")
        XCTAssertEqual(diamondTop.gems, 100, "封顶时不发晋级奖励")
        let bronzeBottom = League.settleRank(16, tierId: .bronze)
        XCTAssertFalse(bronzeBottom.demoted, "青铜保底不降级")
    }

    // MARK: - 榜单排序（同分用户靠前）

    func testStandingsTieBreak() {
        let botXps = [100, 100, 50] + Array(repeating: 10, count: 12)
        let rows = League.standings(userXp: 100, botXps: botXps)
        XCTAssertEqual(rows.count, 16)
        XCTAssertEqual(rows.map(\.rank), Array(1...16))
        // 同为 100 分：用户第 1，bot0 第 2，bot1 第 3（下标升序）。
        XCTAssertTrue(rows[0].isUser)
        XCTAssertEqual(rows[1].botIndex, 0)
        XCTAssertEqual(rows[2].botIndex, 1)
        XCTAssertEqual(League.userRank(userXp: 100, botXps: botXps), 1)
        XCTAssertEqual(League.userRank(userXp: 0, botXps: botXps), 16)
    }

    // MARK: - bot XP 曲线性质

    func testBotXpMonotonicAndConverges() {
        let weekKey = "2026-08-24"
        for botIndex in [0, 7, 14] {
            let goal = League.botWeeklyGoal(weekKey: weekKey, tier: .gold, salt: "s", botIndex: botIndex)
            let range = League.tierXpRanges[.gold]!
            XCTAssertTrue((range.min...range.max).contains(goal))

            var prev = 0
            for day in 0..<7 {
                for hour in [0, 8, 12, 20, 23] {
                    let xp = League.botXpAt(
                        weekKey: weekKey, tier: .gold, salt: "s", botIndex: botIndex,
                        date: date(2026, 8, 24 + day, hour)
                    )
                    XCTAssertGreaterThanOrEqual(xp, prev, "单调不减 (day \(day) hour \(hour))")
                    XCTAssertLessThanOrEqual(xp, goal)
                    prev = xp
                }
            }
            // 周一 00:00 起步 0；下周任何时刻收敛到周目标全额。
            XCTAssertEqual(
                League.botXpAt(weekKey: weekKey, tier: .gold, salt: "s", botIndex: botIndex,
                               date: date(2026, 8, 24, 0)),
                0
            )
            XCTAssertEqual(
                League.botXpAt(weekKey: weekKey, tier: .gold, salt: "s", botIndex: botIndex,
                               date: date(2026, 9, 2, 9)),
                goal
            )
            // 早于本周为 0。
            XCTAssertEqual(
                League.botXpAt(weekKey: weekKey, tier: .gold, salt: "s", botIndex: botIndex,
                               date: date(2026, 8, 20, 9)),
                0
            )
        }
    }

    // MARK: - store：解锁门槛

    func testLeagueLockedBeforeTenLessons() throws {
        let s = try bootStore(with: progressWithLessons(9))
        XCTAssertFalse(s.leagueUnlocked)
        s.refreshLeague(now: date(2026, 8, 26))
        XCTAssertNil(s.leagueWeekKey, "未解锁不入组")
        XCTAssertNil(s.leagueSalt)
        XCTAssertNil(s.pendingLeagueResult)
    }

    func testLeagueEnrollsAtTenLessons() throws {
        let s = try bootStore(with: progressWithLessons(10))
        XCTAssertTrue(s.leagueUnlocked)
        s.refreshLeague(now: date(2026, 8, 26))
        XCTAssertEqual(s.leagueWeekKey, "2026-08-24")
        XCTAssertEqual(s.leagueTierId, .bronze, "入组从青铜起步")
        XCTAssertNotNil(s.leagueSalt)
        XCTAssertNil(s.pendingLeagueResult, "入组当周不结算")

        // salt 一次性生成后稳定不变。
        let salt = s.leagueSalt
        s.refreshLeague(now: date(2026, 8, 27))
        XCTAssertEqual(s.leagueSalt, salt)
    }

    // MARK: - store：周一结算（晋级 / 降级 / 每周只结一次）

    func testWeeklySettlePromotionPaysOnce() throws {
        var p = progressWithLessons(10)
        p.leagueSalt = "test-salt"
        p.leagueTier = "gold"
        p.leagueWeekKey = "2026-08-24"
        // 上周狂刷：xpHistory 拉满 → 必然第 1 名。
        p.xpHistory = ["2026-08-26": 999_999]
        p.gems = 0
        let s = try bootStore(with: p)

        s.refreshLeague(now: date(2026, 8, 31, 9))   // 下周一打开 app

        let result = try XCTUnwrap(s.pendingLeagueResult)
        XCTAssertEqual(result.weekKey, "2026-08-24")
        XCTAssertEqual(result.rank, 1)
        XCTAssertTrue(result.promoted)
        XCTAssertFalse(result.demoted)
        XCTAssertEqual(result.tierBefore, "gold")
        XCTAssertEqual(result.tierAfter, "sapphire")
        XCTAssertEqual(result.gems, 120, "第 1 名 100 + 晋级 20")
        XCTAssertEqual(s.gems, 120, "宝石结算时即入账")
        XCTAssertEqual(s.leagueTierId, .sapphire)
        XCTAssertEqual(s.leagueWeekKey, "2026-08-31")

        // 每周只结一次：同周再刷新不重复结算、不重复发奖。
        s.refreshLeague(now: date(2026, 9, 2, 9))
        XCTAssertEqual(s.gems, 120)
        XCTAssertEqual(s.pendingLeagueResult?.weekKey, "2026-08-24")
        XCTAssertEqual(s.leagueTierId, .sapphire)
    }

    func testWeeklySettleDemotionNoGems() throws {
        var p = progressWithLessons(10)
        p.leagueSalt = "test-salt"
        p.leagueTier = "gold"
        p.leagueWeekKey = "2026-08-24"
        // 上周没学：0 XP → 垫底（bot 周目标最低也有 120）。
        p.xpHistory = [:]
        p.gems = 0
        let s = try bootStore(with: p)

        s.refreshLeague(now: date(2026, 8, 31, 9))

        let result = try XCTUnwrap(s.pendingLeagueResult)
        XCTAssertEqual(result.rank, 16)
        XCTAssertTrue(result.demoted)
        XCTAssertFalse(result.promoted)
        XCTAssertEqual(result.tierAfter, "silver")
        XCTAssertEqual(result.gems, 0)
        XCTAssertEqual(s.gems, 0)
        XCTAssertEqual(s.leagueTierId, .silver)
    }

    func testWeeklySettleDiamondCapAndBronzeFloor() throws {
        // 钻石第 1：不晋级、奖励只有名次档 100。
        var top = progressWithLessons(10)
        top.leagueSalt = "test-salt"
        top.leagueTier = "diamond"
        top.leagueWeekKey = "2026-08-24"
        top.xpHistory = ["2026-08-26": 999_999]
        top.gems = 0
        let s1 = try bootStore(with: top)
        s1.refreshLeague(now: date(2026, 8, 31))
        XCTAssertEqual(s1.pendingLeagueResult?.promoted, false)
        XCTAssertEqual(s1.pendingLeagueResult?.gems, 100)
        XCTAssertEqual(s1.leagueTierId, .diamond)

        // 青铜垫底：不降级。
        var bottom = progressWithLessons(10)
        bottom.leagueSalt = "test-salt"
        bottom.leagueTier = "bronze"
        bottom.leagueWeekKey = "2026-08-24"
        bottom.xpHistory = [:]
        let s2 = try bootStore(with: bottom)
        s2.refreshLeague(now: date(2026, 8, 31))
        XCTAssertEqual(s2.pendingLeagueResult?.demoted, false)
        XCTAssertEqual(s2.leagueTierId, .bronze)
    }

    func testClearPendingLeagueResult() throws {
        var p = progressWithLessons(10)
        p.leagueSalt = "test-salt"
        p.leagueTier = "bronze"
        p.leagueWeekKey = "2026-08-24"
        let s = try bootStore(with: p)
        s.refreshLeague(now: date(2026, 8, 31))
        XCTAssertNotNil(s.pendingLeagueResult)
        s.clearPendingLeagueResult()
        XCTAssertNil(s.pendingLeagueResult)

        // 清除会持久化 —— 重启后不再弹同一张结算幕。
        let rebooted = ProgressStore()
        XCTAssertNil(rebooted.pendingLeagueResult)
    }

    func testLeagueWeeklyXpSumsSevenDays() throws {
        var p = progressWithLessons(10)
        p.xpHistory = [
            "2026-08-24": 10,   // 周一
            "2026-08-27": 20,   // 周四
            "2026-08-30": 30,   // 周日
            "2026-08-23": 999,  // 上周日 —— 不计入
            "2026-08-31": 999,  // 下周一 —— 不计入
        ]
        let s = try bootStore(with: p)
        XCTAssertEqual(s.leagueWeeklyXp(weekKey: "2026-08-24"), 60)
        // 数据不足一周（缺天）按可得数据尽力求和。
        XCTAssertEqual(s.leagueWeeklyXp(weekKey: "2026-08-17"), 999)
    }

    // MARK: - 单元挑战：XP ×2，宝石 drip 不翻倍

    func testExamLessonDoublesXpNotGems() {
        // 两节课放在不同的周三，让「当日首次达标 +20」两边条件一致，
        // 剩下的 drip 差异只可能来自 exam —— 断言相等即证明 drip 不翻倍。
        let normal = store.completeLesson(
            lessonId: "g1up-u1-kp1", correctCount: 8, questionCount: 10, now: date(2026, 3, 4)
        )
        XCTAssertEqual(normal.xpGained, 80)
        XCTAssertFalse(normal.examDoubled)

        // 挑战课：同样成绩 → 160 XP；宝石 drip 与普通课同档（2 星）。
        let exam = store.completeLesson(
            lessonId: "g1up-u1-exam", correctCount: 8, questionCount: 10, now: date(2026, 3, 11)
        )
        XCTAssertEqual(exam.xpGained, 160, "单元挑战 XP ×2")
        XCTAssertTrue(exam.examDoubled)
        XCTAssertEqual(exam.gemsGained, normal.gemsGained, "宝石 drip 不翻倍")
    }

    func testExamXpStacksWithWeekend() {
        let saturday = date(2026, 3, 7)   // 周六
        let outcome = store.completeLesson(
            lessonId: "g1up-u2-exam", correctCount: 8, questionCount: 10, now: saturday
        )
        XCTAssertEqual(outcome.xpGained, 320, "挑战 ×2 与周末 ×2 叠加 = ×4")
        XCTAssertTrue(outcome.examDoubled)
        XCTAssertTrue(outcome.weekendDoubled)
    }

    // MARK: - 路径挑战节点状态机（锁定 → 可挑战 → 征服）

    func testExamPathNodeStates() throws {
        let metas = [
            PathLessonMeta(id: "g1up-u1-kp1", title: "kp1", unitNumber: 1, unitTitle: "U1",
                           kpIndex: 0, kpTotal: 2, questionCount: 5),
            PathLessonMeta(id: "g1up-u1-kp2", title: "kp2", unitNumber: 1, unitTitle: "U1",
                           kpIndex: 1, kpTotal: 2, questionCount: 5),
        ]
        let slot = ExamSlot(
            lessonId: "g1up-u1-exam", title: "第 1 单元挑战",
            unitNumber: 1, unitTitle: "U1", questionCount: 10
        )
        func examNode() -> PathMapNode? {
            PathNodeBuilder.nodes(
                bookId: "g1up", lessons: metas, progressStore: store, examSlots: [slot]
            ).first { $0.kind == .exam }
        }

        // 单元未全通 → 锁定。
        var node = try XCTUnwrap(examNode())
        XCTAssertEqual(node.status, .locked)
        XCTAssertEqual(node.id, "g1up-u1-exam")
        XCTAssertEqual(node.title, "第 1 单元挑战")

        // 全通 → 可挑战（current）。
        store.completeLesson(lessonId: "g1up-u1-kp1", correctCount: 5, questionCount: 5)
        store.completeLesson(lessonId: "g1up-u1-kp2", correctCount: 5, questionCount: 5)
        node = try XCTUnwrap(examNode())
        XCTAssertEqual(node.status, .current)
        XCTAssertFalse(node.conquered)

        // 挑战 accuracy 0.9 ≥ 0.8 → completed + 征服金色态。
        store.completeLesson(lessonId: "g1up-u1-exam", correctCount: 9, questionCount: 10)
        node = try XCTUnwrap(examNode())
        XCTAssertEqual(node.status, .completed)
        XCTAssertTrue(node.conquered)

        // 无 examSlots（旧资产包）→ 不产出挑战节点。
        let noExam = PathNodeBuilder.nodes(bookId: "g1up", lessons: metas, progressStore: store)
        XCTAssertFalse(noExam.contains { $0.kind == .exam })
    }
}
