import SwiftUI

/// Achievement wall — badges grouped by category with tiered progress bars.
struct AchievementsView: View {
    @ObservedObject var progressStore: ProgressStore

    private var snapshot: AchievementProgressSnapshot { progressStore.achievementSnapshot }
    private var unlockedIds: Set<String> { Set(Achievements.unlockedIds(for: snapshot)) }

    private static let categoryOrder: [AchievementCategory] = [.milestone, .streak, .perfection, .review, .shop]
    private static let categoryLabels: [AchievementCategory: String] = [
        .milestone: "里程碑", .streak: "连续学习", .perfection: "完美", .review: "复习", .shop: "商店",
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                summary
                ForEach(Self.categoryOrder, id: \.self) { cat in
                    let items = Achievements.all.filter { $0.category == cat }
                    if !items.isEmpty {
                        section(title: Self.categoryLabels[cat] ?? cat.rawValue, items: items)
                    }
                }
            }
            .padding(20)
        }
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationTitle("成就墙")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var summary: some View {
        let unlocked = unlockedIds.count
        let total = Achievements.all.count
        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(DuoColors.bee.opacity(0.16)).frame(width: 56, height: 56)
                Image(systemName: "rosette").font(.system(size: 28, weight: .heavy)).foregroundStyle(DuoColors.bee)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("已解锁 \(unlocked) / \(total)").duoFont(.heading).foregroundStyle(DuoColors.ink)
                StyledProgressBar(progress: Double(unlocked) / Double(max(total, 1)), height: 10, trackColor: DuoColors.surfaceAlt)
            }
            Spacer()
        }
        .padding(16)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
    }

    private func section(title: String, items: [Achievement]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).duoFont(.caption).tracking(1).foregroundStyle(DuoColors.inkMuted)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                ForEach(items, id: \.id) { ach in badge(ach) }
            }
        }
    }

    private func badge(_ ach: Achievement) -> some View {
        let isUnlocked = unlockedIds.contains(ach.id)
        let progress = ach.progress(snapshot)
        let frac = min(1.0, Double(progress) / Double(max(ach.goal, 1)))
        let tint = Color(hex: UInt32(ach.colorHex))
        return VStack(spacing: 8) {
            Image(systemName: ach.iconKey.symbolName)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(isUnlocked ? .white : tint.opacity(0.5))
                .frame(width: 64, height: 64)
                .background(isUnlocked ? tint : DuoColors.surfaceAlt, in: .circle)
            Text(ach.name).duoFont(.caption).foregroundStyle(DuoColors.ink)
            Text(ach.description)
                .duoFont(.micro)
                .foregroundStyle(DuoColors.inkMuted)
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            if isUnlocked {
                Text("已解锁").duoFont(.micro).foregroundStyle(DuoColors.primary)
            } else {
                StyledProgressBar(progress: frac, height: 6, fillColor: tint, trackColor: DuoColors.surfaceAlt)
                Text("\(progress) / \(ach.goal)").duoFont(.micro).foregroundStyle(DuoColors.inkMuted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
        .accessibilityIdentifier("ach-\(ach.id)")
    }
}
