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
        // Pre-warm generators for lower latency. heavy 也要预热 ——
        // 掉红心的重触感被延迟 0.4s 与心数 bounce 对齐(ios-lesson-15),
        // 预热保证它真正同帧落地而不是再晚半拍。
        lightImpact.prepare()
        mediumImpact.prepare()
        heavyImpact.prepare()
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
