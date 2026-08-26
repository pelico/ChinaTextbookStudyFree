import XCTest
@testable import ChinaTextbookStudy

// MARK: - PR #1 合并前评审修复的回归测试（IOS-STORE 分区）
//
// 覆盖：
//   - iosstore-1 / integration-1：iCloud 镜像绝不用空档 / 弱档盖掉真实备份
//   - iosstore-4：云端「读不到」≠「云端为空」，未知态只读不写
//   - iosstore-5：用户选「暂不恢复」后这台设备仍然能继续备份
//   - iosstore-6：恢复弹窗的本地闸门与引导进度无关
//   - webstore-1 (iOS)：导入 0 心存档后红心仍会自愈回血
//   - iosstore-2 / parity-3：导入恢复今日 XP 与每日任务账本（不可重复刷奖励）
//   - parity-4：断签当天先按 0 档发登录奖励、补卡成功后补发差额（与 web 等价）
//   - core-2 (iOS)：SRS 毕业用派生判定（黄金向量对照）
//   - parity-1 (iOS)：阅读完成 id 规范化 + 存量存档一次性迁移 + 导出日期非空
//   - iosretention-4 (store)：复习补心按天记账（含导出/导入 round-trip），堵死无限刷心
//   - parity-6 (iOS)：周窗口改日历周（周一→周日）
@MainActor
final class PRFixTests: XCTestCase {
    private var savedProgress: Data?
    private var savedPrefs: Data?
    private var store: ProgressStore!

    /// 云端备份状态机用到的 UserDefaults 键 —— 每个用例前后都清干净，
    /// 免得用例之间互相带状态（「已了断」「已确认读到过云端」都是持久标记）。
    private static let cloudDefaultsKeys = [
        ProgressStore.cloudRestoreHandledKey,
        ProgressStore.cloudArchiveDisownedKey,
        ProgressStore.cloudReadConfirmedKey,
        ProgressStore.cloudFirstReadAtKey,
    ]

    private func clearCloudDefaults() {
        for key in Self.cloudDefaultsKeys { UserDefaults.standard.removeObject(forKey: key) }
    }

    override func setUp() async throws {
        savedProgress = try? Data(contentsOf: PersistenceService.url(for: "progress.json"))
        savedPrefs = try? Data(contentsOf: PersistenceService.url(for: "prefs.json"))
        store = ProgressStore()
        store.resetProgress()
        // 清理必须排在 resetProgress 之后：重置本身会置位 cloudRestoreHandled
        // （本机重置 ≠ 新设备），否则每个用例都从「已做过决定」开始。
        clearCloudDefaults()
    }

    override func tearDown() async throws {
        clearCloudDefaults()
        for (name, data) in [("progress.json", savedProgress), ("prefs.json", savedPrefs)] {
            let url = PersistenceService.url(for: name)
            if let data { try? data.write(to: url) } else { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func day(_ s: String) -> Date { SRS.dateFormatter.date(from: s)! }

    /// 写一份定制存档再启动一个新 store（走真实的加载 / 迁移路径）。
    private func bootStore(with progress: UserProgress) throws -> ProgressStore {
        try PersistenceService.write(progress, to: "progress.json")
        return ProgressStore()
    }

    private func makeQuestion(id: Int) -> Question {
        Question(
            id: id, type: .choice, score: 1, difficulty: 1, knowledgePoint: "kp",
            question: "q\(id)", options: ["A", "B"], answer: "A", explanation: "", audio: nil
        )
    }

    // ============================================================
    // iosstore-1 / integration-1：换机不丢档
    // ============================================================

    private func snapshot(xp: Int, lessons: Int) -> ProgressStore.CloudSnapshot {
        ProgressStore.CloudSnapshot(xp: xp, lessonCount: lessons)
    }

    /// 造一份「云端那样的」信封：xp + 若干节已完成的课。
    private func cloudArchive(xp: Int, lessons: Int, exportedAt: Date) -> Backup.Envelope {
        var p = UserProgress(xp: xp, streak: 3, lastActiveDate: "2025-08-26",
                             completedLessons: [:], mistakesBank: [])
        for i in 0..<lessons {
            let id = "g1up-u1-kp\(i)"
            p.completedLessons[id] = LessonResult(
                lessonId: id, stars: 3, accuracy: 1, completedAt: "2025-08-26T08:00:00Z"
            )
        }
        return Backup.makeEnvelope(from: p, exportedAt: exportedAt)
    }

    /// 云端有真实存档 + 本地是刚装好的空档 → 一个字节都不许写。
    func testEmptyLocalNeverOverwritesCloudBackup() {
        let cloud = snapshot(xp: 1200, lessons: 34)
        let fresh = snapshot(xp: 0, lessons: 0)
        XCTAssertFalse(
            ProgressStore.shouldMirrorBackup(local: fresh, cloud: cloud, restorePending: false),
            "新装设备的空档绝不能覆盖云端备份"
        )
        // 连云端读不到时也不写：空档没有任何值得备份的内容。
        XCTAssertFalse(ProgressStore.shouldMirrorBackup(local: fresh, cloud: nil, restorePending: false))
    }

    /// 用户还没决定要不要恢复期间，镜像必须完全让路。
    func testPendingRestoreBlocksMirror() {
        let cloud = snapshot(xp: 1200, lessons: 34)
        let strongLocal = snapshot(xp: 9999, lessons: 99)
        XCTAssertFalse(
            ProgressStore.shouldMirrorBackup(local: strongLocal, cloud: cloud, restorePending: true),
            "恢复弹窗还开着 → 不写云端"
        )
        XCTAssertTrue(
            ProgressStore.shouldMirrorBackup(local: strongLocal, cloud: cloud, restorePending: false)
        )
    }

    /// 本地进度弱于云端（任一维度更少）→ 保留云端。
    func testWeakerLocalNeverOverwritesCloud() {
        let cloud = snapshot(xp: 1200, lessons: 34)
        XCTAssertFalse(ProgressStore.shouldMirrorBackup(local: snapshot(xp: 300, lessons: 40), cloud: cloud, restorePending: false))
        XCTAssertFalse(ProgressStore.shouldMirrorBackup(local: snapshot(xp: 1300, lessons: 12), cloud: cloud, restorePending: false))
        // 不弱于云端才写（相等也算不弱：同一台设备重复镜像要能刷新 exportedAt）
        XCTAssertTrue(ProgressStore.shouldMirrorBackup(local: snapshot(xp: 1200, lessons: 34), cloud: cloud, restorePending: false))
        XCTAssertTrue(ProgressStore.shouldMirrorBackup(local: snapshot(xp: 1500, lessons: 40), cloud: cloud, restorePending: false))
        // 云端本身是空档 → 随便覆盖
        XCTAssertTrue(ProgressStore.shouldMirrorBackup(local: snapshot(xp: 10, lessons: 1), cloud: snapshot(xp: 0, lessons: 0), restorePending: false))
    }

    /// 待恢复期间 refreshForNow 不发奖、不结算、不镜像；弹窗依然立着。
    func testRefreshWhilePendingRestoreKeepsPromptAndSkipsSettlement() {
        let envelope = Backup.makeEnvelope(from: {
            var p = UserProgress(xp: 1200, streak: 9, lastActiveDate: "2026-08-25",
                                 completedLessons: [:], mistakesBank: [])
            p.completedLessons["g1up-u1-kp1"] = LessonResult(
                lessonId: "g1up-u1-kp1", stars: 3, accuracy: 1, completedAt: "2026-08-25T08:00:00Z"
            )
            return p
        }(), exportedAt: day("2026-08-25"))

        store.pendingCloudRestore = envelope
        let gemsBefore = store.gems
        store.refreshForNow(now: day("2026-08-26"))

        XCTAssertNotNil(store.pendingCloudRestore, "恢复弹窗不能被 refreshForNow 吞掉")
        XCTAssertEqual(store.gems, gemsBefore, "还没决定恢复 → 不该在空档上发登录奖励")
        XCTAssertFalse(
            ProgressStore.shouldMirrorBackup(
                local: ProgressStore.CloudSnapshot(store.progress),
                cloud: ProgressStore.CloudSnapshot(envelope),
                restorePending: store.pendingCloudRestore != nil
            )
        )
    }

    /// 用户选「暂不」之后，**空档**仍然不许覆盖云端（闸门 2 保留）。
    func testDeclineRestoreStillProtectsCloudBackupFromEmptySave() {
        let cloud = snapshot(xp: 1200, lessons: 34)
        store.pendingCloudRestore = Backup.makeEnvelope(from: store.progress, exportedAt: day("2026-08-26"))
        store.declineCloudRestore(now: day("2026-08-26"))

        XCTAssertNil(store.pendingCloudRestore)
        XCTAssertFalse(
            ProgressStore.shouldMirrorBackup(
                local: ProgressStore.CloudSnapshot(store.progress),   // 还是一份空档
                cloud: cloud,
                restorePending: false,
                cloudArchiveDisowned: true
            ),
            "「暂不恢复」不等于「拿空档去洗掉云端存档」"
        )
        // 决定做完了，被挡下的每日结算要补上（首次登录奖励 5💎）。
        XCTAssertNotNil(store.pendingDailyReward)
    }

    /// iosstore-5（第一轮修复引入的倒退）：选「暂不恢复 / 从头开始」之后，
    /// 本机「重置学习进度」不等于换了新设备：重置后本地是空档，如果不记下
    /// 这个决定，下次回前台就会弹「发现 iCloud 备份」，用户顺手点「从头开始」
    /// 就会 disown 掉云端那份真备份，下一课把一年的进度洗成空档。
    func testResetProgressIsNotMistakenForANewDevice() {
        // 前置：从没对云端那份档做过决定（全新安装时云端为空的老用户就是这样）。
        XCTAssertTrue(ProgressStore.shouldOfferCloudRestore(
            local: snapshot(xp: 0, lessons: 0),
            restoreHandled: UserDefaults.standard.bool(forKey: ProgressStore.cloudRestoreHandledKey),
            promptShowing: false
        ), "空档 + 没做过决定 = 该问「要恢复吗」")

        store.resetProgress()

        XCTAssertTrue(
            UserDefaults.standard.bool(forKey: ProgressStore.cloudRestoreHandledKey),
            "重置必须落盘成一次决定"
        )
        XCTAssertFalse(ProgressStore.shouldOfferCloudRestore(
            local: snapshot(xp: 0, lessons: 0),
            restoreHandled: UserDefaults.standard.bool(forKey: ProgressStore.cloudRestoreHandledKey),
            promptShowing: false
        ), "重置之后不该再把本机当成新设备来问")

        // 重置不 disown：云端那份档仍受单调性保护，弱档洗不掉它。
        let archive = cloudArchive(xp: 5000, lessons: 300, exportedAt: day("2025-08-26"))
        XCTAssertFalse(store.isCloudArchiveDisowned(archive), "重置不该顺手放弃云端存档")
        XCTAssertFalse(ProgressStore.shouldMirrorBackup(
            local: snapshot(xp: 30, lessons: 1),
            cloud: ProgressStore.CloudSnapshot(archive),
            restorePending: false,
            cloudArchiveDisowned: store.isCloudArchiveDisowned(archive)
        ), "重置后重新开始的弱档不该覆盖云端的年度备份")
    }

    /// 这台设备必须**还能继续备份** —— 否则新学习者学一整年也写不出一份档，
    /// 自己再换机时一年进度全丢。
    func testDeclineDisownsCloudArchiveSoDeviceKeepsBackingUp() {
        let old = cloudArchive(xp: 5000, lessons: 300, exportedAt: day("2025-08-26"))
        store.pendingCloudRestore = old
        store.declineCloudRestore(now: day("2026-08-26"))

        XCTAssertTrue(store.isCloudArchiveDisowned(old), "「暂不恢复」必须落盘成一次了断")

        // 学了一整年（900 XP / 40 课）仍然弱于那份被放弃的旧档 —— 闸门要放行。
        XCTAssertTrue(ProgressStore.shouldMirrorBackup(
            local: snapshot(xp: 900, lessons: 40),
            cloud: ProgressStore.CloudSnapshot(old),
            restorePending: false,
            cloudArchiveDisowned: store.isCloudArchiveDisowned(old)
        ), "已经了断的旧档不该再拦着这台设备备份")

        // 换成另一份档（别的设备刚推上来的真备份）：不在了断范围内，照旧保护。
        let other = cloudArchive(xp: 4000, lessons: 200, exportedAt: day("2026-08-20"))
        XCTAssertFalse(store.isCloudArchiveDisowned(other))
        XCTAssertFalse(ProgressStore.shouldMirrorBackup(
            local: snapshot(xp: 900, lessons: 40),
            cloud: ProgressStore.CloudSnapshot(other),
            restorePending: false,
            cloudArchiveDisowned: store.isCloudArchiveDisowned(other)
        ), "没被了断过的存档仍受单调性保护")
    }

    /// iosstore-4：云端「读不到」不能当成「云端为空」。
    func testUnknownCloudStateIsReadOnly() {
        let strong = snapshot(xp: 900, lessons: 40)
        XCTAssertFalse(
            ProgressStore.shouldMirrorBackup(local: strong, cloud: nil, restorePending: false,
                                             cloudReadConfirmed: false),
            "本进程还没读到过云端值 → 只读不写"
        )
        XCTAssertTrue(
            ProgressStore.shouldMirrorBackup(local: strong, cloud: nil, restorePending: false,
                                             cloudReadConfirmed: true),
            "确认过云端没有备份 → 可以写第一份"
        )
    }

    /// 三态读：先未知，宽限期过了才敢认定「云端确实没有备份」。
    func testCloudReadStaysUnknownUntilGraceElapses() throws {
        let t0 = day("2026-08-26")
        let first = store.cloudRead(now: t0)
        if case .archive = first {
            throw XCTSkip("这台测试机的 iCloud 键值库里已经有备份，跳过空态断言")
        }
        XCTAssertEqual(first, .unknown, "首次读不到值只能是「未知」")
        XCTAssertEqual(store.cloudRead(now: t0.addingTimeInterval(60)), .unknown)
        XCTAssertEqual(
            store.cloudRead(now: t0.addingTimeInterval(ProgressStore.cloudUnknownGraceSeconds + 1)),
            .empty,
            "宽限期过了还是空的 → 认定云端没有备份，否则全新用户永远写不出第一份"
        )
    }

    /// iCloud 变更通知到货 = 云端状态已确认（后续镜像放行）。
    func testCloudChangeNotificationConfirmsCloudState() throws {
        let t0 = day("2026-08-26")
        if case .archive = store.cloudRead(now: t0) {
            throw XCTSkip("这台测试机的 iCloud 键值库里已经有备份，跳过空态断言")
        }
        store.handleCloudStoreChangedExternally(now: t0)
        XCTAssertEqual(store.cloudRead(now: t0), .empty)
    }

    /// iosstore-6：恢复弹窗的本地闸门只看「本地还是空档 + 还没做过决定」，
    /// **与引导做没做完无关** —— 换机首启时 KVS 常常还没到货，用户会先走完引导。
    func testRestoreOfferGateIgnoresOnboardingProgress() {
        let empty = snapshot(xp: 0, lessons: 0)
        XCTAssertTrue(ProgressStore.shouldOfferCloudRestore(
            local: empty, restoreHandled: false, promptShowing: false
        ), "引导走完但一节课没上的用户仍要能收到恢复提示")
        XCTAssertFalse(ProgressStore.shouldOfferCloudRestore(
            local: empty, restoreHandled: true, promptShowing: false
        ), "做过决定就不再打扰")
        XCTAssertFalse(ProgressStore.shouldOfferCloudRestore(
            local: snapshot(xp: 60, lessons: 1), restoreHandled: false, promptShowing: false
        ), "本地已经有进度 → 不该拿云端档盖掉")
        XCTAssertFalse(ProgressStore.shouldOfferCloudRestore(
            local: empty, restoreHandled: false, promptShowing: true
        ), "弹窗已经立着 → 不重复立")
    }

    // ============================================================
    // webstore-1 (iOS)：导入 0 心存档后红心自愈
    // ============================================================

    func testImportedZeroHeartSaveStillRecharges() throws {
        var source = UserProgress(xp: 100, streak: 1, lastActiveDate: "2026-08-26",
                                  completedLessons: [:], mistakesBank: [])
        source.hearts = 0
        source.nextHeartAt = nil
        let envelope = Backup.makeEnvelope(from: source, exportedAt: day("2026-08-26"))

        store.importBackup(envelope, now: day("2026-08-26"))
        XCTAssertEqual(store.hearts, 0)
        XCTAssertNotNil(store.progress.nextHeartAt, "缺心必须带着回心计时落地")

        // 5 分钟后回 1 颗心。
        store.tickHeartRecharge(now: day("2026-08-26").addingTimeInterval(ProgressStore.heartRechargeSeconds))
        XCTAssertEqual(store.hearts, 1)
    }

    /// 就算存档里「缺心 + 无计时」（老档 / 任何漏设计时的写入），tick 也会补种。
    func testTickHeartRechargeSelfHealsMissingTimer() throws {
        var p = UserProgress(xp: 0, streak: 0, lastActiveDate: "", completedLessons: [:], mistakesBank: [])
        p.hearts = 2
        p.nextHeartAt = nil
        let booted = try bootStore(with: p)

        booted.tickHeartRecharge(now: day("2026-08-26"))
        XCTAssertEqual(booted.hearts, 2)
        XCTAssertNotNil(booted.progress.nextHeartAt)

        booted.tickHeartRecharge(now: day("2026-08-26").addingTimeInterval(ProgressStore.heartRechargeSeconds * 2))
        XCTAssertEqual(booted.hearts, 4)
    }

    // ============================================================
    // iosstore-2 / parity-3：导入恢复今日 XP + 任务账本
    // ============================================================

    func testImportRestoresTodayXpSoDailyGoalBonusIsNotFarmable() {
        let today = day("2026-08-26")
        store.setDailyGoal(50)
        let first = store.completeLesson(lessonId: "g1up-u1-kp1", correctCount: 5, questionCount: 5, now: today)
        XCTAssertTrue(first.dailyGoalReachedNow, "60 XP（5 题全对 + 零失误 + 首次三星）跨过 50 的每日目标")

        let envelope = store.exportBackupEnvelope(now: today)
        store.resetProgress()
        store.importBackup(envelope, now: today)

        XCTAssertEqual(store.progress.todayXp, first.xpGained, "今日 XP 必须随 xpHistory 复原")
        XCTAssertEqual(store.progress.lastXpDate, SRS.todayString(now: today))
        XCTAssertTrue(store.dailyGoalReached)

        // 同日导入后再完一课：不能再吃一次 +20💎 的达标奖励。
        let second = store.completeLesson(lessonId: "g1up-u1-kp2", correctCount: 5, questionCount: 5, now: today)
        XCTAssertFalse(second.dailyGoalReachedNow, "当日目标只能跨过一次")
        XCTAssertEqual(
            second.gemsGained,
            Economy.lessonGemDrip(stars: 3, isFirstPerfect: true, crossedDailyGoal: false)
        )
    }

    /// 「导出 → 导入」不能把已领的每日任务刷回可领（claimedQuests 随档走）。
    func testBackupCarriesClaimedQuestLedger() {
        var p = UserProgress(xp: 60, streak: 1, lastActiveDate: "2026-08-26",
                             completedLessons: [:], mistakesBank: [])
        p.claimedQuests = ["2026-08-26:earnXP-60"]
        let envelope = Backup.makeEnvelope(from: p, exportedAt: day("2026-08-26"))
        XCTAssertEqual(envelope.data.claimedQuests["2026-08-26:earnXP-60"], true)

        let restored = Backup.userProgress(from: envelope, now: day("2026-08-26"), today: "2026-08-26")
        XCTAssertEqual(restored.claimedQuests, ["2026-08-26:earnXP-60"])
    }

    // ============================================================
    // parity-4：登录奖励与补卡的收益与 web 等价
    // ============================================================

    func testMakeupTopsUpDailyRewardToWebEquivalentTotal() throws {
        let now = day("2026-08-26")
        var p = UserProgress(xp: 500, streak: 5, lastActiveDate: "2026-08-20",
                             completedLessons: [:], mistakesBank: [])
        p.gems = 100
        p.lifetimeGems = 100
        p.streakFreezes = 2          // 缺勤 5 天，护盾兜不住 → 有效连胜 0
        p.freezesMigrated = true
        let booted = try bootStore(with: p)

        XCTAssertEqual(booted.salvageableStreak(now: now), 0)
        booted.claimDailyRewardIfDue(now: now)
        XCTAssertEqual(booted.gems, 100 + Economy.dailyRewardForStreak(0))    // 先按 0 档发 5💎
        XCTAssertEqual(booted.progress.lastDailyRewardStreak, 0)

        XCTAssertTrue(booted.makeUpYesterdayStreak(now: now))
        // 总额 = table[min(5,7)]，与 web「补卡决定之后再发」完全一致。
        let expected = 100 - Economy.streakMakeupCost + Economy.dailyRewardForStreak(5)
        XCTAssertEqual(booted.gems, expected)
        XCTAssertEqual(booted.pendingDailyReward?.gems, Economy.dailyRewardForStreak(5))
        XCTAssertEqual(booted.pendingDailyReward?.effectiveStreak, 5)

        // 幂等：再刷一次 refresh 不会二次补发。
        booted.refreshForNow(now: now)
        XCTAssertEqual(booted.gems, expected)
    }

    /// 不补卡的用户只拿 0 档 5💎（与 web 相同），不会被差额逻辑误发。
    func testNoMakeupKeepsTierZeroReward() throws {
        let now = day("2026-08-26")
        var p = UserProgress(xp: 500, streak: 5, lastActiveDate: "2026-08-20",
                             completedLessons: [:], mistakesBank: [])
        p.gems = 10
        p.streakFreezes = 2
        p.freezesMigrated = true
        let booted = try bootStore(with: p)

        booted.claimDailyRewardIfDue(now: now)
        booted.refreshForNow(now: now)
        XCTAssertEqual(booted.gems, 10 + Economy.dailyRewardForStreak(0))
    }

    // ============================================================
    // core-2 (iOS)：SRS 毕业派生判定（黄金向量）
    // ============================================================

    private struct GraduationVectorFile: Codable {
        let srsGraduation: [GraduationVector]
    }

    private struct GraduationVector: Codable {
        let graduated: Bool?
        let box: Int?
        let correctCount: Int?
        let expGraduated: Bool
    }

    private func loadGraduationVectors() throws -> [GraduationVector] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ChinaTextbookStudyTests/
            .deletingLastPathComponent()   // apps/mobile/
            .deletingLastPathComponent()   // apps/
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("packages/core/spec/golden-vectors.json")
        return try JSONDecoder().decode(GraduationVectorFile.self, from: try Data(contentsOf: url)).srsGraduation
    }

    func testSrsGraduationGoldenVectors() throws {
        for v in try loadGraduationVectors() {
            XCTAssertEqual(
                SRS.isGraduated(graduated: v.graduated, box: v.box, correctCount: v.correctCount),
                v.expGraduated,
                "isGraduated(graduated: \(String(describing: v.graduated)), box: \(String(describing: v.box)), correct: \(String(describing: v.correctCount)))"
            )
        }
    }

    /// 从 web 导入的条目往往只有 box + correctCount：派生判定必须把它挡在 due 队列外。
    func testDerivedGraduationKeepsImportedEntryOutOfDueQueue() {
        var p = UserProgress(xp: 0, streak: 0, lastActiveDate: "", completedLessons: [:], mistakesBank: [])
        p.mistakesBank = [
            MistakeEntry(
                lessonId: "g1up-u1-kp1", lessonTitle: nil, question: makeQuestion(id: 1),
                addedAt: "2026-08-01T08:00:00Z", box: 3, correctCount: 2,
                lastReviewedAt: nil, nextReviewDate: "2026-08-01", graduated: nil
            ),
            MistakeEntry(
                lessonId: "g1up-u1-kp1", lessonTitle: nil, question: makeQuestion(id: 2),
                addedAt: "2026-08-01T08:00:00Z", box: 3, correctCount: 1,
                lastReviewedAt: nil, nextReviewDate: "2026-08-01", graduated: nil
            ),
        ]
        let due = SRS.dueEntries(p.mistakesBank, now: day("2026-08-26"))
        XCTAssertEqual(due.map(\.question.id), [2], "box3+答对2 的条目已毕业，不该再到期")
    }

    // ============================================================
    // parity-1 (iOS)：阅读 id 规范化
    // ============================================================

    func testReadingIdNormalizationMatchesCoreRules() {
        XCTAssertEqual(Reading.normalize("chinese-g1up-p3"), "reading:listen:chinese-g1up-p3")
        XCTAssertEqual(Reading.normalize("chinese-g1up-p3-followup"), "reading:followup:chinese-g1up-p3")
        XCTAssertEqual(Reading.normalize("chinese-g3up-s1"), "reading:story:chinese-g3up-s1")
        XCTAssertEqual(Reading.normalize("passage-chinese-g1up-p3"), "reading:listen:chinese-g1up-p3")
        XCTAssertEqual(Reading.normalize("passage-chinese-g1up-p3-listen"), "reading:listen:chinese-g1up-p3")
        XCTAssertEqual(Reading.normalize("passage-chinese-g1up-p3-followup"), "reading:followup:chinese-g1up-p3")
        XCTAssertEqual(Reading.normalize("story-chinese-g3up-s1"), "reading:story:chinese-g3up-s1")
        XCTAssertEqual(Reading.normalize(""), "")
        // 幂等
        XCTAssertEqual(Reading.normalize("reading:story:chinese-g3up-s1"), "reading:story:chinese-g3up-s1")
        XCTAssertEqual(
            Reading.normalize(Reading.normalize("chinese-g1up-p3-followup")),
            "reading:followup:chinese-g1up-p3"
        )
    }

    /// 存量存档启动即迁移；老调用点传裸 id 也仍然认得出「已读」。
    func testLegacyReadingKeysMigrateOnLaunch() throws {
        var p = UserProgress(xp: 0, streak: 0, lastActiveDate: "", completedLessons: [:], mistakesBank: [])
        p.completedReadings = ["chinese-g1up-p3", "chinese-g1up-p3-followup", "chinese-g3up-s1"]
        let booted = try bootStore(with: p)

        XCTAssertEqual(booted.completedReadings, [
            "reading:listen:chinese-g1up-p3",
            "reading:followup:chinese-g1up-p3",
            "reading:story:chinese-g3up-s1",
        ])
        XCTAssertTrue(booted.isReadingCompleted("chinese-g1up-p3"))
        XCTAssertTrue(booted.isReadingCompleted("chinese-g1up-p3-followup"))
        XCTAssertTrue(booted.isReadingCompleted(.story, "chinese-g3up-s1"))
        XCTAssertFalse(booted.isReadingCompleted(.followup, "chinese-g3up-s1"))

        // 迁移后重复完成不再二次发 XP。
        let xpBefore = booted.progress.xp
        booted.completeReading(id: "chinese-g1up-p3", xp: 5, now: day("2026-08-26"))
        XCTAssertEqual(booted.progress.xp, xpBefore)
    }

    /// iOS 导出的阅读完成日期**不能是空串**：导入端按值判真，空串会被当成
    /// 没读过 → iOS→web 之后每篇阅读都能再领一次 XP（parity-1）。
    func testExportedReadingDatesAreNeverEmpty() {
        let today = day("2026-08-26")
        store.completeReading(id: "chinese-g1up-p3", xp: 5, now: today)
        store.completeReading(.story, rawId: "chinese-g3up-s1", xp: 5, now: today)

        let data = store.exportBackupEnvelope(now: today).data
        XCTAssertEqual(data.completedReadings.count, 2)
        for (key, date) in data.completedReadings {
            XCTAssertFalse(date.isEmpty, "\(key) 的完成日期不能导成空串")
            XCTAssertEqual(date, store.progress.joinedDate,
                           "口径：iOS 不记完成日期 → 统一回退成 joinedDate")
        }
        // 连 joinedDate 都没有的老档回退成导出当天，仍然是个真值。
        var legacy = UserProgress(xp: 10, streak: 0, lastActiveDate: "",
                                  completedLessons: [:], mistakesBank: [])
        legacy.joinedDate = nil
        legacy.completedReadings = ["reading:listen:chinese-g1up-p3"]
        let fallback = Backup.makeEnvelope(from: legacy, exportedAt: today)
        XCTAssertEqual(fallback.data.completedReadings["reading:listen:chinese-g1up-p3"],
                       SRS.todayString(now: today))
    }

    /// web 造的信封（`passage-*` / `story-*` 键）导入后与 iOS 本地键空间对齐。
    func testWebReadingKeysImportIntoCanonicalSpace() throws {
        let raw = """
        {"schema":"cstf-backup","version":1,"exportedAt":"2026-08-26T00:00:00.000Z","platform":"web",
         "data":{"xp":50,"completedReadings":{
            "passage-chinese-g1up-p3-listen":"2026-08-03",
            "passage-chinese-g1up-p3-followup":"2026-08-04",
            "story-chinese-g3up-s1":"2026-08-05"}}}
        """.data(using: .utf8)!
        guard case .success(let envelope) = Backup.validate(raw) else {
            return XCTFail("web 信封应当通过校验")
        }
        store.importBackup(envelope, now: day("2026-08-26"))
        XCTAssertTrue(store.isReadingCompleted(.listen, "chinese-g1up-p3"))
        XCTAssertTrue(store.isReadingCompleted(.followup, "chinese-g1up-p3"))
        XCTAssertTrue(store.isReadingCompleted(.story, "chinese-g3up-s1"))
    }

    // ============================================================
    // iosretention-4：复习补心按天记账
    // ============================================================

    func testReviewHeartIsOncePerDayAndGated() {
        let today = day("2026-08-26")
        store.loseHeart(now: today)
        store.loseHeart(now: today)
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts - 2)

        // 答对不足门槛 → 不发，也不记账。
        XCTAssertFalse(store.claimReviewHeartIfEligible(correctCount: Economy.reviewHeartMinCorrect - 1, now: today))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts - 2)

        XCTAssertTrue(store.claimReviewHeartIfEligible(correctCount: Economy.reviewHeartMinCorrect, now: today))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts - 1)

        // 「返回 → 再刷一轮」不再回心。
        XCTAssertFalse(store.claimReviewHeartIfEligible(correctCount: 20, now: today))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts - 1)

        // 第二天重新可领（隔夜红心已自然回满，先掉一颗再复习）。
        let tomorrow = day("2026-08-27")
        store.loseHeart(now: tomorrow)
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts - 1)
        XCTAssertTrue(store.claimReviewHeartIfEligible(correctCount: 5, now: tomorrow))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts)

        // 满心不发（也不会超上限）。
        XCTAssertFalse(store.claimReviewHeartIfEligible(correctCount: 5, now: day("2026-08-28")))
        XCTAssertEqual(store.hearts, ProgressStore.maxHearts)
    }

    /// 补心账本是**本机**的按天账本：导出再导入不能把它抹掉，
    /// 否则「做一轮错题补 1 心 → 导出 → 导入」当天就能反复补心到满。
    func testReviewHeartLedgerSurvivesExportImportRoundTrip() {
        let today = day("2026-08-26")
        store.loseHeart(now: today)
        store.loseHeart(now: today)
        XCTAssertTrue(store.claimReviewHeartIfEligible(correctCount: Economy.reviewHeartMinCorrect, now: today))
        let heartsAfterClaim = store.hearts

        let envelope = store.exportBackupEnvelope(now: today)
        store.importBackup(envelope, now: today)

        XCTAssertEqual(store.progress.lastReviewHeartDate, SRS.todayString(now: today),
                       "补心账本必须留本机值，不能被整体覆盖抹成 nil")
        XCTAssertFalse(store.canClaimReviewHeart(now: today))
        XCTAssertFalse(store.claimReviewHeartIfEligible(correctCount: 20, now: today),
                       "导出再导入不能把当天的补心刷回可领")
        XCTAssertEqual(store.hearts, heartsAfterClaim)
    }

    /// 别的设备导出的档（账本里是**昨天**）也不能把今天的补心刷回可领。
    func testImportingYesterdaysArchiveDoesNotResetReviewHeartLedger() {
        let today = day("2026-08-26")
        store.loseHeart(now: today)
        XCTAssertTrue(store.claimReviewHeartIfEligible(correctCount: 5, now: today))

        var stale = UserProgress(xp: 300, streak: 2, lastActiveDate: "2026-08-25",
                                 completedLessons: [:], mistakesBank: [])
        stale.lastReviewHeartDate = "2026-08-25"
        stale.hearts = 1
        store.importBackup(Backup.makeEnvelope(from: stale, exportedAt: day("2026-08-25")), now: today)

        XCTAssertEqual(store.progress.lastReviewHeartDate, SRS.todayString(now: today))
        XCTAssertFalse(store.claimReviewHeartIfEligible(correctCount: 20, now: today))
    }

    func testReviewHeartRewardMirrorsCore() {
        XCTAssertEqual(Economy.reviewHeartReward(correctCount: 4, hearts: 0), 0)
        XCTAssertEqual(Economy.reviewHeartReward(correctCount: 5, hearts: 0), 1)
        XCTAssertEqual(Economy.reviewHeartReward(correctCount: 99, hearts: Economy.maxHearts), 0)
    }

    // ============================================================
    // parity-6：日历周窗口
    // ============================================================

    func testWeekWindowIsCalendarWeekMondayFirst() {
        // 2026-08-26 是周三 → 本周应当是 08-24（周一）… 08-30（周日）。
        XCTAssertEqual(Week.weekStartKey(day("2026-08-26")), "2026-08-24")
        XCTAssertEqual(Week.weekStartKey(day("2026-08-30")), "2026-08-24")   // 周日仍属上一个周一
        XCTAssertEqual(Week.weekStartKey(day("2026-08-31")), "2026-08-31")   // 周一自身
        XCTAssertEqual(Week.weekDateKeys("2026-08-26").first, "2026-08-24")
        XCTAssertEqual(Week.weekDateKeys("2026-08-26").last, "2026-08-30")
        XCTAssertNil(Week.parseDateKey("2026-02-30"))
        XCTAssertNil(Week.parseDateKey("不是日期"))
    }

    func testRecentXpAndWeeklyTotalsUseCalendarWeek() {
        let wednesday = day("2026-08-26")
        _ = store.completeLesson(lessonId: "g1up-u1-kp1", correctCount: 5, questionCount: 5, now: wednesday)
        let thisWeekXp = store.progress.xp

        let week = store.weekXPEntries(now: wednesday)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.map(\.date), Week.weekDateKeys("2026-08-24"))
        XCTAssertEqual(store.todayIndexInWeek(now: wednesday), 2, "周三 → 下标 2（周一=0）")
        XCTAssertEqual(week[2].xp, thisWeekXp)

        XCTAssertEqual(store.weeklyTotal(now: wednesday), thisWeekXp)
        XCTAssertEqual(store.weeklyTotal(endingDaysAgo: 7, now: wednesday), 0, "上周没学过")

        // 上周（08-17 那一周）补一笔 XP → 只进上周总额，不污染本周。
        var p = store.progress
        p.xpHistory = (p.xpHistory ?? [:]).merging(["2026-08-19": 40]) { a, _ in a }
        try? PersistenceService.write(p, to: "progress.json")
        let booted = ProgressStore()
        XCTAssertEqual(booted.weeklyTotal(weeksAgo: 1, now: wednesday), 40)
        XCTAssertEqual(booted.weeklyTotal(weeksAgo: 0, now: wednesday), thisWeekXp)
    }
}
