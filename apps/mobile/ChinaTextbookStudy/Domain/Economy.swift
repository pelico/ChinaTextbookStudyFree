import Foundation

/// 经济系统单一事实源 —— packages/core/src/economy.ts 的 Swift 镜像。
///
/// 常量名换用 camelCase，但**数值必须与 core 完全一致**；
/// ChinaTextbookStudyTests/GoldenVectorTests.swift 会读取
/// packages/core/spec/golden-vectors.json 逐条断言两端行为等价。
/// 任何数值改动必须双端同步（core + 此文件 + 黄金向量）。
enum Economy {

    // ============================================================
    // ⭐ 星级
    // ============================================================

    /// 三星线：首答正确率 ≥ 0.95
    static let threeStarAccuracy = 0.95
    /// 二星线：首答正确率 ≥ 0.80
    static let twoStarAccuracy = 0.80

    /// 由首答正确率（首答答对数 / 总题数）计算星级：≥0.95→3；≥0.80→2；否则 1。
    static func starsFromAccuracy(_ accuracy: Double) -> Int {
        if accuracy >= threeStarAccuracy { return 3 }
        if accuracy >= twoStarAccuracy { return 2 }
        return 1
    }

    // ============================================================
    // ⚡ 课程 XP
    // ============================================================

    /// 每道首答答对的题 = 10 XP
    static let xpPerCorrect = 10
    /// 零失误（首答全对）额外 +5 XP
    static let perfectXpBonus = 5
    /// 该课历史首次达成三星，额外 +5 XP
    static let firstPerfectXpBonus = 5
    /// 周末（本地时间周六/周日）XP 总额整体 ×2，且必须在 UI 可见
    static let weekendXpMultiplier = 2

    /// 一节课的 XP 总额：base = correctCount×10；perfect +5；firstPerfect +5；周末整体 ×2。
    static func xpForLesson(
        correctCount: Int,
        perfect: Bool,
        firstPerfect: Bool,
        isWeekend: Bool
    ) -> Int {
        var xp = correctCount * xpPerCorrect
        if perfect { xp += perfectXpBonus }
        if firstPerfect { xp += firstPerfectXpBonus }
        if isWeekend { xp *= weekendXpMultiplier }
        return xp
    }

    /// 本地时间是否处于周末双倍 XP（周六/周日）。
    static func isWeekend(_ date: Date = Date()) -> Bool {
        let weekday = Calendar.current.component(.weekday, from: date)
        return weekday == 1 || weekday == 7   // 1 = Sunday, 7 = Saturday
    }

    /// 本地时间是否为周一（护盾补给日）。
    static func isMonday(_ date: Date = Date()) -> Bool {
        Calendar.current.component(.weekday, from: date) == 2
    }

    // ============================================================
    // 💎 每课宝石 drip
    // ============================================================

    /// 每节课基础宝石
    static let lessonGemBase = 3
    /// 2 星宝石加成
    static let lessonGemTwoStarBonus = 5
    /// 3 星宝石加成（替代 2 星加成，不叠加）
    static let lessonGemThreeStarBonus = 10
    /// 该课历史首次三星，额外宝石
    static let firstPerfectGemBonus = 15
    /// 当日首次跨过每日目标的一次性宝石奖励
    static let dailyGoalBonus = 20

    /// 每课宝石 drip：基础 3；2 星 +5；3 星 +10（取档不叠加）；首次三星 +15；当日首次达标 +20。
    static func lessonGemDrip(stars: Int, isFirstPerfect: Bool, crossedDailyGoal: Bool) -> Int {
        var gems = lessonGemBase
        if stars == 3 { gems += lessonGemThreeStarBonus }
        else if stars == 2 { gems += lessonGemTwoStarBonus }
        if isFirstPerfect { gems += firstPerfectGemBonus }
        if crossedDailyGoal { gems += dailyGoalBonus }
        return gems
    }

    // ============================================================
    // ❤️ 红心
    // ============================================================

    /// 红心上限
    static let maxHearts = 5
    /// 每颗红心的回复时长（秒）
    static let heartRegenSeconds = 300
    /// 一次性补满红心的宝石价格
    static let heartRefillCost = 350

    // ============================================================
    // 🛡️ 连胜护盾 & 连胜推进
    // ============================================================

    /// 护盾售价（宝石）
    static let freezeCost = 200
    /// 护盾持有上限（满时购买按钮置灰显示 2/2；老档超过 2 的不没收，只封新购）
    static let maxFreezes = 2
    /// 新档初始护盾数（老档一次性迁移为 max(现值, 2)）
    static let initialFreezes = 2

    /// 连胜补卡价格：仅当今天未学且 gap≥2（护盾不够救）时可用，把 lastActiveDate 拨回昨天
    static let streakMakeupCost = 50

    struct StreakAdvanceResult: Equatable {
        var streak: Int
        var freezes: Int
        /// 本次消耗的护盾数
        var freezesConsumed: Int
    }

    /// 连胜推进（core `advanceStreak` 的纯函数镜像）：
    ///   - gapDays <= 0（同日 / 时钟回拨）：不变，不消耗。
    ///   - gapDays == 1：streak+1；周一且护盾未满时自动补 1（封顶 maxFreezes）。
    ///   - gapDays >= 2：缺勤 missed = gapDays-1；护盾足够则扣 missed 并 streak+1，
    ///     不够则 streak 归 1（护盾保留不消耗）。
    static func advanceStreak(
        streak: Int,
        freezes: Int,
        gapDays: Int,
        isMonday: Bool
    ) -> StreakAdvanceResult {
        if gapDays <= 0 {
            return StreakAdvanceResult(streak: streak, freezes: freezes, freezesConsumed: 0)
        }
        if gapDays == 1 {
            let topped = (isMonday && freezes < maxFreezes) ? freezes + 1 : freezes
            return StreakAdvanceResult(streak: streak + 1, freezes: topped, freezesConsumed: 0)
        }
        let missed = gapDays - 1
        if freezes >= missed {
            return StreakAdvanceResult(streak: streak + 1, freezes: freezes - missed, freezesConsumed: missed)
        }
        return StreakAdvanceResult(streak: 1, freezes: freezes, freezesConsumed: 0)
    }

    // ============================================================
    // 🔥 连胜里程碑 & 每日登录奖励
    // ============================================================

    /// 连胜里程碑宝石（每档一次，记入 claimedStreakRewards 账本）。
    static let streakMilestoneRewards: [Int: Int] = [
        3: 30,
        7: 80,
        14: 150,
        30: 300,
        60: 500,
        100: 800,
    ]

    /// 达到某连胜天数应发的里程碑宝石；非里程碑档返回 0。
    static func streakMilestoneReward(_ streakAfter: Int) -> Int {
        streakMilestoneRewards[streakAfter] ?? 0
    }

    /// 每日登录奖励表：index = min(max(0, 有效连胜), 7)。每日一次，记入 lastDailyRewardDate 账本。
    static let dailyRewardTable = [5, 5, 8, 12, 15, 20, 25, 30]

    /// 按有效连胜取每日登录奖励宝石数。
    static func dailyRewardForStreak(_ streak: Int) -> Int {
        let idx = min(max(0, streak), dailyRewardTable.count - 1)
        return dailyRewardTable[idx]
    }

    // ============================================================
    // 🎯 每日目标
    // ============================================================

    /// 每日目标档位（XP）。老用户已选超出档位的值保留现值，仅选项列表变。
    static let dailyGoalOptions = [20, 50, 100, 200]
    static let defaultDailyGoal = 50

    // ============================================================
    // 📖 阅读 XP（纯 XP，无宝石）
    // ============================================================

    /// 阅读类活动 XP：课文听读 5；跟读 10；故事测验 accuracy ≥ 0.8 → 15，否则 5。
    enum ReadingXP {
        /// 课文听读
        static let listen = 5
        /// 跟读
        static let followup = 10
        /// 故事测验达标（accuracy ≥ goodThreshold）
        static let storyGood = 15
        /// 故事测验未达标
        static let storyBase = 5
        /// 故事测验达标线
        static let goodThreshold = 0.8
    }

    /// 故事测验按正确率取 XP。
    static func storyQuizXp(accuracy: Double) -> Int {
        accuracy >= ReadingXP.goodThreshold ? ReadingXP.storyGood : ReadingXP.storyBase
    }
}
