import SwiftUI

/// Three stars appearing one by one with 380ms intervals and flip animation.
/// Ported from the star reveal sequence in LessonRunner CompletionScreen.
///
/// Wave F (ios-lesson-18)：
/// - 没拿到的星（earned == false）不再翻转弹出 —— 小尺寸半透明静静待着，
///   「三颗全亮」才配得上完整演出
/// - 序列整体延后 ~0.5s 起跑，先让结算页站稳再开演
/// - Reduce Motion：不翻转，只做淡入
struct StarRevealView: View {
    let earnedStars: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed: [Bool] = [false, false, false]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { i in
                let earned = i < earnedStars
                Image(systemName: earned ? "star.fill" : "star")
                    .font(.system(size: earned ? 52 : 40))
                    .foregroundStyle(earned ? DuoColors.bee : DuoColors.bgSofter)
                    .opacity(starOpacity(index: i, earned: earned))
                    .scaleEffect(starScale(index: i, earned: earned))
                    .rotationEffect(.degrees(starRotation(index: i, earned: earned)))
            }
        }
        .onAppear { runSequence() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("获得 \(earnedStars) 颗星")
    }

    // MARK: - Per-star presentation

    private func starOpacity(index: Int, earned: Bool) -> Double {
        guard revealed[index] else { return 0 }
        return earned ? 1 : 0.45
    }

    private func starScale(index: Int, earned: Bool) -> CGFloat {
        guard revealed[index] else { return earned && !reduceMotion ? 0 : 0.9 }
        return 1
    }

    private func starRotation(index: Int, earned: Bool) -> Double {
        // 只有拿到的星才翻转登场；Reduce Motion 下一律不转。
        guard earned, !reduceMotion else { return 0 }
        return revealed[index] ? 0 : -180
    }

    // MARK: - Sequence

    private func runSequence() {
        let baseDelay = 0.5
        for i in 0..<3 {
            let earned = i < earnedStars
            if earned {
                let delay = baseDelay + Double(i) * 0.38
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    SFXEngine.shared.play(.star)
                    if reduceMotion {
                        withAnimation(.easeOut(duration: 0.25)) { revealed[i] = true }
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                            revealed[i] = true
                        }
                    }
                }
            } else {
                // 未获得的槽：随第一拍轻轻淡入，不做弹出。
                DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay) {
                    withAnimation(.easeOut(duration: 0.3)) { revealed[i] = true }
                }
            }
        }
    }
}
