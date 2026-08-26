import SwiftUI

/// 本周 7 格连胜日历（ios-path-8 / ios-retention-4）。
///
/// 通用组件：结算页的全屏连胜幕和首页的连胜详情弹层共用，数据来自
/// `ProgressStore.recentXP(days: 7)`（最后一项 = 今天）。设计基于深色底
/// （darkBg / 全屏遮罩）——两处调用场景都是深色环境。
///
/// - `entries`: 7 天（旧 → 新），`studied` = 当天有任意学习活动（XP > 0）。
/// - `todayStudied`: 今天是否已打卡；驱动最后一格的强调态。
struct StreakCalendarView: View {
    let entries: [(dateKey: String, studied: Bool)]
    let todayStudied: Bool

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    private func weekdayLabel(for dateKey: String) -> String {
        guard let date = Self.dayFormatter.date(from: dateKey) else { return "·" }
        let weekday = Calendar.current.component(.weekday, from: date)   // 1 = Sunday
        return Self.weekdaySymbols[(weekday - 1) % 7]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(entries.indices, id: \.self) { i in
                dayCell(at: i)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("本周学习日历")
    }

    @ViewBuilder
    private func dayCell(at index: Int) -> some View {
        let entry = entries[index]
        let isToday = index == entries.count - 1
        let lit = isToday ? todayStudied : entry.studied

        VStack(spacing: 6) {
            Text(isToday ? "今" : weekdayLabel(for: entry.dateKey))
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(isToday ? DuoColors.fox : DuoColors.darkInkMuted)

            ZStack {
                Circle()
                    .fill(lit ? DuoColors.fox : DuoColors.darkSurfaceAlt)
                    .frame(width: 34, height: 34)
                if lit {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.white)
                } else {
                    Circle()
                        .fill(DuoColors.darkInkSofter.opacity(0.35))
                        .frame(width: 6, height: 6)
                }
            }
            .overlay {
                if isToday {
                    Circle()
                        .strokeBorder(DuoColors.fox, lineWidth: 2)
                        .frame(width: 42, height: 42)
                }
            }
            .frame(width: 42, height: 42)
        }
        .frame(maxWidth: .infinity)
    }
}
