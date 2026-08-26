import XCTest
@testable import ChinaTextbookStudy

// MARK: - Wave E2: 跳级 / 备份互通 / 报错 / 讲解标记
//
// 覆盖：备份导出→导入 round-trip（含 web 造的信封反向导入）、宽容校验契约
// （结构性损坏才拒收、坏字段落默认、version>1 前向兼容）、applyJumpUnlock
// 批量标记与零经济、跳级抽题（均匀 / 去重 / 确定性 / 小题库全取）、
// 报错记录去重与持久化、课前讲解已读标记持久化。

@MainActor
final class WaveE2Tests: XCTestCase {
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

    private func day(_ s: String) -> Date { SRS.dateFormatter.date(from: s)! }

    private func makeQuestion(id: Int, answer: String = "A") -> Question {
        Question(
            id: id, type: .choice, score: 1, difficulty: 1, knowledgePoint: "kp",
            question: "q\(id)", options: ["A", "B"], answer: answer, explanation: "", audio: nil
        )
    }

    // ============================================================
    // 备份：导出 → 导入 round-trip
    // ============================================================

    func testBackupRoundTripPreservesProgress() throws {
        // 造一份有血有肉的进度
        _ = store.completeLesson(lessonId: "g1up-u1-kp1", correctCount: 5, questionCount: 5, now: day("2026-08-19"))
        _ = store.completeLesson(lessonId: "g1up-u1-kp2", correctCount: 4, questionCount: 5, now: day("2026-08-20"))
        store.recordMistake(lessonId: "g1up-u1-kp2", lessonTitle: "课二", question: makeQuestion(id: 7))
        _ = store.reviewMistake(lessonId: "g1up-u1-kp2", questionId: 7, isCorrect: true, now: day("2026-08-20"))
        store.completeReading(id: "chinese-g1up-p1", xp: 5, now: day("2026-08-20"))
        store.claimChest("g1up-u1-c1")
        store.addGems(120)
        store.setDailyGoal(100)
        store.displayName = "小测试"

        let original = store.progress
        let envelope = store.exportBackupEnvelope(now: day("2026-08-20"))
        XCTAssertEqual(envelope.schema, "cstf-backup")
        XCTAssertEqual(envelope.version, 1)
        XCTAssertEqual(envelope.platform, "ios")

        // 走完整的「文件」通道：encode → validate → import
        let data = try Backup.encode(envelope)
        guard case .success(let validated) = Backup.validate(data) else {
            return XCTFail("导出的备份必须能通过自家校验")
        }

        store.resetProgress()
        XCTAssertTrue(store.progress.completedLessons.isEmpty)
        store.importBackup(validated)

        let restored = store.progress
        XCTAssertEqual(restored.xp, original.xp)
        XCTAssertEqual(restored.streak, original.streak)
        XCTAssertEqual(restored.lastActiveDate, original.lastActiveDate)
        XCTAssertEqual(restored.gems, original.gems)
        XCTAssertEqual(restored.lifetimeGems, original.lifetimeGems)
        XCTAssertEqual(restored.dailyGoal, original.dailyGoal)
        XCTAssertEqual(restored.joinedDate, original.joinedDate)
        XCTAssertEqual(Set(restored.completedLessons.keys), Set(original.completedLessons.keys))
        XCTAssertEqual(restored.completedLessons["g1up-u1-kp1"]?.stars, 3)
        XCTAssertEqual(restored.completedLessons["g1up-u1-kp2"]?.stars, 2)
        // 错题带题面快照 → 原样回来（SRS 状态保留）
        XCTAssertEqual(restored.mistakesBank.count, 1)
        XCTAssertEqual(restored.mistakesBank.first?.question.id, 7)
        XCTAssertEqual(restored.mistakesBank.first?.box, 2)
        XCTAssertEqual(restored.mistakesBank.first?.correctCount, 1)
        XCTAssertEqual(Set(restored.completedReadings ?? []), Set(original.completedReadings ?? []))
        XCTAssertEqual(restored.claimedChests?["g1up-u1-c1"], true)
        XCTAssertEqual(Set(restored.claimedStreakRewards ?? []), Set(original.claimedStreakRewards ?? []))
        XCTAssertEqual(Set(restored.unlockedAchievements ?? []), Set(original.unlockedAchievements ?? []))
        XCTAssertEqual(restored.xpHistory, original.xpHistory)
        // 瞬态不导：没有挂起会话、没有回心计时
        XCTAssertNil(restored.activeLesson)
        XCTAssertNil(restored.nextHeartAt)
        // 导入不触发护盾补发迁移
        XCTAssertEqual(restored.streakFreezes, original.streakFreezes)
    }

    // ============================================================
    // 备份：web 造的信封反向导入
    // ============================================================

    private let webEnvelopeJSON = """
    {
      "schema": "cstf-backup",
      "version": 1,
      "exportedAt": "2026-08-20T08:00:00.000Z",
      "platform": "web",
      "data": {
        "xp": 320,
        "streak": 5,
        "lastActiveDate": "2026-08-20",
        "streakFreezes": 1,
        "gems": 88,
        "lifetimeGems": 200,
        "hearts": 3,
        "dailyGoal": 100,
        "joinedDate": "2026-05-01",
        "completedLessons": {
          "g1up-u1-kp1": {"stars": 3, "accuracy": 1, "completedAt": "2026-08-01T00:00:00Z"},
          "g1up-u1-kp2": {"stars": 2, "accuracy": 0.85, "completedAt": "2026-08-02T00:00:00Z"}
        },
        "completedReadings": {"chinese-g1up-p1": "2026-08-03"},
        "perfectedLessons": {"g1up-u1-kp1": true},
        "mistakesBank": [
          {"lessonId": "g1up-u1-kp1", "questionId": 4, "box": 2, "correctCount": 1,
           "nextReviewDate": "2026-08-21", "graduated": false,
           "question": {"id": 4, "type": "choice", "score": 1, "difficulty": 1,
                        "knowledge_point": "kp", "question": "1+1=?",
                        "options": ["1", "2"], "answer": "2", "explanation": ""}},
          {"lessonId": "g1up-u9-kp9", "questionId": 9}
        ],
        "claimedChests": {"g1up-u1-c1": true},
        "claimedStreakRewards": {"3": true},
        "lastDailyRewardDate": "2026-08-20",
        "unlockedAchievements": {"lesson-1": true},
        "claimedAchievements": {"lesson-1": true},
        "ownedCosmetics": {"skin_crown": true},
        "equipped": {"mascotSkin": "skin_crown", "uiTheme": "theme_default", "lessonBackdrop": "backdrop_default"},
        "xpHistory": {"2026-08-20": 60},
        "leagueTier": "silver",
        "leagueWeekKey": "2026-08-17",
        "someFutureField": {"ignored": true}
      }
    }
    """

    func testImportWebEnvelope() throws {
        let data = Data(webEnvelopeJSON.utf8)
        guard case .success(let envelope) = Backup.validate(data) else {
            return XCTFail("web 信封必须通过校验")
        }
        XCTAssertEqual(envelope.platform, "web")

        let p = Backup.userProgress(from: envelope, keepLeagueSalt: "device-salt")
        XCTAssertEqual(p.xp, 320)
        XCTAssertEqual(p.streak, 5)
        XCTAssertEqual(p.lastActiveDate, "2026-08-20")
        XCTAssertEqual(p.streakFreezes, 1)
        XCTAssertEqual(p.gems, 88)
        XCTAssertEqual(p.lifetimeGems, 200)
        XCTAssertEqual(p.hearts, 3)
        XCTAssertEqual(p.dailyGoal, 100)
        XCTAssertEqual(p.joinedDate, "2026-05-01")
        XCTAssertEqual(p.completedLessons.count, 2)
        XCTAssertEqual(p.completedLessons["g1up-u1-kp1"]?.stars, 3)
        XCTAssertEqual(p.completedLessons["g1up-u1-kp2"]?.accuracy ?? 0, 0.85, accuracy: 0.0001)
        // 带快照的错题保留；没快照又查不到题库的丢弃
        XCTAssertEqual(p.mistakesBank.count, 1)
        XCTAssertEqual(p.mistakesBank.first?.question.answer, "2")
        XCTAssertEqual(p.completedReadings, ["chinese-g1up-p1"])
        XCTAssertEqual(p.claimedChests?["g1up-u1-c1"], true)
        XCTAssertEqual(p.claimedStreakRewards, [3])
        XCTAssertEqual(p.lastDailyRewardDate, "2026-08-20")
        XCTAssertEqual(p.unlockedAchievements, ["lesson-1"])
        XCTAssertEqual(p.claimedAchievements, ["lesson-1"])
        XCTAssertEqual(p.ownedCosmetics, ["skin_crown"])
        XCTAssertEqual(p.equippedMascotSkin, "skin_crown")
        XCTAssertEqual(p.xpHistory?["2026-08-20"], 60)
        XCTAssertEqual(p.leagueTier, "silver")
        XCTAssertEqual(p.leagueWeekKey, "2026-08-17")
        // salt 是设备指纹：保留本机的，不吃备份的
        XCTAssertEqual(p.leagueSalt, "device-salt")
        // 免掉护盾补发迁移（不然 1 个护盾会被顶到 2）
        XCTAssertEqual(p.freezesMigrated, true)
    }

    // ============================================================
    // 备份：校验契约（结构性损坏才拒收；坏字段落默认）
    // ============================================================

    func testValidateRejectsOnlyStructuralDamage() {
        // 非对象
        if case .success = Backup.validate(Data("[1,2,3]".utf8)) {
            XCTFail("数组不是信封")
        }
        // schema 不对
        let wrongSchema = #"{"schema": "other", "version": 1, "data": {}}"#
        XCTAssertEqual(Backup.validate(Data(wrongSchema.utf8)), .failure(.wrongSchema))
        // version 非正整数
        let badVersion = #"{"schema": "cstf-backup", "version": 0, "data": {}}"#
        XCTAssertEqual(Backup.validate(Data(badVersion.utf8)), .failure(.badVersion))
        let stringVersion = #"{"schema": "cstf-backup", "version": "1", "data": {}}"#
        XCTAssertEqual(Backup.validate(Data(stringVersion.utf8)), .failure(.badVersion))
        // data 缺失
        let noData = #"{"schema": "cstf-backup", "version": 1}"#
        XCTAssertEqual(Backup.validate(Data(noData.utf8)), .failure(.missingData))
    }

    func testValidateToleratesBadFieldsAndFutureVersions() {
        // version 2（未来版本）+ 坏类型字段 + 未知字段 → 仍然接受，坏字段落默认
        let json = """
        {
          "schema": "cstf-backup",
          "version": 2,
          "exportedAt": 42,
          "platform": "martian",
          "data": {
            "xp": "not-a-number",
            "streak": 3,
            "hearts": -5,
            "claimedChests": [1, 2],
            "completedLessons": {"good": {"stars": 2, "accuracy": 0.9, "completedAt": "x"},
                                 "bad": "nope"},
            "mysteryField": true
          }
        }
        """
        guard case .success(let envelope) = Backup.validate(Data(json.utf8)) else {
            return XCTFail("坏字段不该导致整体拒收")
        }
        XCTAssertEqual(envelope.version, 2)
        XCTAssertEqual(envelope.platform, "web")        // 坏平台按 web
        XCTAssertEqual(envelope.data.xp, 0)             // 坏类型 → 默认
        XCTAssertEqual(envelope.data.streak, 3)         // 好字段照读
        XCTAssertEqual(envelope.data.hearts, Economy.maxHearts) // 负数 → 默认
        XCTAssertTrue(envelope.data.claimedChests.isEmpty)      // 坏容器 → 空
        XCTAssertEqual(envelope.data.completedLessons.count, 1) // 坏条目丢弃
        XCTAssertEqual(envelope.data.completedLessons["good"]?.stars, 2)
    }

    // ============================================================
    // 跳级：applyJumpUnlock 批量标记 + 零经济
    // ============================================================

    func testApplyJumpUnlockMarksLessonsWithZeroEconomy() {
        // 先正常学一课，建立经济基线
        _ = store.completeLesson(lessonId: "g1up-u1-kp1", correctCount: 5, questionCount: 5, now: day("2026-08-20"))
        let xpBefore = store.progress.xp
        let gemsBefore = store.gems
        let streakBefore = store.progress.streak
        let priorResult = store.progress.completedLessons["g1up-u1-kp1"]

        let marked = store.applyJumpUnlock(
            lessonIds: ["g1up-u1-kp1", "g1up-u1-kp2", "g1up-u2-kp1"],
            now: day("2026-08-21")
        )

        // 已完成的不动，只补两节
        XCTAssertEqual(marked, 2)
        XCTAssertEqual(store.progress.completedLessons["g1up-u1-kp1"], priorResult)
        for id in ["g1up-u1-kp2", "g1up-u2-kp1"] {
            let r = store.progress.completedLessons[id]
            XCTAssertEqual(r?.stars, 1, "\(id) 应为 1 星")
            XCTAssertEqual(r?.accuracy ?? 0, 0.8, accuracy: 0.0001)
        }
        // 零经济：XP / 宝石 / 连胜全都不动
        XCTAssertEqual(store.progress.xp, xpBefore)
        XCTAssertEqual(store.gems, gemsBefore)
        XCTAssertEqual(store.progress.streak, streakBefore)
        // 幂等：再来一次什么都不标
        XCTAssertEqual(store.applyJumpUnlock(lessonIds: ["g1up-u1-kp2"]), 0)
    }

    // ============================================================
    // 跳级：抽题（均匀 / 去重 / 确定性 / 小题库全取）
    // ============================================================

    private func makeSources(lessons: Int, questionsEach: Int) -> [Jump.QuestionSource] {
        (1...lessons).map { l in
            Jump.QuestionSource(
                lessonId: "g1up-u1-kp\(l)",
                questions: (1...questionsEach).map { makeQuestion(id: $0) }
            )
        }
    }

    func testJumpSamplingEvenDedupedAndDeterministic() {
        let sources = makeSources(lessons: 4, questionsEach: 6)
        let a = Jump.sampleQuestions(sources: sources, seed: "s1")
        XCTAssertEqual(a.count, Jump.testSize)

        // 均匀：每课 15/4 → 3 或 4 道，最多差 1
        let perLesson = Dictionary(grouping: a, by: \.lessonId).mapValues(\.count)
        XCTAssertEqual(perLesson.count, 4)
        XCTAssertLessThanOrEqual((perLesson.values.max() ?? 0) - (perLesson.values.min() ?? 0), 1)

        // 课内不重复
        for (lessonId, picks) in Dictionary(grouping: a, by: \.lessonId) {
            XCTAssertEqual(Set(picks.map(\.question.id)).count, picks.count, "\(lessonId) 抽到重复题")
        }

        // 确定性：同 seed 完全一致；换 seed 出题顺序不同
        let b = Jump.sampleQuestions(sources: sources, seed: "s1")
        XCTAssertEqual(a.map { "\($0.lessonId)#\($0.question.id)" }, b.map { "\($0.lessonId)#\($0.question.id)" })
        let c = Jump.sampleQuestions(sources: sources, seed: "s2")
        XCTAssertNotEqual(a.map { "\($0.lessonId)#\($0.question.id)" }, c.map { "\($0.lessonId)#\($0.question.id)" })
    }

    func testJumpSamplingSmallPoolTakesAllAndDedupes() {
        // 题库不足 15：全取；同课重复 id 只留一次
        let dup = Jump.QuestionSource(
            lessonId: "g1up-u1-kp1",
            questions: [makeQuestion(id: 1), makeQuestion(id: 1), makeQuestion(id: 2)]
        )
        let tiny = Jump.sampleQuestions(sources: [dup], seed: "s")
        XCTAssertEqual(tiny.count, 2)
        XCTAssertEqual(Set(tiny.map(\.question.id)), [1, 2])
        // 空题库
        XCTAssertTrue(Jump.sampleQuestions(sources: [], seed: "s").isEmpty)
    }

    // ============================================================
    // 报错：去重 + 持久化
    // ============================================================

    func testReportsDedupeAndPersist() {
        XCTAssertTrue(store.addReport(
            lessonId: "g1up-u1-kp1", questionId: 3, kind: .questionWrong,
            userAnswer: "B", questionText: "1+1=?"
        ))
        // 同题同类型去重
        XCTAssertFalse(store.addReport(lessonId: "g1up-u1-kp1", questionId: 3, kind: .questionWrong))
        // 同题不同类型允许
        XCTAssertTrue(store.addReport(lessonId: "g1up-u1-kp1", questionId: 3, kind: .audioIssue))
        XCTAssertEqual(store.reports.count, 2)
        XCTAssertEqual(store.reports.first?.userAnswer, "B")
        XCTAssertEqual(store.reports.first?.questionText, "1+1=?")

        // 跨重启持久
        let reborn = ProgressStore()
        XCTAssertEqual(reborn.reports.count, 2)
        XCTAssertEqual(reborn.reports.map(\.kind), [.questionWrong, .audioIssue])

        // 导出的 JSON 可回读
        let data = try? store.exportReportsData()
        let decoded = data.flatMap { try? JSONDecoder().decode([QuestionReport].self, from: $0) }
        XCTAssertEqual(decoded?.count, 2)
    }

    // ============================================================
    // 课前讲解：已读标记持久化
    // ============================================================

    func testIntroSeenPersistsAcrossRelaunch() {
        XCTAssertFalse(store.hasSeenIntro("g1up-u1-kp1"))
        store.markIntroSeen("g1up-u1-kp1")
        store.markIntroSeen("g1up-u1-kp1")   // 幂等
        XCTAssertTrue(store.hasSeenIntro("g1up-u1-kp1"))

        let reborn = ProgressStore()
        XCTAssertTrue(reborn.hasSeenIntro("g1up-u1-kp1"))
        XCTAssertFalse(reborn.hasSeenIntro("g1up-u1-kp2"))
        XCTAssertEqual(reborn.progress.seenIntros, ["g1up-u1-kp1"])
    }
}
