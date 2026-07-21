import Foundation
import UserNotifications

/// Local streak reminder — the only re-engagement lever an offline app has.
///
/// Design notes:
/// - Opt-in. Nothing is requested or scheduled until the learner turns the
///   toggle on in Settings, so a brand-new user is never prompted at launch.
/// - One pending notification at a time, rescheduled after every study action
///   so the copy always quotes the current streak.
/// - If the learner already studied today, the reminder is pushed to tomorrow
///   rather than nagging about a streak that is already safe.
@MainActor
final class NotificationService {
    static let shared = NotificationService()

    /// Fire time — late enough to be a genuine "don't lose it" nudge.
    private let hour = 20
    private let minute = 0
    private let identifier = "cstf.streak.reminder"

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
            schedule(streak: streak, studiedToday: studiedToday, now: now)
        }
    }

    func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private func schedule(streak: Int, studiedToday: Bool, now: Date) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])

        let content = UNMutableNotificationContent()
        content.title = "别让连胜断掉"
        content.body = streak > 0
            ? "你已经连续学习 \(streak) 天了，今天再做一节就能保住 🔥"
            : "今天还没学习，来做一节小课吧 📚"
        content.sound = .default

        guard let fireDate = nextFireDate(studiedToday: studiedToday, now: now) else { return }
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    /// The next evening slot worth firing at. Skips today when the learner has
    /// already studied, or when 20:00 has already passed.
    private func nextFireDate(studiedToday: Bool, now: Date) -> Date? {
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        guard let todaySlot = cal.date(from: comps) else { return nil }

        if !studiedToday && todaySlot > now.addingTimeInterval(60) {
            return todaySlot
        }
        return cal.date(byAdding: .day, value: 1, to: todaySlot)
    }
}
