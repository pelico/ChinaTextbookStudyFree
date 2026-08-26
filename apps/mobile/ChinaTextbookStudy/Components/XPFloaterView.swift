import SwiftUI

/// Floating "+N XP" text — triggered on correct answer in lesson runner.
///
/// Wave F (ios-lesson-11):
/// - 传入 `targetOffset`（目标点相对本视图放置位置的位移，调用方用
///   GeometryReader 计算：顶栏 XP 徽章中心 − 浮字起点中心）时，浮字先小幅
///   弹起，再沿弧线飞向顶栏并缩小淡出 —— 对齐 web 的「+XP 飞徽章」。
/// - 不传 target（nil）时维持原上浮淡出，API 完全向后兼容。
/// - Reduce Motion：原地淡出，不飞行。
struct XPFloaterView: View {
    let amount: Int
    /// 目标点（通常是顶栏 XP 徽章中心）相对浮字放置位置的位移；nil = 原上浮。
    var targetOffset: CGSize? = nil
    var onComplete: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var offsetX: CGFloat = 0
    @State private var offsetY: CGFloat = 0
    @State private var scale: CGFloat = 1
    @State private var opacity: Double = 1

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .bold))
            Text("+\(amount)")
                .font(.system(size: 16, weight: .heavy))
        }
        .foregroundStyle(DuoColors.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DuoColors.secondary.opacity(0.15), in: .capsule)
        .scaleEffect(scale)
        .offset(x: offsetX, y: offsetY)
        .opacity(opacity)
        .allowsHitTesting(false)
        .onAppear { start() }
        .accessibilityLabel("获得 \(amount) 经验")
    }

    private func start() {
        if reduceMotion {
            // 动效减弱：原地停留片刻再淡出。
            withAnimation(.easeOut(duration: 0.35).delay(0.45)) { opacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onComplete?() }
            return
        }

        guard let target = targetOffset else {
            // 兼容路径：原上浮淡出。
            withAnimation(.easeOut(duration: 1.0)) {
                offsetY = -60
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { onComplete?() }
            return
        }

        // 第一拍（0 ~ 0.18s）：小弹起 + 放大，让玩家先看清数字。
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
            offsetY = -22
            scale = 1.15
        }

        // 第二拍（0.18 ~ 0.78s）：飞向顶栏。x 用 easeOut、y 用 easeIn，
        // 两条曲线错开就画出一道弧线；途中缩小，收尾淡出「入账」。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.6)) {
                offsetX = target.width
            }
            withAnimation(.easeIn(duration: 0.6)) {
                offsetY = target.height
                scale = 0.55
            }
            withAnimation(.easeIn(duration: 0.25).delay(0.4)) {
                opacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) { onComplete?() }
    }
}
