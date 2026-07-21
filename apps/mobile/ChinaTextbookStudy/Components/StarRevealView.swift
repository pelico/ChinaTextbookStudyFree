import SwiftUI

/// Three stars appearing one by one with 380ms intervals and flip animation.
/// Ported from the star reveal sequence in LessonRunner CompletionScreen.
struct StarRevealView: View {
    let earnedStars: Int

    @State private var revealed: [Bool] = [false, false, false]

    var body: some View {
        HStack(spacing: 16) {
            ForEach(0..<3, id: \.self) { i in
                let earned = i < earnedStars
                Image(systemName: earned ? "star.fill" : "star")
                    .font(.system(size: 52))
                    .foregroundStyle(earned ? DuoColors.bee : DuoColors.bgSofter)
                    .scaleEffect(revealed[i] ? 1.0 : 0)
                    .rotationEffect(.degrees(revealed[i] ? 0 : -180))
            }
        }
        .onAppear {
            for i in 0..<3 {
                let delay = Double(i) * 0.38
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    if i < earnedStars {
                        SFXEngine.shared.play(.star)
                    }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
                        revealed[i] = true
                    }
                }
            }
        }
    }
}
