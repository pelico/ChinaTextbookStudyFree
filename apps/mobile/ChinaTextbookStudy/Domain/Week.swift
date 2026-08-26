import Foundation

/// 「一周」与「日期键」的单一事实源 —— packages/core/src/week.ts 的 Swift 镜像。
///
/// 双端凡是涉及「本周」的功能（联赛周榜、周报、连胜日历）都必须用这里的
/// 日历周定义，**不允许**再出现「最近滚动 7 天」之类的第二套窗口。
///
/// 约定：
///   - 日期键统一为本地时区 `YYYY-MM-DD`（与 `SRS.todayString` 同一格式化器）；
///   - 一周从**周一**开始、到**周日**结束（中国校历习惯）；
///   - 周键 = 该周周一的日期键；
///   - 全部按本地日历日计算，跨月 / 跨年 / 夏令时都安全。
enum Week {

    /// 本地时区下把 Date 格式化成 `YYYY-MM-DD`。
    static func dateKey(_ date: Date = Date()) -> String {
        SRS.dateFormatter.string(from: date)
    }

    /// 是否是结构合法且真实存在的日期键（`2026-02-30` 为假）。
    static func isDateKey(_ key: String) -> Bool {
        parseDateKey(key) != nil
    }

    /// 解析日期键为**本地时区当天 00:00**；非法键返回 nil（绝不抛）。
    static func parseDateKey(_ key: String) -> Date? {
        guard key.count == 10, let date = SRS.dateFormatter.date(from: key) else { return nil }
        // DateFormatter 会把 2026-02-30 悄悄滚到 3 月 2 日 —— 回写比对一次，
        // 不存在的日期一律判非法。
        guard SRS.dateFormatter.string(from: date) == key else { return nil }
        return Calendar.current.startOfDay(for: date)
    }

    /// date 所在**日历周**周一的日期键（周一自身返回当天）。
    static func weekStartKey(_ date: Date = Date()) -> String {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)   // 1=周日..7=周六
        let jsDay = weekday - 1                             // 0=周日..6=周六
        let offset = (jsDay + 6) % 7                        // 距本周周一的天数
        let monday = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: date)) ?? date
        return dateKey(monday)
    }

    /// 一周 7 天的日期键，**周一 → 周日**（下标 0..6 即 `dayIndexInWeek`）。
    ///
    /// 入参既可以是周键，也可以是该周内任意一天 —— 内部一律先归一到周一；
    /// 非法键回退到「今天所在的周」。
    static func weekDateKeys(_ key: String, now: Date = Date()) -> [String] {
        let monday: Date = {
            if let parsed = parseDateKey(key), let m = parseDateKey(weekStartKey(parsed)) { return m }
            return parseDateKey(weekStartKey(now)) ?? Calendar.current.startOfDay(for: now)
        }()
        let cal = Calendar.current
        return (0..<7).map { i in
            dateKey(cal.date(byAdding: .day, value: i, to: monday) ?? monday)
        }
    }

    /// date 相对 weekKey 那一周周一的天序（周一=0 … 周日=6；早于周一为负，
    /// 晚于周日 >6）。非法 weekKey 回退到本周。
    static func dayIndexInWeek(weekKey: String, date: Date, now: Date = Date()) -> Int {
        let monday = parseDateKey(weekKey)
            ?? parseDateKey(weekStartKey(now))
            ?? Calendar.current.startOfDay(for: now)
        let cal = Calendar.current
        let to = cal.startOfDay(for: date)
        return cal.dateComponents([.day], from: monday, to: to).day ?? 0
    }

    /// `weeksAgo` 周前那一周的周键（0 = 本周，1 = 上周……）。
    static func weekStartKey(weeksAgo: Int, now: Date = Date()) -> String {
        let cal = Calendar.current
        let shifted = cal.date(byAdding: .day, value: -7 * max(0, weeksAgo), to: now) ?? now
        return weekStartKey(shifted)
    }
}
