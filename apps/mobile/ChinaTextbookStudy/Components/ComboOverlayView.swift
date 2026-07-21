import SwiftUI

/// Full-screen overlay badge shown when combo hits milestones (3, 5, 10).
/// Ported from `apps/web/src/components/ComboOverlay.tsx`.
struct ComboOverlayView: View {
    let combo: Int
    @State private var scale: CGFloat = 0.2
    @State private var opacity: Double = 1

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: "flame.fill")
                .font(.system(size: 28))
                .foregroundStyle(.white)
            Text("连击 ×\(combo)")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                colors: [DuoColors.bee, DuoColors.fox, DuoColors.danger],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: .rect(cornerRadius: 20)
        )
        .shadow(color: Color(hex: 0xB45A00).opacity(0.4), radius: 0, x: 0, y: 8)
        .scaleEffect(scale)
        .opacity(opacity)
        .onAppear {
            SFXEngine.shared.play(.combo)
            HapticEngine.shared.success()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                scale = 1.0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                withAnimation(.easeOut(duration: 0.4)) {
                    opacity = 0
                    scale = 0.8
                }
            }
        }
    }
}
