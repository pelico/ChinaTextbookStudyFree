import SwiftUI

/// Last-7-days XP bar chart with a week-over-week delta — the offline stand-in
/// for a leaderboard: you compete with your own previous week.
struct WeeklyReportCard: View {
    @ObservedObject var progressStore: ProgressStore

    private var days: [(date: String, xp: Int)] { progressStore.recentXP(days: 7) }
    private var thisWeek: Int { progressStore.weeklyTotal() }
    private var lastWeek: Int { progressStore.weeklyTotal(endingDaysAgo: 7) }
    private var delta: Int { thisWeek - lastWeek }
    private var peak: Int { max(days.map(\.xp).max() ?? 0, 1) }

    /// "2026-07-20" → 周一…周日
    private func weekdayLabel(_ iso: String) -> String {
        let parts = iso.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return "" }
        var c = DateComponents(); c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
        guard let d = Calendar.current.date(from: c) else { return "" }
        let idx = Calendar.current.component(.weekday, from: d)   // 1 = Sunday
        return ["日", "一", "二", "三", "四", "五", "六"][max(0, idx - 1)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill").font(.system(size: 16, weight: .heavy)).foregroundStyle(DuoColors.secondary)
                Text("本周报告").duoFont(.subhead).foregroundStyle(DuoColors.ink)
                Spacer()
                deltaChip
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(DuoColors.surfaceAlt)
                                .frame(height: 68)
                            RoundedRectangle(cornerRadius: 4)
                                .fill(i == days.count - 1 ? DuoColors.primary : DuoColors.secondary)
                                .frame(height: max(day.xp > 0 ? 6 : 0, 68 * CGFloat(day.xp) / CGFloat(peak)))
                        }
                        .frame(maxWidth: .infinity)
                        Text(weekdayLabel(day.date))
                            .duoFont(.micro)
                            .foregroundStyle(i == days.count - 1 ? DuoColors.ink : DuoColors.inkMuted)
                    }
                }
            }

            HStack(spacing: 18) {
                stat("本周", "\(thisWeek) XP", DuoColors.ink)
                stat("上周", "\(lastWeek) XP", DuoColors.inkMuted)
                stat("最佳", "\(days.map(\.xp).max() ?? 0) XP", DuoColors.inkMuted)
                Spacer()
            }
        }
        .padding(16)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
    }

    @ViewBuilder
    private var deltaChip: some View {
        if lastWeek == 0 && thisWeek == 0 {
            Text("本周还没开始").duoFont(.micro).foregroundStyle(DuoColors.inkSofter)
        } else {
            let up = delta >= 0
            HStack(spacing: 3) {
                Image(systemName: up ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 10, weight: .heavy))
                Text("\(abs(delta)) XP").duoNumeral(.micro)
            }
            .foregroundStyle(up ? DuoColors.primary : DuoColors.fox)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background((up ? DuoColors.primary : DuoColors.fox).opacity(0.14), in: .capsule)
        }
    }

    private func stat(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).duoNumeral(.caption).foregroundStyle(tint)
            Text(label).duoFont(.micro).foregroundStyle(DuoColors.inkSofter)
        }
    }
}
