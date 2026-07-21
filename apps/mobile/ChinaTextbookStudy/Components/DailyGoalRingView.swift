import SwiftUI

/// Circular progress ring for daily XP goal — ported from `DailyGoalRing.tsx`.
/// Green gradient while in progress, gold gradient when complete.
struct DailyGoalRingView: View {
    @ObservedObject var progressStore: ProgressStore
    var size: CGFloat = 72
    @State private var showGoalSheet = false

    private var lineWidth: CGFloat { max(5, size * 0.11) }

    private var progress: Double {
        let goal = progressStore.dailyGoal
        guard goal > 0 else { return 0 }
        return min(1.0, Double(progressStore.todayXp) / Double(goal))
    }

    private var isComplete: Bool { progress >= 1.0 }

    var body: some View {
        Button {
            showGoalSheet = true
        } label: {
            ZStack {
                // Track
                Circle()
                    .stroke(DuoColors.bgSofter, lineWidth: lineWidth)

                // Progress arc
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(
                            colors: isComplete
                                ? [Color(hex: 0xFFE066), Color(hex: 0xFFB300)]
                                : [Color(hex: 0x76E32A), Color(hex: 0x3FA800)],
                            center: .center
                        ),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(
                        color: (isComplete ? DuoColors.bee : DuoColors.primary).opacity(isComplete ? 0.55 : 0.25),
                        radius: 4
                    )
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: progress)

                // Center content
                VStack(spacing: 1) {
                    if isComplete {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: size * 0.26, weight: .bold))
                            .foregroundStyle(DuoColors.primary)
                    } else {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: size * 0.18))
                            .foregroundStyle(DuoColors.secondary)
                    }
                    Text("\(progressStore.todayXp)")
                        .font(.system(size: size * 0.24, weight: .heavy, design: .rounded))
                        .foregroundStyle(DuoColors.ink)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showGoalSheet) {
            goalAdjustSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Goal adjustment sheet

    @ViewBuilder
    private var goalAdjustSheet: some View {
        VStack(spacing: 20) {
            Text("每日目标").font(.title2.weight(.heavy)).foregroundStyle(DuoColors.ink)
            Text("选择你的每日 XP 目标")
                .font(.subheadline)
                .foregroundStyle(DuoColors.inkLight)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                ForEach([50, 100, 200, 500], id: \.self) { goal in
                    let isSelected = progressStore.dailyGoal == goal
                    Button {
                        progressStore.setDailyGoal(goal)
                        showGoalSheet = false
                    } label: {
                        VStack(spacing: 4) {
                            Text("\(goal)")
                                .font(.title2.weight(.heavy))
                            Text("XP")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(isSelected ? .white : DuoColors.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            isSelected ? DuoColors.primary : DuoColors.bgSofter,
                            in: .rect(cornerRadius: 14)
                        )
                        .overlay {
                            if !isSelected {
                                RoundedRectangle(cornerRadius: 14)
                                    .strokeBorder(DuoColors.bgSofter, lineWidth: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
        .padding(24)
    }
}
