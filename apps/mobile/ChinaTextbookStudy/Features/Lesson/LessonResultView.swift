import SwiftUI

/// Duolingo-style multi-act lesson completion celebration (ios-lesson-5 /
/// ios-retention-4 / ios-economy-6).
///
/// Acts, in order (absent acts are skipped):
///   1. `stars`     — mascot + star reveal (confetti)
///   2. `shield`    — ❄️ 护盾保住了连胜（+「再备一个护盾」入口）
///   3. `streak`    — 当日首次学习：全屏大火焰 + 本周 7 格日历
///   4. `milestone` — 连胜里程碑宝石（B 波的幕并入本序列，不再重复弹）
///   5. `stats`     — 统计卡 + 成就横幅 + 宝箱
///   6. `quests`    — 今日任务进度从旧值动画推进到新值，可跳去领取
///
/// 幕间由「继续」推进，每幕入场音效错峰。
struct LessonResultView: View {
    let result: LessonRunResult
    @ObservedObject var progressStore: ProgressStore
    @Binding var path: [AppRoute]

    private enum Act: Hashable {
        case stars, conquest, shield, streak, milestone, stats, quests
    }

    /// 本课是否单元挑战（"{bookId}-u{n}-exam"）。
    private var isExamLesson: Bool { Economy.isExamLessonId(result.lessonId) }
    /// 挑战正确率 ≥ 0.8 = 单元征服（金色奖杯幕）。
    private var conqueredUnit: Bool { isExamLesson && result.accuracy >= 0.8 }

    @State private var acts: [Act] = []
    @State private var actIndex = 0
    @State private var showConfetti = false
    @State private var showChest = false
    @State private var displayedXp: Int = 0
    /// The chest slot this lesson just filled (every 5th lesson of a unit).
    @State private var chestSlotId: String?
    /// Frozen after-state of today's quests, captured once on appear so the
    /// quest act animates against a stable target.
    @State private var questsAfter: [ProgressStore.QuestSnapshot] = []
    /// Drives the quest bars: false = show pre-lesson values, true = animate
    /// to the post-lesson values.
    @State private var questsAnimated = false

    private var currentAct: Act { acts.indices.contains(actIndex) ? acts[actIndex] : .stars }
    private var isDarkAct: Bool {
        currentAct == .streak || currentAct == .milestone || currentAct == .conquest
    }

    var body: some View {
        ZStack {
            (isDarkAct ? Color.black.opacity(0.92) : DuoColors.bg)
                .ignoresSafeArea()

            // Confetti behind the first act and the stats act.
            ConfettiView(active: showConfetti)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            Group {
                switch currentAct {
                case .stars:     starsAct
                case .conquest:  conquestAct
                case .shield:    shieldAct
                case .streak:    streakAct
                case .milestone: milestoneAct
                case .stats:     statsAct
                case .quests:    questsAct
                }
            }
            .id(actIndex)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .opacity
            ))

            // Chest modal overlay (stats act only).
            if showChest, let chestSlotId {
                ChestModalView(
                    onClaim: { gems in
                        progressStore.addGems(gems)
                        progressStore.claimChest(chestSlotId)
                    },
                    onDismiss: { showChest = false }
                )
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: actIndex)
        .navigationTitle("结算")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar(isDarkAct ? .hidden : .visible, for: .navigationBar)
        .onAppear { setUp() }
    }

    // MARK: - Setup

    private func setUp() {
        var sequence: [Act] = [.stars]
        if conqueredUnit { sequence.append(.conquest) }
        if result.outcome.freezesConsumed > 0 { sequence.append(.shield) }
        // streakIncreased ⟺ 今天的第一次学习活动推进了连胜（当日首课）。
        if result.outcome.streakIncreased { sequence.append(.streak) }
        if result.outcome.milestoneGems > 0 { sequence.append(.milestone) }
        sequence.append(.stats)
        sequence.append(.quests)
        acts = sequence

        // 结算已经提交（completeLesson 在进入本页前完成），这里读到的就是
        // 「课后」的任务状态；「课前」值由本课贡献量反推。
        questsAfter = progressStore.questsSnapshot()

        SFXEngine.shared.play(.complete)
        HapticEngine.shared.success()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showConfetti = true }

        // Chest cadence: only when this lesson fills an unclaimed
        // every-5th-lesson slot (same rule as the path + web).
        if let slot = chestSlotAfterThisLesson(), !progressStore.isChestClaimed(slot.id) {
            chestSlotId = slot.id
        }
    }

    /// Advance to the next act, with per-act entry SFX (错峰).
    private func advanceAct() {
        guard actIndex + 1 < acts.count else { return }
        HapticEngine.shared.tap()
        actIndex += 1
        switch acts[actIndex] {
        case .conquest:  SFXEngine.shared.play(.star); HapticEngine.shared.success()
        case .shield:    SFXEngine.shared.play(.unlock)
        case .streak:    SFXEngine.shared.play(.star); HapticEngine.shared.success()
        case .milestone: SFXEngine.shared.play(.complete); HapticEngine.shared.success()
        case .stats:
            SFXEngine.shared.play(.progressTick)
            withAnimation(.easeOut(duration: 1.0).delay(0.4)) { displayedXp = awardedXp }
            if chestSlotId != nil {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                    withAnimation { showChest = true }
                }
            }
        case .quests:
            SFXEngine.shared.play(.tap)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                withAnimation(.easeOut(duration: 0.8)) { questsAnimated = true }
                SFXEngine.shared.play(.progressTick)
            }
        case .stars: break
        }
    }

    /// Pop back to the path (or book detail) — shared by the final act.
    private func exitToPath() {
        while path.count > 1 { path.removeLast() }
        if path.last.map({ if case .bookDetail = $0 { return false } else { return true } }) ?? true {
            path.removeAll()
        }
    }

    private func continueButton(_ title: String = "继续", action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title) }
            .buttonStyle(ChunkyButtonStyle(.primary))
            .padding(.horizontal, 24)
            .accessibilityIdentifier("result-continue")
    }

    // MARK: - Act 1: stars

    private var starsAct: some View {
        VStack(spacing: 24) {
            Spacer()

            // Mascot — plays its level-up reaction once on appear.
            MascotView(
                mood: result.stars >= 3 ? .proud : (result.stars >= 2 ? .happy : .think),
                size: 110,
                reactTo: .levelup
            )

            VStack(spacing: 8) {
                Text("完成！")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(DuoColors.ink)
                Text(result.lessonTitle)
                    .font(.subheadline)
                    .foregroundStyle(DuoColors.inkLight)
            }

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

            // 挑战双倍 —— exam ×2 与周末 ×2 各自亮牌，叠加时两张都在。
            if result.outcome.examDoubled {
                celebrationBanner(icon: "trophy.fill", tint: DuoColors.beetle, text: "⚔️ 挑战双倍 ×2")
            }
            // Weekend ×2 — the doubled XP must be visibly labeled.
            if result.outcome.weekendDoubled {
                celebrationBanner(icon: "bolt.fill", tint: DuoColors.bee, text: "周末双倍 ×2")
            }

            StarRevealView(earnedStars: result.stars)
                .padding(.vertical, 8)

            Spacer()

            continueButton { advanceAct() }
                .padding(.bottom, 28)
        }
    }

    // MARK: - Act 1.5: unit conquered (Wave E1, accuracy ≥ 0.8 on the exam)

    private var conquestAct: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "trophy.fill")
                .font(.system(size: 104, weight: .heavy))
                .foregroundStyle(DuoColors.bee)
                .shadow(color: DuoColors.bee.opacity(0.6), radius: 26)

            Text("单元征服！")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.white)

            Text("正确率 \(Int(round(result.accuracy * 100)))%，这个单元被你拿下啦")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Text("路径上的奖杯换上金色，快去看看吧")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white.opacity(0.65))

            Spacer()

            continueButton("太棒了！") { advanceAct() }
                .padding(.bottom, 28)
        }
    }

    // MARK: - Act 2: shield saved the streak (ios-economy-6)

    private var shieldAct: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "snowflake")
                .font(.system(size: 84, weight: .heavy))
                .foregroundStyle(DuoColors.secondary)
                .shadow(color: DuoColors.secondary.opacity(0.5), radius: 20)

            Text("❄️ 护盾保住了你 \(result.outcome.streakAfter) 天连胜")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(DuoColors.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Text("错过学习的那\(result.outcome.freezesConsumed > 1 ? " \(result.outcome.freezesConsumed) " : "")天，护盾自动帮你顶上了")
                .duoFont(.body)
                .foregroundStyle(DuoColors.inkMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            HStack(spacing: 8) {
                Image(systemName: "snowflake")
                    .font(.system(size: 14, weight: .heavy))
                Text("剩余护盾 \(progressStore.streakFreezes)/\(Economy.maxFreezes)")
                    .font(.system(size: 14, weight: .heavy))
            }
            .foregroundStyle(DuoColors.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(DuoColors.secondary.opacity(0.14), in: .capsule)

            Spacer()

            VStack(spacing: 10) {
                // 「再备一个护盾」入口 — 补上刚消耗掉的那个。
                let canBuy = progressStore.streakFreezes < Economy.maxFreezes
                    && progressStore.gems >= Economy.freezeCost
                Button {
                    if progressStore.buyStreakFreeze(cost: Economy.freezeCost) {
                        HapticEngine.shared.success()
                        SFXEngine.shared.play(.unlock)
                    } else {
                        HapticEngine.shared.wrong()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "diamond.fill").font(.system(size: 14, weight: .heavy))
                        Text(progressStore.streakFreezes >= Economy.maxFreezes
                             ? "护盾已满 \(Economy.maxFreezes)/\(Economy.maxFreezes)"
                             : "再备一个护盾  \(Economy.freezeCost)")
                    }
                }
                .buttonStyle(ChunkyButtonStyle(canBuy ? .secondary : .disabled))
                .disabled(!canBuy)
                .padding(.horizontal, 24)
                .accessibilityIdentifier("shield-rebuy")

                continueButton { advanceAct() }
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: - Act 3: full-screen streak (当日首课)

    private var streakAct: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "flame.fill")
                .font(.system(size: 110, weight: .heavy))
                .foregroundStyle(DuoColors.fox)
                .shadow(color: DuoColors.fox.opacity(0.6), radius: 28)

            Text("\(result.outcome.streakAfter)")
                .font(.system(size: 76, weight: .black))
                .foregroundStyle(.white)
                .monospacedDigit()

            Text("天连胜！")
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.white)

            // 本周 7 格日历（数据 = recentXP，今天必已点亮）。
            StreakCalendarView(
                entries: progressStore.recentXP(days: 7).map { (dateKey: $0.date, studied: $0.xp > 0) },
                todayStudied: true
            )
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(Color.white.opacity(0.08), in: .rect(cornerRadius: Radius.card))
            .padding(.horizontal, 24)

            Text("每天学一点，火焰不熄灭")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white.opacity(0.75))

            Spacer()

            continueButton { advanceAct() }
                .padding(.bottom, 28)
        }
    }

    // MARK: - Act 4: streak milestone (B 波的幕并入序列)

    private var milestoneAct: some View {
        VStack(spacing: 18) {
            Spacer()

            Image(systemName: "flame.fill")
                .font(.system(size: 96, weight: .heavy))
                .foregroundStyle(DuoColors.fox)
                .shadow(color: DuoColors.fox.opacity(0.6), radius: 24)

            Text("\(result.outcome.streakAfter)")
                .font(.system(size: 72, weight: .black))
                .foregroundStyle(.white)
                .monospacedDigit()

            Text("天连胜里程碑！")
                .font(.system(size: 22, weight: .heavy))
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 18, weight: .heavy))
                Text("+\(result.outcome.milestoneGems)")
                    .font(.system(size: 22, weight: .black))
                    .monospacedDigit()
            }
            .foregroundStyle(DuoColors.beetle)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.white, in: .capsule)

            Spacer()

            Button {
                advanceAct()
            } label: {
                Text("太棒了！")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(ChunkyButtonStyle(.primary))
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .accessibilityIdentifier("result-continue")
        }
    }

    // MARK: - Act 5: stats

    private var statsAct: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer(minLength: 16)

                Text("本节成绩")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(DuoColors.ink)

                if result.outcome.dailyGoalReachedNow {
                    celebrationBanner(icon: "target", tint: DuoColors.primary, text: "今日目标达成 🎉")
                }
                ForEach(result.outcome.newAchievements) { achievement in
                    celebrationBanner(
                        icon: "rosette",
                        tint: Color(hex: achievement.colorHex),
                        text: "解锁成就「\(achievement.name)」快去领取吧"
                    )
                }

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
                        icon: "diamond.fill",
                        value: "+\(result.outcome.gemsGained)",
                        label: "宝石",
                        tint: DuoColors.beetle
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

                Spacer(minLength: 16)

                continueButton { advanceAct() }
                    .padding(.bottom, 24)
            }
        }
    }

    // MARK: - Act 6: daily quest progress (ios-retention-4)

    /// 本课开始前的任务进度：从「课后」快照反推本课贡献。
    private func questProgressBefore(_ snap: ProgressStore.QuestSnapshot) -> Int {
        switch snap.quest.kind {
        case .earnXP:        return max(0, snap.progress - result.outcome.xpGained)
        case .finishLessons: return max(0, snap.progress - 1)
        case .reviewMistakes, .readTexts: return snap.progress
        }
    }

    private var hasClaimableQuest: Bool {
        questsAfter.contains { $0.isComplete && !$0.claimed }
    }

    private var questsAct: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 12)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 52, weight: .heavy))
                .foregroundStyle(DuoColors.bee)

            Text("今日任务")
                .font(.system(size: 26, weight: .heavy))
                .foregroundStyle(DuoColors.ink)

            VStack(spacing: 12) {
                ForEach(questsAfter) { snap in
                    questRow(snap)
                }
            }
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 10) {
                if hasClaimableQuest {
                    Button {
                        HapticEngine.shared.tap()
                        // 去「我的」页领取任务奖励。
                        path.removeAll()
                        path.append(.profile)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "gift.fill").font(.system(size: 14, weight: .heavy))
                            Text("去领取奖励")
                        }
                    }
                    .buttonStyle(ChunkyButtonStyle(.secondary))
                    .padding(.horizontal, 24)
                    .accessibilityIdentifier("quests-claim-jump")
                }

                Button {
                    exitToPath()
                } label: {
                    Text("继续学习")
                }
                .buttonStyle(ChunkyButtonStyle(.primary))
                .padding(.horizontal, 24)
                .accessibilityIdentifier("result-continue")
            }
            .padding(.bottom, 28)
        }
    }

    @ViewBuilder
    private func questRow(_ snap: ProgressStore.QuestSnapshot) -> some View {
        let before = questProgressBefore(snap)
        let shown = questsAnimated ? snap.progress : before
        let clamped = min(shown, snap.quest.target)
        let fraction = Double(clamped) / Double(max(1, snap.quest.target))

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((snap.isComplete ? DuoColors.primary : DuoColors.bee).opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: snap.isComplete && questsAnimated
                      ? "checkmark"
                      : snap.quest.kind.symbol)
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(snap.isComplete ? DuoColors.primary : DuoColors.bee)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(snap.quest.title)
                        .duoFont(.caption)
                        .foregroundStyle(DuoColors.ink)
                    Spacer()
                    Text("\(clamped)/\(snap.quest.target)")
                        .duoNumeral(.caption)
                        .foregroundStyle(snap.isComplete ? DuoColors.primary : DuoColors.inkMuted)
                        .contentTransition(.numericText())
                }
                StyledProgressBar(
                    progress: fraction,
                    height: 12,
                    trackColor: DuoColors.surfaceAlt
                )
            }
        }
        .padding(12)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(
                    snap.isComplete && questsAnimated ? DuoColors.primary.opacity(0.5) : DuoColors.border,
                    lineWidth: 2
                )
        }
    }

    // MARK: - Shared bits

    /// The chest slot immediately following this lesson, if any.
    private func chestSlotAfterThisLesson() -> ChestSlot? {
        guard let outline = try? DataLoader.shared.loadOutline(bookId: result.bookId) else { return nil }
        return Chest.chestAfter(
            bookId: result.bookId,
            lessons: outline.pathLessonMetas(bookId: result.bookId),
            lessonId: result.lessonId
        )
    }

    private var awardedXp: Int {
        if result.outcome.xpGained > 0 { return result.outcome.xpGained }
        // Fallback mirrors the real formula (first-perfect bonus unknown here).
        return Economy.xpForLesson(
            correctCount: result.correctCount,
            perfect: result.correctCount >= result.questionCount,
            firstPerfect: false,
            isWeekend: Economy.isWeekend(),
            isExam: isExamLesson
        )
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
