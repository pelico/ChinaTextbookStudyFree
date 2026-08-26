import SwiftUI
import Combine

/// User-facing appearance preference. `.system` follows the device setting;
/// `.light` / `.dark` pin the app to one theme (Duolingo-style opt-in dark).
enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light:  return "浅色"
        case .dark:   return "深色"
        }
    }

    /// Value to hand to `.preferredColorScheme` (nil = follow system).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

/// Persistent user preferences (mute, autoplay TTS, appearance, etc.).
/// State is mirrored to UserDefaults so the values are available
/// synchronously at app launch.
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var isMuted: Bool {
        didSet { defaults.set(isMuted, forKey: Keys.muted) }
    }

    @Published var autoNarrate: Bool {
        didSet { defaults.set(autoNarrate, forKey: Keys.autoNarrate) }
    }

    @Published var hapticEnabled: Bool {
        didSet { defaults.set(hapticEnabled, forKey: Keys.haptic) }
    }

    @Published var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// Opt-in local streak reminder. Off until the learner enables it.
    @Published var streakReminderEnabled: Bool {
        didSet { defaults.set(streakReminderEnabled, forKey: Keys.streakReminder) }
    }

    /// Reminder fire time (ios-retention-9). Default 20:00 — late enough to be
    /// a genuine "don't lose it" nudge; the learner can move it in Settings.
    @Published var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: Keys.reminderHour) }
    }

    @Published var reminderMinute: Int {
        didSet { defaults.set(reminderMinute, forKey: Keys.reminderMinute) }
    }

    static let defaultReminderHour = 20
    static let defaultReminderMinute = 0

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let muted = "cstf.muted"
        static let autoNarrate = "cstf.autoNarrate"
        static let haptic = "cstf.hapticEnabled"
        static let appearance = "cstf.appearance"
        static let streakReminder = "cstf.streakReminder"
        static let reminderHour = "cstf.reminderHour"
        static let reminderMinute = "cstf.reminderMinute"
    }

    init() {
        self.isMuted = defaults.bool(forKey: Keys.muted)
        // Default ON — auto-narration is the whole point of the audio bundle.
        self.autoNarrate = defaults.object(forKey: Keys.autoNarrate) as? Bool ?? true
        self.hapticEnabled = defaults.object(forKey: Keys.haptic) as? Bool ?? true
        // Default: light-first (Duolingo's identity), with opt-in dark.
        let raw = defaults.string(forKey: Keys.appearance) ?? AppAppearance.light.rawValue
        self.appearance = AppAppearance(rawValue: raw) ?? .light
        self.streakReminderEnabled = defaults.bool(forKey: Keys.streakReminder)
        let hour = defaults.object(forKey: Keys.reminderHour) as? Int ?? Self.defaultReminderHour
        self.reminderHour = (0...23).contains(hour) ? hour : Self.defaultReminderHour
        let minute = defaults.object(forKey: Keys.reminderMinute) as? Int ?? Self.defaultReminderMinute
        self.reminderMinute = (0...59).contains(minute) ? minute : Self.defaultReminderMinute
    }

    /// "20:00"-style label for the hint line under the reminder toggle.
    var reminderTimeLabel: String {
        String(format: "%02d:%02d", reminderHour, reminderMinute)
    }

    func toggleMute() {
        isMuted.toggle()
    }
}
