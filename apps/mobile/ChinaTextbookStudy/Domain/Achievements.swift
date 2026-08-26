import Foundation

/// Achievement catalog + unlock evaluation — port of packages/core/src/achievements.ts.
/// Pure data + functions; no Store dependency.

enum AchievementCategory: String, Codable, Hashable {
    case milestone, streak, perfection, shop, review
}

enum AchievementIconKey: String, Codable, Hashable {
    case lightning, flame, star, crown, gem, bookmark, trophy, rocket, medal, sparkle

    /// Map to an SF Symbol name — useful for the iOS UI layer.
    var symbolName: String {
        switch self {
        case .lightning: return "bolt.fill"
        case .flame:     return "flame.fill"
        case .star:      return "star.fill"
        case .crown:     return "crown.fill"
        case .gem:       return "diamond.fill"
        case .bookmark:  return "bookmark.fill"
        case .trophy:    return "trophy.fill"
        case .rocket:    return "paperplane.fill"
        case .medal:     return "medal.fill"
        case .sparkle:   return "sparkles"
        }
    }
}

/// Snapshot of progress state — only the fields ALL_ACHIEVEMENTS read.
struct AchievementProgressSnapshot: Hashable {
    var xp: Int
    var streak: Int
    var lifetimeGems: Int
    var completedLessonCount: Int
    var perfectedLessonCount: Int
    var ownedCosmeticCount: Int
    var reviewedMistakeCount: Int  // entries with correctCount > 0
}

struct Achievement: Identifiable, Hashable {
    let id: String
    let category: AchievementCategory
    let name: String
    let description: String
    let iconKey: AchievementIconKey
    let colorHex: UInt32
    let goal: Int
    /// 解锁奖励宝石（20/50/100，与 core achievements.ts 逐枚一致；只发一次，
    /// 解锁写入永久 unlockedAchievements 账本）。
    let reward: Int
    let progress: (AchievementProgressSnapshot) -> Int

    static func == (lhs: Achievement, rhs: Achievement) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

enum Achievements {
    static let all: [Achievement] = [
        // ===== Milestone =====
        Achievement(id: "first-lesson",  category: .milestone, name: "出师告捷", description: "完成你的第一节课",
                    iconKey: .rocket, colorHex: 0x1CB0F6, goal: 1, reward: 20,
                    progress: { $0.completedLessonCount }),
        Achievement(id: "ten-lessons",   category: .milestone, name: "学海十里", description: "累计完成 10 节课",
                    iconKey: .bookmark, colorHex: 0x1CB0F6, goal: 10, reward: 50,
                    progress: { $0.completedLessonCount }),
        Achievement(id: "fifty-lessons", category: .milestone, name: "百炼成钢", description: "累计完成 50 节课",
                    iconKey: .trophy, colorHex: 0xA855F7, goal: 50, reward: 100,
                    progress: { $0.completedLessonCount }),
        // ===== XP =====
        Achievement(id: "xp-100",  category: .milestone, name: "初露锋芒", description: "累计 100 经验",
                    iconKey: .lightning, colorHex: 0x1CB0F6, goal: 100, reward: 20,
                    progress: { $0.xp }),
        Achievement(id: "xp-1000", category: .milestone, name: "经验丰富", description: "累计 1000 经验",
                    iconKey: .lightning, colorHex: 0xA855F7, goal: 1000, reward: 50,
                    progress: { $0.xp }),
        Achievement(id: "xp-5000", category: .milestone, name: "学霸认证", description: "累计 5000 经验",
                    iconKey: .lightning, colorHex: 0xFFC800, goal: 5000, reward: 100,
                    progress: { $0.xp }),
        // ===== Streak =====
        Achievement(id: "streak-3",   category: .streak, name: "三日不辍",  description: "连续学习 3 天",
                    iconKey: .flame, colorHex: 0xFF9600, goal: 3, reward: 20,
                    progress: { $0.streak }),
        Achievement(id: "streak-7",   category: .streak, name: "一周如一日", description: "连续学习 7 天",
                    iconKey: .flame, colorHex: 0xFF9600, goal: 7, reward: 50,
                    progress: { $0.streak }),
        Achievement(id: "streak-30",  category: .streak, name: "月度坚持",  description: "连续学习 30 天",
                    iconKey: .flame, colorHex: 0xFF4B4B, goal: 30, reward: 100,
                    progress: { $0.streak }),
        Achievement(id: "streak-100", category: .streak, name: "百日行者",  description: "连续学习 100 天",
                    iconKey: .flame, colorHex: 0xFFC800, goal: 100, reward: 100,
                    progress: { $0.streak }),
        // ===== Perfection =====
        Achievement(id: "perfect-1",  category: .perfection, name: "完美初体验", description: "首次三星通关一节课",
                    iconKey: .star, colorHex: 0xFFC800, goal: 1, reward: 20,
                    progress: { $0.perfectedLessonCount }),
        Achievement(id: "perfect-10", category: .perfection, name: "完美十连",   description: "三星通关 10 节课",
                    iconKey: .star, colorHex: 0xFFC800, goal: 10, reward: 50,
                    progress: { $0.perfectedLessonCount }),
        Achievement(id: "perfect-50", category: .perfection, name: "无暇修行",   description: "三星通关 50 节课",
                    iconKey: .crown, colorHex: 0xA855F7, goal: 50, reward: 100,
                    progress: { $0.perfectedLessonCount }),
        // ===== Shop =====
        Achievement(id: "first-cosmetic", category: .shop, name: "时尚启航",   description: "解锁第一件美妆道具",
                    iconKey: .sparkle, colorHex: 0xA855F7, goal: 1, reward: 20,
                    progress: { max(0, $0.ownedCosmeticCount - 3) }),
        Achievement(id: "gem-collector",  category: .shop, name: "宝石收藏家", description: "累计获得 500 颗宝石",
                    iconKey: .gem, colorHex: 0xA855F7, goal: 500, reward: 50,
                    progress: { $0.lifetimeGems }),
        // ===== Review =====
        Achievement(id: "first-review", category: .review, name: "知错就改", description: "在错题本中复习一道题",
                    iconKey: .medal, colorHex: 0x58CC02, goal: 1, reward: 20,
                    progress: { $0.reviewedMistakeCount }),
    ]

    static func unlockedIds(for snapshot: AchievementProgressSnapshot) -> [String] {
        all.filter { $0.progress(snapshot) >= $0.goal }.map(\.id)
    }

    /// Look up an achievement (= a tier) by its legacy id.
    static func byId(_ id: String) -> Achievement? {
        all.first { $0.id == id }
    }

    /// Achievements that became unlocked between two snapshots.
    static func newlyUnlocked(
        before: AchievementProgressSnapshot,
        after: AchievementProgressSnapshot
    ) -> [Achievement] {
        let beforeSet = Set(unlockedIds(for: before))
        return all.filter { $0.progress(after) >= $0.goal && !beforeSet.contains($0.id) }
    }

    // MARK: - Tiered families (Wave D, ios-retention-10)

    /// 同族成就折叠成的「家族」：同一个计数指标下的递进档位（tiers 按 goal
    /// 升序）。tiers 里的每个 `Achievement` 保留 Wave B 的旧 id / 奖励，
    /// 因此已解锁账本 `unlockedAchievements` 与领取账本 `claimedAchievements`
    /// 无需任何迁移。单档成就（如 first-review）就是只有一档的家族。
    struct Family: Identifiable, Hashable {
        let id: String
        /// 家族名（UI 分组标题用；档位各自保留自己的 name/description）。
        let name: String
        let category: AchievementCategory
        let iconKey: AchievementIconKey
        /// goal 升序的档位列表。
        let tiers: [Achievement]

        static func == (lhs: Family, rhs: Family) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }

        /// 已解锁的最高档（nil = 一档都没解锁）。
        func highestUnlocked(unlockedIds: Set<String>) -> Achievement? {
            tiers.last { unlockedIds.contains($0.id) }
        }

        /// 下一个待解锁档（nil = 全部解锁）。
        func nextTier(unlockedIds: Set<String>) -> Achievement? {
            tiers.first { !unlockedIds.contains($0.id) }
        }

        /// 已解锁档数。
        func unlockedTierCount(unlockedIds: Set<String>) -> Int {
            tiers.filter { unlockedIds.contains($0.id) }.count
        }
    }

    /// 家族分组定义。成员 id 必须存在于 `all` 且按 goal 升序排列。
    private static let familySpec: [(id: String, name: String, memberIds: [String])] = [
        ("lessons", "学习里程", ["first-lesson", "ten-lessons", "fifty-lessons"]),
        ("xp",      "经验积累", ["xp-100", "xp-1000", "xp-5000"]),
        ("streak",  "连胜火焰", ["streak-3", "streak-7", "streak-30", "streak-100"]),
        ("perfect", "完美通关", ["perfect-1", "perfect-10", "perfect-50"]),
        ("cosmetic", "时尚启航", ["first-cosmetic"]),
        ("gems",    "宝石收藏", ["gem-collector"]),
        ("review",  "知错就改", ["first-review"]),
    ]

    /// 全部家族（覆盖 `all` 的每一枚成就，各恰好一次）。
    static let families: [Family] = familySpec.map { spec in
        let tiers = spec.memberIds.compactMap { id in all.first { $0.id == id } }
        precondition(tiers.count == spec.memberIds.count, "family \(spec.id) references unknown achievement id")
        return Family(
            id: spec.id,
            name: spec.name,
            category: tiers[0].category,
            iconKey: tiers[0].iconKey,
            tiers: tiers
        )
    }

    /// 某枚成就（旧 id）所属的家族。
    static func family(containing achievementId: String) -> Family? {
        families.first { family in family.tiers.contains { $0.id == achievementId } }
    }

    /// 永久解锁账本合并（只进不出）—— core `latchUnlocked` 的镜像：把「当前按
    /// 进度算出来的解锁集合」并进已持久化的账本。连胜回落等导致进度倒退时，
    /// 已解锁的成就不会被「回锁」，奖励也因此只会发一次。
    /// 返回保持 prevLedger 原有顺序，新解锁的按 currentUnlockedIds 顺序追加；去重。
    static func latchUnlocked(
        prevLedger: [String],
        currentUnlockedIds: [String]
    ) -> [String] {
        var seen = Set(prevLedger)
        var merged = prevLedger
        for id in currentUnlockedIds where !seen.contains(id) {
            seen.insert(id)
            merged.append(id)
        }
        return merged
    }
}
