import SwiftUI

/// Duolingo-faithful lesson runner:
///
/// - **Top**: [X] [green progress bar] [❤️ N]
/// - **Instruction**: bold text like "判断对错" / "选择正确答案"
/// - **Question**: text + TTS button
/// - **Options**: Duolingo option cards
/// - **Bottom**: green chunky "检查" button → colored feedback panel with mascot
///
/// The progress bar advances **only on correct answers**, and wrong questions are
/// re-queued to the end so the bar always completes and mistakes get re-practiced.
struct LessonRunnerView: View {
    let bookId: String
    let lessonId: String
    @ObservedObject var progressStore: ProgressStore
    @Binding var path: [AppRoute]

    @State private var lesson: Lesson?
    @State private var loadError: String?

    // Runner state — `queue` grows when a wrong answer is re-queued.
    @State private var queue: [Question] = []
    @State private var index: Int = 0
    @State private var phase: QuestionPhase = .answering
    @State private var currentAnswer: String = ""
    @State private var isCorrect: Bool? = nil
    @State private var solvedIDs: Set<Int> = []
    @State private var missedIDs: Set<Int> = []
    @State private var combo: Int = 0
    @State private var maxCombo: Int = 0
    @State private var attemptedThisQuestion = false

    // Session persistence (ios-lesson-3 / parity-13)
    /// 本会话内累计展示过的 XP（恢复时接着累计；结算以 store 计算为准）。
    @State private var sessionXp = 0
    /// ISO8601 开始时间 —— 恢复会话时沿用原会话的时间。
    @State private var sessionStartedAt = ISO8601DateFormatter().string(from: Date())
    /// 检测到可恢复的挂起会话时弹「继续上次 / 重新开始」。
    @State private var pendingResume: ActiveLessonSession?

    // Feedback presentation
    @State private var mascotMood: MascotMood = .happy
    @State private var feedbackReaction: MascotReaction? = nil
    @State private var feedbackBubble: String = ""
    @State private var feedbackTitleText: String = ""
    @State private var showCombo = false
    @State private var comboDisplayValue = 0
    @State private var xpFloaters: [XPFloatItem] = []

    // Gates & effects
    @State private var showQuitConfirm = false
    @State private var showOutOfHearts = false
    @State private var wrongFlash = 0
    @State private var showLessonSettings = false

    @ObservedObject private var settings = SettingsStore.shared
    @ObservedObject private var audioPlayer = AudioPlayer.shared

    private struct XPFloatItem: Identifiable { let id = UUID(); let amount: Int }
    enum QuestionPhase { case answering, checked }

    private var originalTotal: Int { max(1, lesson?.questions.count ?? 1) }
    private var progress: Double { Double(solvedIDs.count) / Double(originalTotal) }

    /// The equipped lesson backdrop, laid over the neutral surface at a reduced
    /// strength so question text keeps its contrast on every backdrop.
    @ViewBuilder
    private var lessonBackground: some View {
        ZStack {
            DuoColors.bg
            if let b = progressStore.equippedBackdropData, !b.stops.isEmpty {
                LinearGradient(colors: b.stops, startPoint: .top, endPoint: .bottom)
                    .opacity(b.needsOverlay ? 0.26 : 0.55)
            }
        }
    }

    var body: some View {
        Group {
            if lesson != nil, index < queue.count {
                runner(question: queue[index])
            } else if let loadError {
                VStack(spacing: Space.m) {
                    Text("加载失败").duoFont(.heading)
                    Text(loadError).duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                }
                .padding()
            } else {
                ProgressView().tint(DuoColors.primary)
            }
        }
        .navigationBarHidden(true)
        .task { load() }
        .onDisappear { audioPlayer.stop() }
    }

    @ViewBuilder
    private func runner(question q: Question) -> some View {
        VStack(spacing: 0) {
            header
            content(q: q)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(lessonBackground.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if phase == .checked, let ok = isCorrect {
                feedbackPanel(ok: ok, question: q)
            } else {
                checkFooter(question: q)
            }
        }
        .overlay { floaters }
        .overlay { comboOverlay }
        .overlay { FullScreenFlash(color: DuoColors.danger, trigger: wrongFlash) }
        .overlay { if showOutOfHearts { outOfHeartsGate } }
        .overlay { if showQuitConfirm { quitConfirmOverlay } }
        .overlay { if pendingResume != nil { resumePromptOverlay } }
        .sheet(isPresented: $showLessonSettings) { lessonSettingsSheet }
    }

    // MARK: - Header: [X] [progress] [❤️]

    private var header: some View {
        HStack(spacing: 14) {
            Button {
                // 零进度（一道题都没答过）直接退出不弹挽留 —— 对齐 web。
                if phase == .checked || !solvedIDs.isEmpty || !missedIDs.isEmpty {
                    HapticEngine.shared.tap()
                    withAnimation(.easeOut(duration: 0.2)) { showQuitConfirm = true }
                } else {
                    path.removeLast()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(DuoColors.inkMuted)
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("关闭")

            StyledProgressBar(progress: progress, height: 16, trackColor: DuoColors.surfaceAlt)

            // Weekend ×2 XP must be visible while it applies — small honest badge.
            if Economy.isWeekend() {
                HStack(spacing: 2) {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: 11, weight: .heavy))
                    Text("×2")
                        .font(.system(size: 13, weight: .black))
                        .monospacedDigit()
                }
                .foregroundStyle(DuoColors.bee)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(DuoColors.bee.opacity(0.16), in: .capsule)
                .accessibilityLabel("周末双倍经验")
            }

            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 16, weight: .heavy))
                    .foregroundStyle(progressStore.hearts > 0 ? DuoColors.danger : DuoColors.inkSofter)
                    .symbolEffect(.bounce, value: progressStore.hearts)
                Text("\(progressStore.hearts)")
                    .duoNumeral(.body)
                    .foregroundStyle(progressStore.hearts > 0 ? DuoColors.danger : DuoColors.inkSofter)
            }
            .accessibilityIdentifier("lesson-hearts")

            // 课内快捷设置：音效 / 触感 / 自动朗读（ios-lesson-14）。
            Button {
                HapticEngine.shared.tap()
                showLessonSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(DuoColors.inkSofter)
                    .frame(width: 32, height: 36)
            }
            .accessibilityLabel("课堂设置")
            .accessibilityIdentifier("lesson-settings")
        }
        .padding(.horizontal, 18)
        .padding(.top, 6)
        .padding(.bottom, 10)
    }

    // MARK: - In-lesson settings sheet (ios-lesson-14)

    private var lessonSettingsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("课堂设置")
                .duoFont(.heading)
                .foregroundStyle(DuoColors.ink)
                .padding(.top, 18)

            settingToggle(
                icon: "speaker.wave.2.fill",
                title: "音效",
                subtitle: "答题反馈与庆祝的声音",
                isOn: Binding(get: { !settings.isMuted }, set: { settings.isMuted = !$0 })
            )
            settingToggle(
                icon: "iphone.radiowaves.left.and.right",
                title: "触感振动",
                subtitle: "答对答错时的轻微振动",
                isOn: $settings.hapticEnabled
            )
            settingToggle(
                icon: "text.bubble.fill",
                title: "自动朗读",
                subtitle: "进入新题目时自动朗读题干",
                isOn: $settings.autoNarrate
            )

            Button("好了") { showLessonSettings = false }
                .buttonStyle(ChunkyButtonStyle(.primary))
                .padding(.top, 4)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(DuoColors.bg)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }

    private func settingToggle(icon: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(DuoColors.secondary)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).duoFont(.subhead).foregroundStyle(DuoColors.ink)
                Text(subtitle).duoFont(.micro).foregroundStyle(DuoColors.inkMuted)
            }
            Spacer()
            Toggle("", isOn: isOn)
                .labelsHidden()
                .tint(DuoColors.primary)
        }
        .padding(12)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.card)
                .strokeBorder(DuoColors.border, lineWidth: 2)
        }
    }

    // MARK: - Question content

    private func content(q: Question) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                Text(instructionText(q.type))
                    .duoFont(.heading)
                    .foregroundStyle(DuoColors.ink)
                    .padding(.top, 6)

                HStack(alignment: .top, spacing: 10) {
                    Text(MathText.render(q.question))
                        .duoFont(.subhead, weight: .medium)
                        .foregroundStyle(DuoColors.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(4)
                    TTSButton(path: q.audio?.question)
                }

                QuestionRendererView(
                    question: q,
                    answer: currentAnswer,
                    phase: phase,
                    isCorrect: isCorrect,
                    onChange: { currentAnswer = $0 }
                )
                .id("\(q.id)-\(index)")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .onChange(of: index) { _, _ in autoNarrate(q) }
        .onAppear { autoNarrate(q) }
    }

    // MARK: - Overlays

    @ViewBuilder private var floaters: some View {
        ForEach(xpFloaters) { f in
            XPFloaterView(amount: f.amount) { xpFloaters.removeAll { $0.id == f.id } }
        }
    }

    @ViewBuilder private var comboOverlay: some View {
        if showCombo {
            ComboOverlayView(combo: comboDisplayValue)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { showCombo = false }
                }
        }
    }

    // MARK: - Instruction text

    private func instructionText(_ type: QuestionType) -> String {
        switch type {
        case .trueFalse:     return "判断对错"
        case .choice:        return "选择正确答案"
        case .fillBlank:     return "填写答案"
        case .calculation:   return "计算结果"
        case .fillBlankText: return "填写答案"
        case .wordOrder:     return "组成正确的句子"
        case .matching:      return "将配对连线"
        case .wordProblem:   return "解答应用题"
        }
    }

    // MARK: - Feedback panel (mascot + accent title + big CTA)

    private func feedbackPanel(ok: Bool, question: Question) -> some View {
        let accent = ok ? DuoColors.primary : DuoColors.danger
        let surface = accent.opacity(0.12)

        return VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(DuoColors.border)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)

            HStack(alignment: .center, spacing: 12) {
                MascotView(mood: mascotMood, size: 54, reactTo: feedbackReaction, reactKey: index + 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(feedbackTitleText.isEmpty ? (ok ? "正确" : "答错了") : feedbackTitleText)
                        .duoFont(.heading)
                        .foregroundStyle(accent)
                    if !ok {
                        Text("正确答案：\(MathText.render(question.answer))")
                            .duoFont(.caption)
                            .foregroundStyle(accent)
                    } else if !feedbackBubble.isEmpty {
                        Text(feedbackBubble)
                            .duoFont(.caption)
                            .foregroundStyle(accent.opacity(0.85))
                    }
                }
                Spacer()
            }

            if !question.explanation.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Text(MathText.render(question.explanation))
                        .duoFont(.body)
                        .foregroundStyle(DuoColors.inkMuted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    TTSButton(path: question.audio?.explanation, size: 16)
                }
            }

            Button { proceed(question: question) } label: { Text(ok ? "继续" : "知道了") }
                .buttonStyle(ChunkyButtonStyle(ok ? .primary : .danger))
                .padding(.top, 2)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(surface)
        .background(DuoColors.bg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    // MARK: - Check footer

    private func checkFooter(question: Question) -> some View {
        let empty = currentAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button { check(question: question) } label: { Text("检查") }
            .buttonStyle(ChunkyButtonStyle(empty ? .disabled : .primary))
            .disabled(empty)
            .accessibilityIdentifier("检查答案")
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
            .padding(.top, 14)
            .background(DuoColors.bg)
    }

    // MARK: - Out-of-hearts gate

    private var outOfHeartsGate: some View {
        OutOfHeartsGate(
            progressStore: progressStore,
            onRefill: {
                if progressStore.buyHeartRefill(cost: Economy.heartRefillCost) {
                    HapticEngine.shared.success()
                    SFXEngine.shared.play(.unlock)
                    showOutOfHearts = false
                    advance()
                } else {
                    HapticEngine.shared.wrong()
                }
            },
            // 断心闭环（ios-lesson-7）：去错题本做一组复习赚回 1 颗心。
            // 会话已持久化 —— 复习完回到这节课会从当前题目继续。
            onReview: {
                HapticEngine.shared.tap()
                path.removeLast()
                path.append(.reviewRunner)
            },
            onQuit: { path.removeLast() }   // 被迫退出：保留会话，回来可续
        )
        .transition(.opacity)
    }

    // MARK: - Quit confirm overlay (ios-lesson-13 / ios-feel-7)

    /// 自绘退出挽留：难过的聪聪 + 主按钮「继续学习」置顶。零进度时根本
    /// 不会走到这里（header 直接退出）。
    private var quitConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { showQuitConfirm = false }
                }

            VStack(spacing: Space.l) {
                MascotView(mood: .sad, size: 92)

                Text("再坚持一下，快完成了！")
                    .duoFont(.heading)
                    .foregroundStyle(DuoColors.ink)
                    .multilineTextAlignment(.center)

                Text("已答对 \(solvedIDs.count) / \(originalTotal) 题，现在放弃太可惜啦")
                    .duoFont(.caption)
                    .foregroundStyle(DuoColors.inkMuted)
                    .multilineTextAlignment(.center)

                VStack(spacing: 10) {
                    Button("继续学习") {
                        HapticEngine.shared.tap()
                        withAnimation(.easeOut(duration: 0.2)) { showQuitConfirm = false }
                    }
                    .buttonStyle(ChunkyButtonStyle(.primary))

                    Button("退出") {
                        progressStore.clearLessonSession()   // 主动退出：不保留会话
                        path.removeLast()
                    }
                    .buttonStyle(ChunkyButtonStyle(.ghost))
                    .accessibilityIdentifier("lesson-quit")
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 340)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.large))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large)
                    .strokeBorder(DuoColors.border, lineWidth: 2)
            }
            .padding(24)
        }
        .transition(.opacity)
    }

    // MARK: - Resume prompt overlay (ios-lesson-3)

    /// 进入同一课检测到挂起会话时的选择层：继续上次 or 重新开始。
    private var resumePromptOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: Space.l) {
                MascotView(mood: .wave, size: 92)

                Text("上次学到一半哦")
                    .duoFont(.heading)
                    .foregroundStyle(DuoColors.ink)

                if let session = pendingResume {
                    Text("已答对 \(session.solvedIds.count) / \(originalTotal) 题，接着做还是重新来？")
                        .duoFont(.caption)
                        .foregroundStyle(DuoColors.inkMuted)
                        .multilineTextAlignment(.center)
                }

                VStack(spacing: 10) {
                    Button("继续上次（第 \((pendingResume?.solvedIds.count ?? 0) + 1) 题）") {
                        HapticEngine.shared.tap()
                        if let session = pendingResume { applyResume(session) }
                        withAnimation(.easeOut(duration: 0.2)) { pendingResume = nil }
                    }
                    .buttonStyle(ChunkyButtonStyle(.primary))
                    .accessibilityIdentifier("lesson-resume")

                    Button("重新开始") {
                        HapticEngine.shared.tap()
                        progressStore.clearLessonSession()
                        withAnimation(.easeOut(duration: 0.2)) { pendingResume = nil }
                    }
                    .buttonStyle(ChunkyButtonStyle(.ghost))
                    .accessibilityIdentifier("lesson-restart")
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 340)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.large))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large)
                    .strokeBorder(DuoColors.border, lineWidth: 2)
            }
            .padding(24)
        }
        .transition(.opacity)
    }

    private func autoNarrate(_ q: Question) {
        guard settings.autoNarrate, !settings.isMuted else { return }
        guard let path = q.audio?.question else { return }
        audioPlayer.play(path: path, settings: settings)
    }

    // MARK: - Actions

    private func check(question: Question) {
        let ok = Grade.gradeAnswer(question: question, userAnswer: currentAnswer)
        feedbackTitleText = pickTitle(ok: ok)

        withAnimation(Motion.reveal) {
            phase = .checked
            isCorrect = ok
        }

        if ok {
            solvedIDs.insert(question.id)
            combo += 1; maxCombo = max(maxCombo, combo)
            SFXEngine.shared.play(.correct); HapticEngine.shared.correct()
            // Per-correct XP floater — mirrors the real per-question rate,
            // doubled on weekends so the promise matches the payout.
            let floatXp = Economy.xpPerCorrect * (Economy.isWeekend() ? Economy.weekendXpMultiplier : 1)
            sessionXp += floatXp
            xpFloaters.append(XPFloatItem(amount: floatXp))
            if [3, 5, 10].contains(combo) { comboDisplayValue = combo; showCombo = true }
        } else {
            attemptedThisQuestion = true
            missedIDs.insert(question.id)
            combo = 0
            queue.append(question)                       // re-practice later
            SFXEngine.shared.play(.wrong); HapticEngine.shared.wrong()
            SFXEngine.shared.play(.heartLoss); HapticEngine.shared.heartLoss()
            wrongFlash += 1
            progressStore.loseHeart()
            progressStore.recordMistake(lessonId: lessonId, lessonTitle: lesson?.title, question: question)
        }

        let ctx = MascotTriggerContext(
            isCorrect: ok,
            isPerfectSession: missedIDs.isEmpty,
            attemptCount: attemptedThisQuestion ? 2 : 1,
            remainingHearts: progressStore.hearts, combo: combo, maxCombo: maxCombo,
            index: solvedIDs.count, total: originalTotal, totalCorrectInSession: solvedIDs.count
        )
        mascotMood = MascotTriggers.decideMood(ctx)
        feedbackReaction = MascotTriggers.decideReaction(ctx)
        feedbackBubble = ok ? MascotTriggers.pickBubble(mood: mascotMood) : ""

        // 每次判定后立即落盘会话（ios-lesson-3）：App 被杀 / 断心退出后，
        // 下次进入同一课可从下一题无缝恢复。
        persistSession()
    }

    /// Persist the in-flight session. `queue[(index+1)...]` is the remaining
    /// queue as of "after this question" — a wrong answer already re-appended
    /// the question to the tail, so resuming never re-asks the front card.
    private func persistSession() {
        guard index + 1 <= queue.count else { return }
        let remaining = queue[(index + 1)...].map(\.id)
        // 全部答完（结算在即）就没有可恢复的会话了。
        guard solvedIDs.count < originalTotal, !remaining.isEmpty else { return }
        progressStore.upsertLessonSession(ActiveLessonSession(
            bookId: bookId,
            lessonId: lessonId,
            queueIds: Array(remaining),
            solvedIds: Array(solvedIDs).sorted(),
            missedIds: Array(missedIDs).sorted(),
            combo: combo,
            maxCombo: maxCombo,
            sessionXp: sessionXp,
            startedAt: sessionStartedAt
        ))
    }

    /// Restore runner state from a persisted session (resume path).
    private func applyResume(_ session: ActiveLessonSession) {
        guard let lesson else { return }
        let byId = Dictionary(uniqueKeysWithValues: lesson.questions.map { ($0.id, $0) })
        let restoredQueue = session.queueIds.compactMap { byId[$0] }
        // 课程内容更新导致队列失效 → 放弃恢复，从头来。
        guard !restoredQueue.isEmpty else {
            progressStore.clearLessonSession()
            return
        }
        queue = restoredQueue
        index = 0
        solvedIDs = Set(session.solvedIds).intersection(byId.keys)
        missedIDs = Set(session.missedIds).intersection(byId.keys)
        combo = session.combo
        maxCombo = session.maxCombo
        sessionXp = session.sessionXp
        sessionStartedAt = session.startedAt
        currentAnswer = ""
        isCorrect = nil
        phase = .answering
        attemptedThisQuestion = false
    }

    /// Called by the feedback panel's continue button. Gates on hearts.
    private func proceed(question: Question) {
        if !isCorrectValue && progressStore.hearts == 0 {
            withAnimation(.easeOut(duration: 0.2)) { showOutOfHearts = true }
            return
        }
        advance()
    }

    private var isCorrectValue: Bool { isCorrect ?? false }

    private func advance() {
        SFXEngine.shared.play(.progressTick); HapticEngine.shared.tap()
        guard let lesson else { return }
        if solvedIDs.count >= originalTotal || index + 1 >= queue.count {
            finish(lesson: lesson)
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                index += 1
                currentAnswer = ""
                isCorrect = nil
                phase = .answering
                attemptedThisQuestion = false
            }
        }
    }

    private func finish(lesson: Lesson) {
        // 首答口径：missedIDs 记录的是「首答就错过」的题，correctCount = 首答答对数。
        let correctCount = originalTotal - missedIDs.count
        let outcome = progressStore.completeLesson(lessonId: lessonId, correctCount: correctCount, questionCount: originalTotal)
        let result = LessonRunResult(
            bookId: bookId, lessonId: lessonId, lessonTitle: lesson.title,
            questionCount: originalTotal, correctCount: correctCount, outcome: outcome
        )
        path.removeLast(); path.append(.lessonResult(result))
    }

    private func pickTitle(ok: Bool) -> String {
        let pool = ok
            ? ["太棒了！", "完美！", "做得好！", "天才！", "继续保持！", "漂亮！"]
            : ["答错了", "差一点", "加油", "没关系", "下次就对！"]
        return pool.randomElement() ?? (ok ? "正确" : "答错了")
    }

    private func load() {
        do {
            let l = try DataLoader.shared.loadLesson(bookId: bookId, lessonId: lessonId)
            self.lesson = l
            self.queue = l.questions
            // 检测挂起会话（ios-lesson-3）：有实际进度才值得弹恢复层。
            if let session = progressStore.activeSession(for: lessonId),
               !session.solvedIds.isEmpty || !session.missedIds.isEmpty {
                self.pendingResume = session
            }
        } catch {
            self.loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }
}

// MARK: - Out-of-hearts gate

/// Blocking modal shown when the learner runs out of hearts mid-lesson.
/// Offers a gem refill, a review path that earns back one heart
/// (ios-lesson-7), or an exit, plus a live recharge countdown.
private struct OutOfHeartsGate: View {
    @ObservedObject var progressStore: ProgressStore
    let onRefill: () -> Void
    let onReview: () -> Void
    let onQuit: () -> Void

    private let refillCost = Economy.heartRefillCost
    @State private var tick = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var hasDueMistakes: Bool { !progressStore.dueMistakes.isEmpty }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()

            VStack(spacing: Space.l) {
                Image(systemName: "heart.slash.fill")
                    .font(.system(size: 60, weight: .heavy))
                    .foregroundStyle(DuoColors.danger)

                Text("心心用完了")
                    .duoFont(.title)
                    .foregroundStyle(DuoColors.ink)

                if let next = progressStore.nextHeartAt {
                    VStack(spacing: 2) {
                        Text("下一颗心还需")
                            .duoFont(.caption)
                            .foregroundStyle(DuoColors.inkMuted)
                        Text(countdown(to: next))
                            .duoNumeral(.title)
                            .foregroundStyle(DuoColors.danger)
                    }
                }

                VStack(spacing: 10) {
                    Button(action: onRefill) {
                        HStack(spacing: 6) {
                            Image(systemName: "diamond.fill").font(.system(size: 14, weight: .heavy))
                            Text("用宝石补满  \(refillCost)")
                        }
                    }
                    .buttonStyle(ChunkyButtonStyle(progressStore.gems >= refillCost ? .secondary : .disabled))
                    .disabled(progressStore.gems < refillCost)

                    if hasDueMistakes {
                        Button(action: onReview) {
                            Text("做一组复习回 1 颗心 ❤️")
                        }
                        .buttonStyle(ChunkyButtonStyle(.primary))
                        .accessibilityIdentifier("hearts-review-earnback")

                        Text("这节课已帮你记住进度，复习完回来接着学")
                            .duoFont(.micro)
                            .foregroundStyle(DuoColors.inkMuted)
                            .multilineTextAlignment(.center)
                    }

                    Button("退出练习", action: onQuit)
                        .buttonStyle(ChunkyButtonStyle(.ghost))
                }
            }
            .padding(Space.xl)
            .frame(maxWidth: 340)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.large))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.large)
                    .strokeBorder(DuoColors.border, lineWidth: 2)
            }
            .padding(24)
        }
        .onReceive(timer) { _ in
            tick = Date()
            progressStore.tickHeartRecharge()
        }
    }

    private func countdown(to date: Date) -> String {
        let remaining = max(0, date.timeIntervalSince(tick))
        return String(format: "%d:%02d", Int(remaining) / 60, Int(remaining) % 60)
    }
}
