import SwiftUI

/// Duolingo-style progress bar with animated green fill and rounded caps.
/// Replaces the stock `ProgressView` in the lesson runner.
///
/// Wave F (ios-lesson-10):
/// - `sweepTrigger` 每 +1 触发一次白色高光从左向右扫过（答对时调用方递增）
/// - `comboLevel >= 3` 时整条金色 glow，且扫光时伴随 scaleY 脉冲，
///   幅度对齐 web 公式 `min(1.6 + combo * 0.05, 2.1)`
/// - VoiceOver 读出百分比进度
/// - Reduce Motion 下扫光与脉冲全部关闭
struct StyledProgressBar: View {
    /// 0.0 ... 1.0
    let progress: Double
    var height: CGFloat = 16
    var fillColor: Color = DuoColors.primary
    var trackColor: Color = DuoColors.bgSofter
    /// 答对时调用方 +1；0 → 不扫光（向后兼容）。
    var sweepTrigger: Int = 0
    /// 当前连击数；>= 3 时金色 glow + 脉冲幅度随连击增大。
    var comboLevel: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 高光带的水平位置，相对填充宽度：-0.6（左外）→ 1.2（右外）。
    @State private var sweepPhase: CGFloat = -0.6
    @State private var pulseScaleY: CGFloat = 1

    private var comboGlow: Bool { comboLevel >= 3 }

    var body: some View {
        GeometryReader { geo in
            let clamped = CGFloat(min(1, max(0, progress)))
            let fillWidth = max(height, geo.size.width * clamped)

            ZStack(alignment: .leading) {
                // Track
                Capsule()
                    .fill(trackColor)
                    .frame(height: height)

                // Fill
                Capsule()
                    .fill(fillColor)
                    .frame(width: fillWidth, height: height)
                    // Inner highlight for 3D effect
                    .overlay(alignment: .top) {
                        Capsule()
                            .fill(.white.opacity(0.30))
                            .frame(height: height * 0.4)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }
                    // 连击 3+：金色描边微光，进度条也跟着「燃」起来。
                    .overlay {
                        if comboGlow {
                            Capsule()
                                .strokeBorder(DuoColors.bee.opacity(0.85), lineWidth: 2)
                        }
                    }
                    // 答对扫光：白色高光带从左滑到右，只在填充范围内可见。
                    .overlay {
                        if !reduceMotion, sweepTrigger > 0 {
                            LinearGradient(
                                colors: [.white.opacity(0), .white.opacity(0.75), .white.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: max(24, fillWidth * 0.45), height: height)
                            .offset(x: sweepPhase * fillWidth)
                            .allowsHitTesting(false)
                        }
                    }
                    .clipShape(Capsule())
                    .shadow(
                        color: comboGlow ? DuoColors.bee.opacity(0.55) : .clear,
                        radius: comboGlow ? 6 : 0
                    )
            }
            .scaleEffect(x: 1, y: pulseScaleY, anchor: .center)
        }
        .frame(height: height)
        .animation(.spring(response: 0.4, dampingFraction: 0.6), value: progress)
        .onChange(of: sweepTrigger) { _, _ in
            runSweep()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("课程进度")
        .accessibilityValue("\(Int((min(1, max(0, progress)) * 100).rounded()))%")
    }

    /// 白色高光扫过 + （连击时）scaleY 脉冲。Reduce Motion 下不做。
    private func runSweep() {
        guard !reduceMotion else { return }

        // Sweep: reset instantly off-screen left, then glide right.
        var resetTx = Transaction()
        resetTx.disablesAnimations = true
        withTransaction(resetTx) { sweepPhase = -0.6 }
        withAnimation(.easeInOut(duration: 0.5)) { sweepPhase = 1.2 }

        // Pulse: combo 越高幅度越大（对齐 web 公式，封顶 2.1）。
        if comboGlow {
            let amp = min(1.6 + Double(comboLevel) * 0.05, 2.1)
            withAnimation(.easeOut(duration: 0.18)) { pulseScaleY = amp }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                withAnimation(.easeIn(duration: 0.17)) { pulseScaleY = 1 }
            }
        }
    }
}
