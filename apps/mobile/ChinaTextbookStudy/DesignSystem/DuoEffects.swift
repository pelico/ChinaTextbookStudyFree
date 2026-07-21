import SwiftUI

/// A horizontal "shake" — the classic error nudge. Drive it by bumping an
/// integer trigger inside `withAnimation`; the effect interpolates the shake.
///
/// ```swift
/// @State private var shakes = 0
/// someCard.modifier(ShakeEffect(animatableData: CGFloat(shakes)))
/// // on wrong: withAnimation(.linear(duration: 0.4)) { shakes += 1 }
/// ```
struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 8
    var shakesPerUnit: CGFloat = 3
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        let dx = amount * sin(animatableData * .pi * shakesPerUnit * 2)
        return ProjectionTransform(CGAffineTransform(translationX: dx, y: 0))
    }
}

extension View {
    /// Apply a shake keyed to a monotonically increasing trigger.
    /// The caller bumps `trigger` inside `withAnimation(.linear(duration: ~0.4))`.
    func duoShake(_ trigger: Int) -> some View {
        modifier(ShakeEffect(animatableData: CGFloat(trigger)))
    }
}

/// A brief, gentle full-screen color wash — used for the wrong-answer flash.
/// Kept soft (low opacity, short) so it reads as feedback, not punishment.
struct FullScreenFlash: View {
    let color: Color
    var trigger: Int

    @State private var opacity: Double = 0

    var body: some View {
        color
            .opacity(opacity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .onChange(of: trigger) { _, _ in
                opacity = 0.18
                withAnimation(.easeOut(duration: 0.45)) { opacity = 0 }
            }
    }
}
