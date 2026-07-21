import SwiftUI

/// Chest open animation modal — shows pulsing glow, tap to open,
/// gem particle burst. Ported from `ChestModal.tsx`.
struct ChestModalView: View {
    let onClaim: (Int) -> Void  // Called with gem amount
    var onDismiss: () -> Void

    @State private var opened = false
    @State private var gemAmount = 0
    @State private var showResult = false
    @State private var breatheY: CGFloat = 0
    @State private var glowScale: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.opacity(0.4)
                .ignoresSafeArea()
                .onTapGesture { if showResult { onDismiss() } }

            VStack(spacing: 20) {
                if !opened {
                    // Pulsing chest
                    ZStack {
                        Circle()
                            .fill(DuoColors.bee.opacity(0.25))
                            .frame(width: 120, height: 120)
                            .scaleEffect(glowScale)

                        Image(systemName: "shippingbox.fill")
                            .font(.system(size: 64))
                            .foregroundStyle(DuoColors.bee)
                            .offset(y: breatheY)
                    }
                    .onAppear {
                        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                            breatheY = -4
                            glowScale = 1.25
                        }
                    }

                    Text("点击打开宝箱！")
                        .font(.headline.weight(.heavy))
                        .foregroundStyle(DuoColors.ink)

                    Button("打开") {
                        openChest()
                    }
                    .buttonStyle(ChunkyButtonStyle(.primary))
                    .padding(.horizontal, 40)

                } else if showResult {
                    // Result: gem count
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(DuoColors.beetle)
                        .scaleEffect(showResult ? 1 : 0)

                    Text("+\(gemAmount) 宝石")
                        .font(.title.weight(.heavy))
                        .foregroundStyle(DuoColors.beetle)

                    Button("收下") {
                        onDismiss()
                    }
                    .buttonStyle(ChunkyButtonStyle(.primary))
                    .padding(.horizontal, 40)
                }
            }
            .padding(32)
            .background(.ultraThinMaterial, in: .rect(cornerRadius: 24))
            .padding(.horizontal, 40)
        }
    }

    private func openChest() {
        let reward = Chest.rollReward()
        gemAmount = reward.gems

        SFXEngine.shared.play(.unlock)
        HapticEngine.shared.success()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            opened = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onClaim(gemAmount)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                showResult = true
            }
        }
    }
}
