import Foundation

/// 存档备份中立信封（BackupEnvelope v1）—— packages/core/src/backup.ts 的
/// Swift 镜像。JSON 字段名与 core 完全一致，双端导出 / 导入互通。
///
/// 校验契约（与 core `validateBackup` 一致）：
///   - 拒收仅限结构性损坏：非 JSON 对象 / schema ≠ "cstf-backup" /
///     version 非正整数 / data 非对象；
///   - version > 1 前向兼容不拒收（未知字段忽略、缺字段补默认）；
///   - 字段级坏类型重置为默认值、非法条目丢弃（宽容解码）；
///   - 瞬态状态（红心计时、课程会话、今日 XP 等）不进信封。
enum Backup {

    static let schema = "cstf-backup"
    static let version = 1

    // ============================================================
    // 载荷类型（JSON 键与 core 完全一致）
    // ============================================================

    struct LessonResultPayload: Codable, Hashable {
        var stars: Int
        var accuracy: Double
        var completedAt: String
    }

    struct MistakePayload: Codable, Hashable {
        var lessonId: String
        var questionId: Int
        var box: Int?
        var correctCount: Int?
        var nextReviewDate: String?
        var graduated: Bool?
        /// 题面快照（可选）：携带时导入端优先使用。
        var question: Question?
    }

    struct EquippedPayload: Codable, Hashable {
        var mascotSkin: String
        var uiTheme: String
        var lessonBackdrop: String
    }

    /// data 载荷。Encodable 由编译器合成（可选字段为 nil 时省略键）；
    /// Decodable 在 extension 里手写宽容解码（坏类型 → 默认值）。
    struct DataPayload: Encodable, Hashable {
        var xp: Int = 0
        var streak: Int = 0
        var lastActiveDate: String = ""
        var streakFreezes: Int = Economy.initialFreezes
        var gems: Int = 0
        var lifetimeGems: Int = 0
        var hearts: Int = Economy.maxHearts
        var dailyGoal: Int = Economy.defaultDailyGoal
        var joinedDate: String?
        var completedLessons: [String: LessonResultPayload] = [:]
        /// 阅读完成表：**规范阅读 id**（`Reading.id`）→ 完成日期。
        /// 值必须是真值（非空串）：导入端判断「这篇读过没有」是看值的，
        /// 空串会被当成没读过 → 跨端重复领 XP（parity-1）。iOS 本地不记完成
        /// 日期，导出时按 `makeEnvelope` 的口径回退（见那里的注释）。
        /// 导出 / 校验都会跑 `Reading.normalizeMap` 归一化，双端共用同一个 key 空间。
        var completedReadings: [String: String] = [:]
        var perfectedLessons: [String: Bool]?
        var mistakesBank: [MistakePayload] = []
        var claimedChests: [String: Bool] = [:]
        /// key 为里程碑天数的字符串形式。
        var claimedStreakRewards: [String: Bool] = [:]
        /// 每日任务领取账本，键格式 `"YYYY-MM-DD:questId"`（questId 形如 `earnXP-60`）。
        /// 必须随档携带：否则导入端把它当瞬态清空、又从 xpHistory 复原了今日 XP，
        /// 已领过的任务会立刻回到「可领取」，导出再导入就能无限刷宝石。
        var claimedQuests: [String: Bool] = [:]
        var lastDailyRewardDate: String = ""
        var unlockedAchievements: [String: Bool] = [:]
        var claimedAchievements: [String: Bool]?
        var ownedCosmetics: [String: Bool] = [:]
        var equipped = EquippedPayload(
            mascotSkin: Cosmetics.defaultEquipped.mascotSkin,
            uiTheme: Cosmetics.defaultEquipped.uiTheme,
            lessonBackdrop: Cosmetics.defaultEquipped.lessonBackdrop
        )
        var xpHistory: [String: Int] = [:]
        var leagueTier: String?
        var leagueWeekKey: String?
    }

    struct Envelope: Codable, Hashable {
        var schema: String
        var version: Int
        var exportedAt: String
        /// "ios" | "web"（坏值按 "web" 处理，仅元数据）。
        var platform: String
        var data: DataPayload

        private enum CodingKeys: String, CodingKey {
            case schema, version, exportedAt, platform, data
        }

        init(schema: String, version: Int, exportedAt: String, platform: String, data: DataPayload) {
            self.schema = schema
            self.version = version
            self.exportedAt = exportedAt
            self.platform = platform
            self.data = data
        }

        /// 宽容解码：exportedAt / platform 是元数据，坏值不致命。
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            schema = try c.decode(String.self, forKey: .schema)
            version = try c.decode(Int.self, forKey: .version)
            exportedAt = ((try? c.decodeIfPresent(String.self, forKey: .exportedAt)) ?? nil) ?? ""
            platform = ((try? c.decodeIfPresent(String.self, forKey: .platform)) ?? nil) ?? "web"
            data = try c.decode(DataPayload.self, forKey: .data)
        }
    }

    // ============================================================
    // 校验（导入端）
    // ============================================================

    enum ValidationError: Error, LocalizedError, Equatable {
        case notJSONObject
        case wrongSchema
        case badVersion
        case missingData

        var errorDescription: String? {
            switch self {
            case .notJSONObject: return "备份内容不是 JSON 对象"
            case .wrongSchema:   return "这不是本应用的备份文件"
            case .badVersion:    return "备份版本号缺失或不合法"
            case .missingData:   return "备份缺少 data 字段"
            }
        }
    }

    /// 校验一段未知输入是否是可导入的备份信封。
    /// 结构性损坏 → .failure；否则返回补全默认值后的完整信封。
    static func validate(_ raw: Data) -> Result<Envelope, ValidationError> {
        guard let top = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else {
            return .failure(.notJSONObject)
        }
        guard top["schema"] as? String == schema else {
            return .failure(.wrongSchema)
        }
        // version 必须是正整数（version > BACKUP_VERSION 前向兼容不拒收）。
        guard let versionNumber = top["version"] as? NSNumber,
              versionNumber.doubleValue == versionNumber.doubleValue.rounded(),
              versionNumber.intValue >= 1
        else {
            return .failure(.badVersion)
        }
        guard top["data"] is [String: Any] else {
            return .failure(.missingData)
        }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: raw) else {
            // DataPayload 解码是全宽容的，理论上到不了这里 —— 兜底按结构损坏。
            return .failure(.notJSONObject)
        }
        var normalized = envelope
        if normalized.platform != "ios" && normalized.platform != "web" {
            normalized.platform = "web"
        }
        return .success(normalized)
    }

    // ============================================================
    // 导出：UserProgress → Envelope
    // ============================================================

    static func makeEnvelope(from p: UserProgress, exportedAt: Date = Date()) -> Envelope {
        var data = DataPayload()
        data.xp = max(0, p.xp)
        data.streak = max(0, p.streak)
        data.lastActiveDate = p.lastActiveDate
        data.streakFreezes = max(0, p.streakFreezes ?? Economy.initialFreezes)
        data.gems = max(0, p.gems ?? 0)
        data.lifetimeGems = max(0, p.lifetimeGems ?? (p.gems ?? 0))
        data.hearts = min(max(0, p.hearts ?? Economy.maxHearts), Economy.maxHearts)
        data.dailyGoal = max(0, p.dailyGoal ?? Economy.defaultDailyGoal)
        data.joinedDate = p.joinedDate

        data.completedLessons = Dictionary(uniqueKeysWithValues: p.completedLessons.map { id, r in
            (id, LessonResultPayload(
                stars: min(max(1, r.stars), 3),
                accuracy: min(max(0, r.accuracy), 1),
                completedAt: r.completedAt
            ))
        })
        // 阅读键一律归一化成规范 id（`reading:{kind}:{rawId}`）后再进信封。
        //
        // 值的口径（parity-1）：iOS 本地只存「读过哪些」的 id 列表、不记完成日期，
        // 但**绝不能导成空串** —— 导入端（web）判断「这篇读过没有」是看值真不真的，
        // 空串一律被当成没读过，iOS→web 之后每篇阅读都能再领一次 XP。
        // 统一回退成 `joinedDate`（这台设备的首次使用日，一定不晚于真实完成日；
        // 拿不到就用导出当天），保证值恒为真值。
        let readingCompletedDate: String = {
            if let joined = p.joinedDate, !joined.isEmpty { return joined }
            return SRS.todayString(now: exportedAt)
        }()
        data.completedReadings = Reading.normalizeMap(
            Dictionary(
                (p.completedReadings ?? []).map { ($0, readingCompletedDate) },
                uniquingKeysWith: { a, _ in a }
            )
        )
        let perfected = p.completedLessons.filter { $0.value.stars >= 3 }.map(\.key)
        if !perfected.isEmpty {
            data.perfectedLessons = Dictionary(uniqueKeysWithValues: perfected.map { ($0, true) })
        }
        data.mistakesBank = p.mistakesBank.map { entry in
            MistakePayload(
                lessonId: entry.lessonId,
                questionId: entry.question.id,
                box: entry.box,
                correctCount: entry.correctCount,
                nextReviewDate: entry.nextReviewDate,
                graduated: entry.graduated,
                question: entry.question
            )
        }
        data.claimedChests = (p.claimedChests ?? [:]).filter(\.value)
        data.claimedStreakRewards = Dictionary(
            (p.claimedStreakRewards ?? []).map { (String($0), true) },
            uniquingKeysWith: { a, _ in a }
        )
        // 每日任务领取账本必须随档走，否则「导出 → 导入」能把已领的任务刷回可领。
        data.claimedQuests = Dictionary(
            (p.claimedQuests ?? []).map { ($0, true) },
            uniquingKeysWith: { a, _ in a }
        )
        data.lastDailyRewardDate = p.lastDailyRewardDate ?? ""
        data.unlockedAchievements = Dictionary(
            uniqueKeysWithValues: (p.unlockedAchievements ?? []).map { ($0, true) }
        )
        data.claimedAchievements = Dictionary(
            uniqueKeysWithValues: (p.claimedAchievements ?? []).map { ($0, true) }
        )
        data.ownedCosmetics = Dictionary(
            uniqueKeysWithValues: (p.ownedCosmetics ?? []).map { ($0, true) }
        )
        data.equipped = EquippedPayload(
            mascotSkin: p.equippedMascotSkin ?? Cosmetics.defaultEquipped.mascotSkin,
            uiTheme: p.equippedTheme ?? Cosmetics.defaultEquipped.uiTheme,
            lessonBackdrop: p.equippedBackdrop ?? Cosmetics.defaultEquipped.lessonBackdrop
        )
        data.xpHistory = (p.xpHistory ?? [:]).filter { $0.value >= 0 }
        data.leagueTier = p.leagueTier
        data.leagueWeekKey = p.leagueWeekKey

        return Envelope(
            schema: schema,
            version: version,
            exportedAt: SRS.isoFormatter.string(from: exportedAt),
            platform: "ios",
            data: data
        )
    }

    /// 导出为 JSON 数据（键排序，双端 diff 友好）。
    static func encode(_ envelope: Envelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }

    // ============================================================
    // 导入：Envelope → UserProgress
    // ============================================================

    /// lessonId（"g1up-u3-kp2" / "g1up-u3-exam"）→ bookId（"g1up"）。
    static func bookId(fromLessonId lessonId: String) -> String? {
        guard let range = lessonId.range(of: "-u") else { return nil }
        let prefix = String(lessonId[..<range.lowerBound])
        return prefix.isEmpty ? nil : prefix
    }

    /// 把校验后的信封落成一份全新的 UserProgress。
    ///
    /// - `questionLookup`: 错题条目缺少题面快照时，从本地题库找回题目；
    ///   找不到的条目丢弃（跨端题库可能不齐）。
    /// - `keepLeagueSalt`: 联赛 salt 是设备指纹，不随备份迁移 —— 保留本机的。
    /// - `keepReviewHeartDate`: 复习补心账本（`lastReviewHeartDate`）是**本机按天
    ///   的防刷账本**，不进信封也不随档迁移 —— 必须原样保留本机值。整体覆盖会把它
    ///   抹成 nil，「补 1 心 → 导出 → 导入」就能当天反复补心到满（iosretention-4）。
    ///   跟着信封走也不行：导入一份昨天的老档同样会把今天的账本刷回可领。
    /// - `now`: 导入时刻。红心不满时按它补种回心计时（红心计时本身不进信封，
    ///   但「缺心却没有计时」会让红心永不再生 —— 导入侧必须显式设置）。
    /// - `today`: 「今天」的日期键（可注入便于测试）。今日 XP / 当日目标进度
    ///   从 `xpHistory[today]` 复原，与 web importBackup 同口径 —— 否则同日
    ///   导入后当日目标归零，再完一课就能重复领 +20💎。
    /// - 真·瞬态不导入：课程会话、今日任务计数。
    static func userProgress(
        from envelope: Envelope,
        questionLookup: (String, Int) -> Question? = { _, _ in nil },
        keepLeagueSalt: String? = nil,
        keepReviewHeartDate: String? = nil,
        now: Date = Date(),
        today: String = SRS.todayString()
    ) -> UserProgress {
        let d = envelope.data
        var p = UserProgress(
            xp: max(0, d.xp),
            streak: max(0, d.streak),
            lastActiveDate: d.lastActiveDate,
            completedLessons: [:],
            mistakesBank: []
        )

        p.completedLessons = Dictionary(uniqueKeysWithValues: d.completedLessons.map { id, r in
            (id, LessonResult(
                lessonId: id,
                stars: min(max(1, r.stars), 3),
                accuracy: min(max(0, r.accuracy), 1),
                completedAt: r.completedAt
            ))
        })

        p.mistakesBank = d.mistakesBank.compactMap { m in
            guard let question = m.question ?? questionLookup(m.lessonId, m.questionId) else {
                return nil   // 本地题库找不到又没快照 —— 丢弃该条
            }
            return MistakeEntry(
                lessonId: m.lessonId,
                lessonTitle: nil,
                question: question,
                addedAt: envelope.exportedAt,
                box: m.box.map { min(max(1, $0), 3) },
                correctCount: m.correctCount.map { max(0, $0) },
                lastReviewedAt: nil,
                nextReviewDate: m.nextReviewDate,
                graduated: m.graduated
            )
        }

        let hearts = min(max(0, d.hearts), Economy.maxHearts)
        p.hearts = hearts
        // 缺心必须带着回心计时落地：只清空计时会让导入来的 0 心存档永远
        // 停在 0 心（tickHeartRecharge 没有计时可推进）。满心则明确清空。
        p.nextHeartAt = hearts < Economy.maxHearts
            ? (now.timeIntervalSince1970 + Double(Economy.heartRegenSeconds)) * 1000
            : nil
        p.gems = max(0, d.gems)
        p.lifetimeGems = max(max(0, d.lifetimeGems), max(0, d.gems))
        p.dailyGoal = d.dailyGoal > 0 ? d.dailyGoal : Economy.defaultDailyGoal
        p.streakFreezes = max(0, d.streakFreezes)
        p.freezesMigrated = true                              // 免掉护盾补发迁移
        p.joinedDate = d.joinedDate
        // 阅读键落成规范 id —— 与本地存储、web 端同一个 key 空间。
        p.completedReadings = Reading.normalizeIds(Array(d.completedReadings.keys))
        p.claimedChests = d.claimedChests.filter(\.value)
        p.claimedStreakRewards = d.claimedStreakRewards
            .filter(\.value)
            .compactMap { Int($0.key) }
            .sorted()
        p.lastDailyRewardDate = d.lastDailyRewardDate.isEmpty ? nil : d.lastDailyRewardDate
        p.unlockedAchievements = d.unlockedAchievements.filter(\.value).keys.sorted()
        p.claimedAchievements = (d.claimedAchievements ?? [:]).filter(\.value).keys.sorted()
        p.ownedCosmetics = d.ownedCosmetics.filter(\.value).keys.sorted()
        p.equippedMascotSkin = d.equipped.mascotSkin
        p.equippedTheme = d.equipped.uiTheme
        p.equippedBackdrop = d.equipped.lessonBackdrop
        let history = d.xpHistory.filter { $0.value >= 0 }
        p.xpHistory = history

        // 今日 XP 从 xpHistory 复原（与 web 同口径）：不复原的话当日目标进度
        // 归零，同一天里再完一节课就能重复吃到 +20💎 的达标奖励。
        if let todayXp = history[today] {
            p.todayXp = todayXp
            p.lastXpDate = today
        } else {
            p.todayXp = 0
            p.lastXpDate = nil
        }
        // 每日任务领取账本随档恢复，否则「导出 → 导入」= 任务重置 = 无限刷宝石。
        p.claimedQuests = d.claimedQuests.filter(\.value).keys.sorted()
        // 复习补心账本留本机值（同上：随档走 / 被抹掉都能刷心）。
        p.lastReviewHeartDate = keepReviewHeartDate

        // 联赛：段位随备份走（未知段位由 League.tier 容错落回青铜），
        // salt 留本机，周键沿用备份（周一结算逻辑自会对齐）。
        p.leagueSalt = keepLeagueSalt
        p.leagueTier = d.leagueTier
        p.leagueWeekKey = d.leagueWeekKey

        return p
    }
}

// ============================================================
// 宽容解码（坏类型 → 默认值 / 非法条目丢弃）
// ============================================================

extension Backup.DataPayload: Decodable {

    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ s: String) { stringValue = s }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    /// 单值宽容盒：目标类型解不出来 → nil（不让整体解码失败）。
    private struct Lossy<T: Decodable>: Decodable {
        let value: T?
        init(from decoder: Decoder) throws {
            value = try? T(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: AnyKey.self) else { return }

        func int(_ key: String) -> Int? {
            if let v = ((try? c.decodeIfPresent(Int.self, forKey: AnyKey(key))) ?? nil) { return v }
            // web 端可能导出 12.0 这类整数值的浮点
            if let v = ((try? c.decodeIfPresent(Double.self, forKey: AnyKey(key))) ?? nil),
               v == v.rounded() { return Int(v) }
            return nil
        }
        func string(_ key: String) -> String? {
            ((try? c.decodeIfPresent(String.self, forKey: AnyKey(key))) ?? nil)
        }
        func flags(_ key: String) -> [String: Bool] {
            let raw = ((try? c.decodeIfPresent([String: Lossy<Bool>].self, forKey: AnyKey(key))) ?? nil) ?? [:]
            return raw.compactMapValues { $0.value }.filter(\.value)
        }

        if let v = int("xp"), v >= 0 { xp = v }
        if let v = int("streak"), v >= 0 { streak = v }
        if let v = string("lastActiveDate") { lastActiveDate = v }
        if let v = int("streakFreezes"), v >= 0 { streakFreezes = v }
        if let v = int("gems"), v >= 0 { gems = v }
        if let v = int("lifetimeGems"), v >= 0 { lifetimeGems = v }
        if let v = int("hearts"), v >= 0 { hearts = v }
        if let v = int("dailyGoal"), v >= 0 { dailyGoal = v }
        joinedDate = string("joinedDate")

        let lessons = ((try? c.decodeIfPresent(
            [String: Lossy<Backup.LessonResultPayload>].self, forKey: AnyKey("completedLessons")
        )) ?? nil) ?? [:]
        completedLessons = lessons.compactMapValues(\.value)

        let readings = ((try? c.decodeIfPresent(
            [String: Lossy<String>].self, forKey: AnyKey("completedReadings")
        )) ?? nil) ?? [:]
        // 历史键（web 的 passage-*/story-*、iOS 的裸 id）在校验期就归一化成
        // 规范阅读 id —— 与 core validateBackup 同一处理点，幂等。
        completedReadings = Reading.normalizeMap(readings.compactMapValues(\.value))

        let perfected = ((try? c.decodeIfPresent(
            [String: Lossy<Bool>].self, forKey: AnyKey("perfectedLessons")
        )) ?? nil)
        if let perfected {
            perfectedLessons = perfected.compactMapValues(\.value).filter(\.value)
        }

        let mistakes = ((try? c.decodeIfPresent(
            [Lossy<Backup.MistakePayload>].self, forKey: AnyKey("mistakesBank")
        )) ?? nil) ?? []
        mistakesBank = mistakes.compactMap(\.value)

        claimedChests = flags("claimedChests")
        claimedStreakRewards = flags("claimedStreakRewards")
        claimedQuests = flags("claimedQuests")
        if let v = string("lastDailyRewardDate") { lastDailyRewardDate = v }
        unlockedAchievements = flags("unlockedAchievements")
        if c.contains(AnyKey("claimedAchievements")) {
            claimedAchievements = flags("claimedAchievements")
        }
        ownedCosmetics = flags("ownedCosmetics")

        if let e = ((try? c.decodeIfPresent(
            Lossy<Backup.EquippedPayload>.self, forKey: AnyKey("equipped")
        )) ?? nil)?.value {
            equipped = e
        }

        let history = ((try? c.decodeIfPresent(
            [String: Lossy<Int>].self, forKey: AnyKey("xpHistory")
        )) ?? nil) ?? [:]
        xpHistory = history.compactMapValues(\.value).filter { $0.value >= 0 }

        leagueTier = string("leagueTier")
        leagueWeekKey = string("leagueWeekKey")
    }
}
