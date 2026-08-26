import Foundation
import UserNotifications

/// Local streak reminder — the only re-engagement lever an offline app has.
///
/// Design notes:
/// - Opt-in. Nothing is requested or scheduled until the learner says yes to
///   the onboarding primer or turns the toggle on in Settings, so a brand-new
///   user is never system-prompted at launch.
/// - A rolling window of 7 evening reminders, refreshed at every launch and
///   after every study action. A lapsed learner — the whole point of the
///   reminder — keeps hearing from us for a week after their last visit.
/// - If the learner already studied today, today's slot is skipped rather
///   than nagging about a streak that is already safe.
/// - Copy ladder (ios-retention-8): each of the 7 slots speaks differently.
///   Day 1 quotes the live streak, day 2 points at the mistake book, day 3
///   聪聪 misses you, days 4–5 up the ante, day 6 announces the last call,
///   day 7 is a personable goodbye — then we go quiet instead of nagging
///   forever.
/// - Fire time is learner-configurable (ios-retention-9): read from
///   `SettingsStore.reminderHour` / `reminderMinute` (default 20:00).
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    private let reminderDays = 7
    private var identifiers: [String] {
        (0..<reminderDays).map { "cstf.streak.reminder.\($0)" }
    }

    private var center: UNUserNotificationCenter { .current() }

    private init() {}

    // MARK: - Authorization

    /// Ask for permission. Returns whether reminders may be scheduled.
    func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        default: return false
        }
    }

    // MARK: - Copy ladder (ios-retention-8)

    /// Everything the ladder copy may quote, captured at scheduling time.
    struct ReminderContext {
        var streak: Int
        /// Mistake-book entries due for review when the window was scheduled.
        var dueMistakes: Int
    }

    /// One (title, body) pair per slot. Slot 0 fires on the first missed
    /// evening; slot 6 is the farewell. 文案池数组化 — adding a day is adding
    /// an entry.
    static let reminderLadder: [(ReminderContext) -> (title: String, body: String)] = [
        { ctx in
            ctx.streak > 0
                ? ("别让连胜断掉", "你已经连续学习 \(ctx.streak) 天了，今天再学一节就能保住 🔥")
                : ("今天学一点吧", "几分钟就能完成一节小课，聪聪在等你 📚")
        },
        { ctx in
            ctx.dueMistakes > 0
                ? ("错题本在等你", "错题本有 \(ctx.dueMistakes) 题等你，回来把它们消灭掉吧 ✏️")
                : ("温故而知新", "回来复习一节小课，学过的知识才记得牢 ✏️")
        },
        { _ in
            ("聪聪想你了", "两天没见啦，回来学一节课陪陪聪聪吧 🐼")
        },
        { _ in
            ("宝石在等你", "完成每日任务就能赢宝石，今天的任务还空着呢 💎")
        },
        { _ in
            ("小步也是前进", "哪怕只学 5 分钟也很棒，来做一节小课吧 ⭐")
        },
        { _ in
            ("明天是最后一条提醒", "聪聪不想变成唠叨鬼，今天回来学一节，我们就继续每天见 📚")
        },
        { _ in
            ("聪聪先不打扰啦", "提醒好像帮不上忙，聪聪先不打扰啦，想我了随时回来 🐼")
        },
    ]

    // MARK: - Scheduling

    /// Cancel and re-create the pending reminder window.
    /// - Parameters:
    ///   - streak: current streak, quoted in the day-1 copy.
    ///   - studiedToday: when true the window starts tomorrow evening.
    func rescheduleStreakReminder(streak: Int, studiedToday: Bool, now: Date = Date()) {
        guard SettingsStore.shared.streakReminderEnabled else {
            cancel()
            return
        }
        // Snapshot ladder inputs on the main actor before suspending.
        let context = ReminderContext(
            streak: streak,
            dueMistakes: ProgressStore.shared.dueMistakes.count
        )
        Task {
            guard await isAuthorized() else { return }
            // Re-check after the await: the learner may have flipped the
            // toggle off while authorization status was being fetched.
            guard SettingsStore.shared.streakReminderEnabled else { return }
            schedule(context: context, studiedToday: studiedToday, now: now)
        }
    }

    func cancel() {
        // "cstf.streak.reminder" is the pre-window single-shot identifier;
        // clear it too so an update never leaves a stale pending reminder.
        center.removePendingNotificationRequests(withIdentifiers: identifiers + ["cstf.streak.reminder"])
    }

    private func schedule(context: ReminderContext, studiedToday: Bool, now: Date) {
        cancel()

        for (i, fireDate) in fireDates(studiedToday: studiedToday, now: now).enumerated() {
            let copy = Self.reminderLadder[min(i, Self.reminderLadder.count - 1)](context)
            let content = UNMutableNotificationContent()
            content.title = copy.title
            content.body = copy.body
            content.sound = .default

            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: identifiers[i], content: content, trigger: trigger))
        }
    }

    /// The next `reminderDays` slots at the learner's chosen time. Skips today
    /// when the learner has already studied, or when the slot has (nearly)
    /// passed.
    private func fireDates(studiedToday: Bool, now: Date) -> [Date] {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = SettingsStore.shared.reminderHour
        comps.minute = SettingsStore.shared.reminderMinute
        guard let todaySlot = cal.date(from: comps) else { return [] }

        let firstOffset = (!studiedToday && todaySlot > now.addingTimeInterval(60)) ? 0 : 1
        return (0..<reminderDays).compactMap {
            cal.date(byAdding: .day, value: firstOffset + $0, to: todaySlot)
        }
    }
}
