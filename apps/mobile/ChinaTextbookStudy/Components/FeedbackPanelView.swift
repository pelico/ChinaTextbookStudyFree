import SwiftUI

/// Duolingo-style bottom slide-up feedback panel shown after checking an answer.
/// Ported from `apps/web/src/components/FeedbackPanel.tsx`.
struct FeedbackPanelView: View {
    let isCorrect: Bool
    let explanation: String
    let correctAnswer: String?
    let explanationAudioPath: String?
    let onContinue: () -> Void

    @State private var title: String = ""
    @State private var appeared = false

    private static let praisePool = ["太棒了！", "完美！", "做得好！", "天才！", "继续保持！", "漂亮！"]
    private static let comfortPool = ["再想想", "差一点", "加油", "没关系", "下次就对！"]

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 12) {
                // Title row: icon + random praise/comfort
                HStack(spacing: 10) {
                    Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(isCorrect ? DuoColors.primaryDark : DuoColors.dangerDark)
                        .rotationEffect(.degrees(appeared ? 0 : -180))
                        .scaleEffect(appeared ? 1 : 0)

                    Text(title)
                        .font(.title2.weight(.heavy))
                        .foregroundStyle(isCorrect ? DuoColors.primaryDark : DuoColors.dangerDark)
                        .opacity(appeared ? 1 : 0)
                        .offset(x: appeared ? 0 : -10)
                }

                // Correct answer (only shown when wrong)
                if !isCorrect, let correct = correctAnswer {
                    Text("正确答案：\(correct)")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(DuoColors.dangerDark)
                }

                // Explanation + TTS
                if !explanation.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Text(explanation)
                            .font(.body)
                            .foregroundStyle(DuoColors.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TTSButton(path: explanationAudioPath, size: 18)
                    }
                }

                // Continue button
                Button(action: onContinue) {
                    Text("继续")
                }
                .buttonStyle(ChunkyButtonStyle(isCorrect ? .primary : .danger))
            }
            .padding(20)
            .background(
                (isCorrect ? DuoColors.primary : DuoColors.danger).opacity(0.10)
            )
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(isCorrect ? DuoColors.primary : DuoColors.danger)
                    .frame(height: 4)
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .onAppear {
            let pool = isCorrect ? Self.praisePool : Self.comfortPool
            title = pool.randomElement() ?? (isCorrect ? "正确" : "错误")
            withAnimation(.spring(response: 0.4, dampingFraction: 0.65)) {
                appeared = true
            }
        }
    }
}
