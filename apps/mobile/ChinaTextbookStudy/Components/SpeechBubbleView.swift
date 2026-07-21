import SwiftUI

/// Speech bubble shown next to the mascot with contextual text.
/// Uses `MascotTriggers.bubblesByMood` and `MascotTriggers.tone(for:)`.
struct SpeechBubbleView: View {
    let text: String
    var mood: MascotMood = .happy

    @State private var appeared = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .foregroundStyle(toneColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(toneColor.opacity(0.10), in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(toneColor.opacity(0.25), lineWidth: 1.5)
            }
            .scaleEffect(appeared ? 1 : 0.5)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    appeared = true
                }
            }
    }

    private var toneColor: Color {
        switch MascotTriggers.tone(for: mood) {
        case .primary: return DuoColors.primary
        case .danger:  return DuoColors.danger
        case .neutral: return DuoColors.inkLight
        }
    }
}
