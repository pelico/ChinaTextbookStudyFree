import UIKit

/// Centralized haptic feedback — wraps UIFeedbackGenerator for consistent
/// Duolingo-style tactile responses. Ported from `apps/web/src/lib/haptic.ts`.
@MainActor
final class HapticEngine {
    static let shared = HapticEngine()

    private let lightImpact = UIImpactFeedbackGenerator(style: .light)
    private let mediumImpact = UIImpactFeedbackGenerator(style: .medium)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationFeedback = UINotificationFeedbackGenerator()

    private init() {
        // Pre-warm generators for lower latency.
        lightImpact.prepare()
        mediumImpact.prepare()
    }

    /// Light tap — option selection, button press.
    func tap() {
        guard isEnabled else { return }
        lightImpact.impactOccurred()
    }

    /// Success notification — correct answer.
    func correct() {
        guard isEnabled else { return }
        notificationFeedback.notificationOccurred(.success)
    }

    /// Error notification — wrong answer.
    func wrong() {
        guard isEnabled else { return }
        notificationFeedback.notificationOccurred(.error)
    }

    /// Medium double-pulse — lesson complete, achievement unlock.
    func success() {
        guard isEnabled else { return }
        mediumImpact.impactOccurred(intensity: 0.8)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [self] in
            mediumImpact.impactOccurred(intensity: 1.0)
        }
    }

    /// Heavy impact — heart loss.
    func heartLoss() {
        guard isEnabled else { return }
        heavyImpact.impactOccurred()
    }

    private var isEnabled: Bool {
        // Gate on the dedicated haptics toggle — muting *audio* should not
        // silently kill *haptics* (they're independent channels).
        SettingsStore.shared.hapticEnabled
    }
}
