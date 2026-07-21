import SwiftUI

/// Duolingo-style lesson completion celebration.
/// Features: confetti, mascot, star reveal sequence, stat cards,
/// optional chest modal, and "完美通关!" badge.
struct LessonResultView: View {
    let result: LessonRunResult
    @ObservedObject var progressStore: ProgressStore
    @Binding var path: [AppRoute]

    @State private var showConfetti = false
    @State private var showChest = false
    @State private var displayedXp: Int = 0
    @State private var appeared = false

    var body: some View {
        ZStack {
            // Confetti background
            ConfettiView(active: showConfetti)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            ScrollView {
                VStack(spacing: 24) {
                    Spacer(minLength: 20)

                    // Mascot — plays its level-up reaction once on appear.
                    MascotView(
                        mood: result.stars >= 3 ? .proud : (result.stars >= 2 ? .happy : .think),
                        size: 100,
                        reactTo: .levelup
                    )

                    // Title
                    VStack(spacing: 8) {
                        Text("完成！")
                            .font(.system(size: 32, weight: .heavy))
                            .foregroundStyle(DuoColors.ink)
                        Text(result.lessonTitle)
                            .font(.subheadline)
                            .foregroundStyle(DuoColors.inkLight)
                    }

                    // Perfect badge
                    if result.stars == 3 {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                            Text("完美通关！")
                        }
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            LinearGradient(
                                colors: [DuoColors.primary, DuoColors.secondary],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: .capsule
                        )
                    }

                    // Streak / daily-goal celebration beats
                    if result.outcome.streakIncreased {
                        celebrationBanner(icon: "flame.fill", tint: DuoColors.fox, text: "连续 \(result.outcome.streakAfter) 天！")
                    }
                    if result.outcome.dailyGoalReachedNow {
                        celebrationBanner(icon: "target", tint: DuoColors.primary, text: "今日目标达成 🎉")
                    }

                    // Star reveal
                    StarRevealView(earnedStars: result.stars)
                        .padding(.vertical, 8)

                    // Stat cards
                    LazyVGrid(columns: [
                        GridItem(.flexible()), GridItem(.flexible())
                    ], spacing: 12) {
                        statCard(
                            icon: "bolt.fill",
                            value: "+\(displayedXp)",
                            label: "经验值",
                            tint: DuoColors.secondary
                        )
                        statCard(
                            icon: "target",
                            value: "\(Int(round(result.accuracy * 100)))%",
                            label: "正确率",
                            tint: result.accuracy >= 0.8 ? DuoColors.primary : DuoColors.fox
                        )
                        statCard(
                            icon: "checkmark.circle.fill",
                            value: "\(result.correctCount)/\(result.questionCount)",
                            label: "答对题数",
                            tint: DuoColors.primary
                        )
                    }
                    .padding(.horizontal)

                    Spacer(minLength: 20)

                    // Continue button
                    Button {
                        while path.count > 1 { path.removeLast() }
                        if path.last.map({ if case .bookDetail = $0 { return false } else { return true } }) ?? true {
                            path.removeAll()
                        }
                    } label: {
                        Text("继续学习")
                    }
                    .buttonStyle(ChunkyButtonStyle(.primary))
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }

            // Chest modal overlay
            if showChest {
                ChestModalView(
                    onClaim: { gems in
                        progressStore.addGems(gems)
                        progressStore.claimChest("\(result.bookId)-\(result.lessonId)")
                    },
                    onDismiss: { showChest = false }
                )
                .transition(.opacity)
            }
        }
        .navigationTitle("结算")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            appeared = true
            SFXEngine.shared.play(.complete)
            HapticEngine.shared.success()

            // Trigger confetti after a brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showConfetti = true
            }

            // XP count-up animation
            withAnimation(.easeOut(duration: 1.0).delay(0.8)) {
                displayedXp = awardedXp
            }

            // Check for chest (simplified: check if not already claimed)
            let chestId = "\(result.bookId)-\(result.lessonId)"
            if !progressStore.isChestClaimed(chestId) {
                // Show chest after star reveal completes (~1.5s)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation { showChest = true }
                }
            }
        }
    }

    private var awardedXp: Int {
        if result.outcome.xpGained > 0 { return result.outcome.xpGained }
        let base = result.questionCount * 10
        return result.stars == 3 ? base * 2 : base
    }

    private func celebrationBanner(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 16, weight: .heavy))
            Text(text).duoFont(.button)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18).padding(.vertical, 11)
        .background(tint, in: .capsule)
        .transition(.scale.combined(with: .opacity))
    }

    private func statCard(icon: String, value: String, label: String, tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.heavy))
                .foregroundStyle(DuoColors.ink)
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(DuoColors.inkLight)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(DuoColors.border, lineWidth: 2)
        }
    }
}
