import Foundation

/// 本地模拟联赛引擎 —— packages/core/src/league.ts 的 Swift 逐字镜像。
///
/// 纯单机联赛：每周把用户和 15 个「影子同学」（bot）放进同一个 16 人小组，
/// bot 的名字、周目标 XP、每日活跃曲线全部由 seed 确定性生成——
/// 同一台设备（同 salt）同一周同一段位，任何时刻重算得到完全相同的榜单。
///
/// 确定性来源：
///   seed = mix64(djb2Hash("\(weekKey)#\(tier)#\(salt)"))
///   - weekKey：本周周一的 YYYY-MM-DD（本地时区），见 `weekKeyFor`
///   - tier：段位 id（bronze/silver/...）
///   - salt：每台设备一次性生成的稳定随机串（ProgressStore 持久化）
///
/// ⚠️ 双端镜像铁律：BOT_NAME_POOL 全文同序、所有常量同值、所有取模偏移
/// （0x1000/0x2000/0x3000/0x4000/0x5000 系）同值。任何一端改动都会导致
/// 双端榜单漂移，禁止单独修改。GoldenVectorTests 的 league 组读取
/// packages/core/spec/golden-vectors.json 逐条对照。
enum League {

    // ============================================================
    // 🏆 段位
    // ============================================================

    enum TierId: String, Codable, CaseIterable, Hashable {
        case bronze, silver, gold, sapphire, ruby, diamond
    }

    struct Tier: Hashable {
        let id: TierId
        /// 儿童友好中文名
        let name: String
        /// 段位顺序（0 = 最低）
        let order: Int
        /// 段位主题色（24 位 RGB）
        let colorHex: UInt32
    }

    /// 6 个段位，order 升序 —— 与 core LEAGUE_TIERS 同值同序。
    static let tiers: [Tier] = [
        Tier(id: .bronze,   name: "青铜联赛",   order: 0, colorHex: 0xCD7F32),
        Tier(id: .silver,   name: "白银联赛",   order: 1, colorHex: 0xA8B8C8),
        Tier(id: .gold,     name: "黄金联赛",   order: 2, colorHex: 0xFFC800),
        Tier(id: .sapphire, name: "蓝宝石联赛", order: 3, colorHex: 0x1CB0F6),
        Tier(id: .ruby,     name: "红宝石联赛", order: 4, colorHex: 0xE0115F),
        Tier(id: .diamond,  name: "钻石联赛",   order: 5, colorHex: 0x54D7EC),
    ]

    /// 按 id 取段位（无效 id 落回青铜，容错老档）。
    static func tier(_ id: String) -> Tier {
        guard let tid = TierId(rawValue: id) else { return tiers[0] }
        return tiers.first { $0.id == tid } ?? tiers[0]
    }

    static func tier(_ id: TierId) -> Tier {
        tiers.first { $0.id == id } ?? tiers[0]
    }

    /// 晋级后的段位 id（钻石封顶）。
    static func nextTierId(_ id: TierId) -> TierId {
        tiers[min(tier(id).order + 1, tiers.count - 1)].id
    }

    /// 降级后的段位 id（青铜保底）。
    static func prevTierId(_ id: TierId) -> TierId {
        tiers[max(tier(id).order - 1, 0)].id
    }

    // ============================================================
    // 🔓 解锁 & 小组构成
    // ============================================================

    /// 累计完成 10 节课后解锁联赛。
    static let unlockLessons = 10

    /// 小组总人数：用户 + 15 个影子同学。
    static let groupSize = 16
    /// 每组影子同学（bot）数。
    static let botCount = 15

    // ============================================================
    // 📅 周键
    // ============================================================

    /// 本周周一的 YYYY-MM-DD（本地时区）。周一自身返回当天。
    /// 镜像 core：offset = (getDay() + 6) % 7；Swift weekday 周日=1。
    static func weekKeyFor(_ date: Date = Date()) -> String {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)   // 1=周日..7=周六
        let jsDay = weekday - 1                             // 0=周日..6=周六（= JS getDay）
        let offset = (jsDay + 6) % 7                        // 距本周周一的天数
        let monday = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: date))!
        return SRS.dateFormatter.string(from: monday)
    }

    /// date 相对 weekKey 周一的天序（周一=0 … 周日=6；早于周一为负，晚于周日 >6）。
    /// 本地日历日差，与 core `dayIndexInWeek` 等价。
    static func dayIndexInWeek(weekKey: String, date: Date) -> Int {
        guard let monday = SRS.dateFormatter.date(from: weekKey) else { return 0 }
        let cal = Calendar.current
        let from = cal.startOfDay(for: monday)
        let to = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: from, to: to).day ?? 0
    }

    // ============================================================
    // 🎲 确定性随机原语（与 core rng.ts 逐位一致）
    // ============================================================

    /// SplitMix64 finalizer —— 与 TS mix64 逐位一致（&+ / &* 环绕）。
    static func mix64(_ value: UInt64) -> UInt64 {
        var x = value &+ 0x9E37_79B9_7F4A_7C15
        x = (x ^ (x >> 30)) &* 0xBF58_476D_1CE4_E5B9
        x = (x ^ (x >> 27)) &* 0x94D0_49BB_1331_11EB
        return x ^ (x >> 31)
    }

    /// djb2 滚动哈希（UTF-8 字节，seed 5381，×33 + byte，64 位环绕）。
    static func djb2Hash(_ s: String) -> UInt64 {
        var hash: UInt64 = 5381
        for byte in s.utf8 { hash = hash &* 33 &+ UInt64(byte) }
        return hash
    }

    /// 当周种子：mix64(djb2("\(weekKey)#\(tier)#\(salt)"))。
    static func seed(weekKey: String, tier: TierId, salt: String) -> UInt64 {
        mix64(djb2Hash("\(weekKey)#\(tier.rawValue)#\(salt)"))
    }

    /// seed 派生的取模抽样：mix64(seed &+ offset) % count。
    private static func draw(seed: UInt64, offset: UInt64, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return Int(mix64(seed &+ offset) % UInt64(count))
    }

    // ============================================================
    // 🤖 影子同学（bot）
    // ============================================================

    struct Bot: Hashable, Identifiable {
        /// 稳定 id：`bot-<weekKey>-<tier>-<botIndex>`
        let id: String
        /// 儿童友好中文昵称（当周组内去重）
        let name: String
    }

    /// 儿童友好中文昵称池（36 个）。
    /// ⚠️ 必须与 core BOT_NAME_POOL 逐字同序——顺序参与去重抽取的结果。
    static let botNamePool: [String] = [
        "小猴淘淘", "兔子朵朵", "熊猫团团", "小鹿灵灵", "狐狸悠悠", "小象壮壮",
        "企鹅冰冰", "小猫咪咪", "小狗旺旺", "松鼠果果", "小鸟啾啾", "海豚蓝蓝",
        "小马奔奔", "刺猬球球", "考拉抱抱", "小龙腾腾", "河马呼呼", "小羊咩咩",
        "青蛙呱呱", "蜜蜂嗡嗡", "猫头鹰慧慧", "小熊憨憨", "仓鼠豆豆", "鹦鹉花花",
        "小鲸鱼泡泡", "蜗牛慢慢", "小老虎威威", "浣熊乐乐", "长颈鹿高高", "小恐龙吼吼",
        "雪人白白", "星星闪闪", "月亮弯弯", "太阳暖暖", "彩虹七七", "云朵飘飘",
    ]

    /// 各段位 bot 周目标 XP 区间（闭区间）—— 与 core TIER_XP_RANGES 同值。
    static let tierXpRanges: [TierId: (min: Int, max: Int)] = [
        .bronze:   (min: 40,  max: 260),
        .silver:   (min: 80,  max: 420),
        .gold:     (min: 120, max: 600),
        .sapphire: (min: 160, max: 800),
        .ruby:     (min: 200, max: 1000),
        .diamond:  (min: 240, max: 1200),
    ]

    /// 当周 15 个影子同学（名字在名池内不放回抽取，组内必然去重）。
    /// botIndex ∈ [0, 14] 与返回数组下标一致，是 `botXpAt` 的输入。
    static func botsForWeek(weekKey: String, tier: TierId, salt: String) -> [Bot] {
        let s = seed(weekKey: weekKey, tier: tier, salt: salt)
        var pool = botNamePool
        var bots: [Bot] = []
        for i in 0..<botCount {
            let idx = draw(seed: s, offset: UInt64(0x1000 + i), count: pool.count)
            let name = pool.remove(at: idx)
            bots.append(Bot(id: "bot-\(weekKey)-\(tier.rawValue)-\(i)", name: name))
        }
        return bots
    }

    /// 某 bot 的周目标 XP（段位区间内均匀取值，seed 确定）。
    static func botWeeklyGoal(weekKey: String, tier: TierId, salt: String, botIndex: Int) -> Int {
        let s = seed(weekKey: weekKey, tier: tier, salt: salt)
        let range = tierXpRanges[tier] ?? tierXpRanges[.bronze]!
        let span = range.max - range.min + 1
        return range.min + draw(seed: s, offset: UInt64(0x2000 + botIndex), count: span)
    }

    /// 某 bot 在 date 时刻的累计周 XP（core `botXpAt` 的逐位镜像）：
    ///   - 周一 00:00 起步为 0，随时间单调不减；
    ///   - 早于本周返回 0，晚于本周返回周目标全额；
    ///   - 已过整天按「每日份额」累加（7 天权重曲线由 seed 确定，权重 1..9）；
    ///   - 今天的份额按小时线性推进：seed 确定的活跃时段
    ///     [startHour ∈ 6..10, endHour ∈ 18..23]，时段前 0%、时段后 100%；
    ///   - 全程整数运算（floor），双端可逐位对齐。
    static func botXpAt(weekKey: String, tier: TierId, salt: String, botIndex: Int, date: Date) -> Int {
        let s = seed(weekKey: weekKey, tier: tier, salt: salt)
        let goal = botWeeklyGoal(weekKey: weekKey, tier: tier, salt: salt, botIndex: botIndex)

        // 7 天权重（周一..周日），每天 1..9
        var weights: [Int] = []
        for d in 0..<7 {
            weights.append(1 + draw(seed: s, offset: UInt64(0x3000 + botIndex * 0x10 + d), count: 9))
        }
        let totalWeight = weights.reduce(0, +)
        // 累计到第 d 天（含）应得的 XP：floor(goal * ΣW / W)，cum(6) == goal
        func cum(_ d: Int) -> Int {
            var w = 0
            for i in 0...d { w += weights[i] }
            return goal * w / totalWeight
        }

        let dayIndex = dayIndexInWeek(weekKey: weekKey, date: date)
        if dayIndex < 0 { return 0 }
        if dayIndex > 6 { return goal }

        let prevCum = dayIndex == 0 ? 0 : cum(dayIndex - 1)
        let todayShare = cum(dayIndex) - prevCum

        // 今日按小时推进：活跃时段 [startHour, endHour] 内线性，两端截断
        let startHour = 6 + draw(seed: s, offset: UInt64(0x4000 + botIndex), count: 5)   // 6..10
        let endHour = 18 + draw(seed: s, offset: UInt64(0x5000 + botIndex), count: 6)    // 18..23
        let hour = Calendar.current.component(.hour, from: date)
        let clamped = min(max(hour - startHour, 0), endHour - startHour)
        let todayPortion = todayShare * clamped / (endHour - startHour)

        return prevCum + todayPortion
    }

    // ============================================================
    // 📊 实时榜单
    // ============================================================

    struct StandingEntry: Hashable {
        /// 是否为用户本人
        let isUser: Bool
        /// bot 下标（0..14）；用户为 nil
        let botIndex: Int?
        let xp: Int
        /// 名次 1..16
        let rank: Int
    }

    /// 把用户实时插入 16 人榜单：XP 降序；同分用户靠前；bot 同分按下标升序。
    static func standings(userXp: Int, botXps: [Int]) -> [StandingEntry] {
        var rows: [(isUser: Bool, botIndex: Int?, xp: Int)] =
            [(isUser: true, botIndex: nil, xp: userXp)]
        for (i, xp) in botXps.enumerated() {
            rows.append((isUser: false, botIndex: i, xp: xp))
        }
        rows.sort { a, b in
            if a.xp != b.xp { return a.xp > b.xp }
            if a.isUser != b.isUser { return a.isUser }
            return (a.botIndex ?? -1) < (b.botIndex ?? -1)
        }
        return rows.enumerated().map { i, r in
            StandingEntry(isUser: r.isUser, botIndex: r.botIndex, xp: r.xp, rank: i + 1)
        }
    }

    /// 用户当前名次（1..16）。
    static func userRank(userXp: Int, botXps: [Int]) -> Int {
        standings(userXp: userXp, botXps: botXps).first { $0.isUser }!.rank
    }

    // ============================================================
    // 🎁 周一结算
    // ============================================================

    /// 前 5 名晋级（钻石封顶）。
    static let promoteZone = 5
    /// 后 5 名降级（青铜保底），即名次 ≥ 12。
    static let demoteZone = 5

    /// 名次宝石奖励表（4-5 名同档 40；6 名及以后 0）。
    static let rankGemRewards: [Int: Int] = [1: 100, 2: 80, 3: 60, 4: 40, 5: 40]

    /// 晋级额外宝石。
    static let promotionBonusGems = 20

    struct SettleResult: Hashable {
        let promoted: Bool
        let demoted: Bool
        /// 名次奖励 +（晋级时）晋级奖励
        let gems: Int
    }

    /// 按上周末终值名次结算：
    ///   - rank ≤ 5 晋级（钻石封顶不晋级，也不发晋级奖励）；
    ///   - rank ≥ 12 降级（青铜保底不降级）；
    ///   - gems = rankGemRewards[rank]（缺省 0）+ 晋级时 promotionBonusGems。
    static func settleRank(_ rank: Int, tierId: TierId? = nil) -> SettleResult {
        let promoted = rank <= promoteZone && tierId != .diamond
        let demoted = rank >= groupSize - demoteZone + 1 && tierId != .bronze
        let gems = (rankGemRewards[rank] ?? 0) + (promoted ? promotionBonusGems : 0)
        return SettleResult(promoted: promoted, demoted: demoted, gems: gems)
    }
}
