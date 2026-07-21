import SwiftUI

/// Floating "+N XP" text that rises and fades out.
/// Triggered on correct answer in lesson runner.
struct XPFloaterView: View {
    let amount: Int
    var onComplete: (() -> Void)? = nil

    @State private var offsetY: CGFloat = 0
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
        .offset(y: offsetY)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeOut(duration: 1.0)) {
                offsetY = -60
                opacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onComplete?()
            }
        }
    }
}
