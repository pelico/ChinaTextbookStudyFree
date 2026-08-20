import Foundation
import UserNotifications

/// Local streak reminder — the only re-engagement lever an offline app has.
///
/// Design notes:
/// - Opt-in. Nothing is requested or scheduled until the learner turns the
///   toggle on in Settings, so a brand-new user is never prompted at launch.
/// - A rolling window of 7 evening reminders, refreshed at every launch and
///   after every study action. A lapsed learner — the whole point of the
///   reminder — keeps hearing from us for a week after their last visit.
/// - If the learner already studied today, today's slot is skipped rather
///   than nagging about a streak that is already safe.
/// - Only the first evening can truthfully quote the current streak; the
///   later slots (learner hasn't come back) use generic copy.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    /// Fire time — late enough to be a genuine "don't lose it" nudge.
    private let hour = 20
    private let minute = 0
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

    // MARK: - Scheduling

    /// Cancel and re-create the pending reminder.
    /// - Parameters:
    ///   - streak: current streak, quoted in the copy.
    ///   - studiedToday: when true the reminder targets tomorrow evening.
    func rescheduleStreakReminder(streak: Int, studiedToday: Bool, now: Date = Date()) {
        guard SettingsStore.shared.streakReminderEnabled else {
            cancel()
            return
        }
        Task {
            guard await isAuthorized() else { return }
            // Re-check after the await: the learner may have flipped the
            // toggle off while authorization status was being fetched.
            guard SettingsStore.shared.streakReminderEnabled else { return }
            schedule(streak: streak, studiedToday: studiedToday, now: now)
        }
    }

    func cancel() {
        // "cstf.streak.reminder" is the pre-window single-shot identifier;
        // clear it too so an update never leaves a stale pending reminder.
        center.removePendingNotificationRequests(withIdentifiers: identifiers + ["cstf.streak.reminder"])
    }

    private func schedule(streak: Int, studiedToday: Bool, now: Date) {
        cancel()

        for (i, fireDate) in fireDates(studiedToday: studiedToday, now: now).enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "别让连胜断掉"
            content.body = (i == 0 && streak > 0)
                ? "你已经连续学习 \(streak) 天了，今天再做一节就能保住 🔥"
                : "今天还没学习，来做一节小课吧 📚"
            content.sound = .default

            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            center.add(UNNotificationRequest(identifier: identifiers[i], content: content, trigger: trigger))
        }
    }

    /// The next `reminderDays` evening slots. Skips today when the learner has
    /// already studied, or when 20:00 has (nearly) passed.
    private func fireDates(studiedToday: Bool, now: Date) -> [Date] {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        guard let todaySlot = cal.date(from: comps) else { return [] }

        let firstOffset = (!studiedToday && todaySlot > now.addingTimeInterval(60)) ? 0 : 1
        return (0..<reminderDays).compactMap {
            cal.date(byAdding: .day, value: firstOffset + $0, to: todaySlot)
        }
    }
}
