import SwiftUI

/// 跳级测试（Wave E2，jump ahead）—— 锁定单元 banner「⚡ 跳到这里」入口。
///
/// 口径（双端一致）：
///   - 从目标单元之前所有单元的课程题库均匀抽 15 题，无课前讲解、无跳过；
///   - 每题只答一次（答错不重练、不扣心、不进错题本 —— 合成会话）；
///   - 正确率 ≥ 0.80 通过：前置未完成课程批量 completed{stars:1, accuracy:0.8}，
///     不发 XP / 宝石，庆祝后回路径（视口自动落到新当前节点）；
///   - 失败：扣 1 颗红心，可换一套题重试（0 心时给补心入口）。
struct JumpTestView: View {
    let bookId: String
    let unitNumber: Int
    @ObservedObject var progressStore: ProgressStore
    @Binding var path: [AppRoute]

    private enum Stage {
        case briefing        // 规则说明
        case running         // 做题中
        case passed(Int)     // 通过（解锁课程数）
        case failed(Int)     // 未通过（答对题数）
    }

    @State private var stage: Stage = .briefing
    @State private var questions: [Jump.SampledQuestion] = []
    /// 前置未完成课程 id（通过时批量标记）。
    @State private var priorUncompletedIds: [String] = []
    @State private var loadError: String?
    @State private var attempt = 1

    // Runner state（轻量：一题一次，不重练）
    @State private var index = 0
    @State private var currentAnswer = ""
    @State private var phase: LessonRunnerView.QuestionPhase = .answering
    @State private var isCorrect: Bool?
    @State private var correctCount = 0
    @State private var showConfetti = false
    @State private var showQuitConfirm = false

    private var total: Int { max(1, questions.count) }
    private var progress: Double { Double(index) / Double(total) }
    private var accuracy: Double { Double(correctCount) / Double(total) }

    var body: some View {
        Group {
            switch stage {
            case .briefing:
                briefing
            case .running:
                if let loadError {
                    errorView(loadError)
                } else if index < questions.count {
                    runner(question: questions[index].question)
                } else {
                    ProgressView().tint(DuoColors.primary)
                }
            case .passed(let unlocked):
                passedView(unlocked: unlocked)
            case .failed(let correct):
                failedView(correct: correct)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationBarHidden(true)
        .task { prepare() }
    }

    // MARK: - Briefing

    private var briefing: some View {
        VStack(spacing: 18) {
            HStack {
                closeButton
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)

            Spacer()

            Text("⚡")
                .font(.system(size: 64))
            Text("跳级测试")
                .duoFont(.title)
                .foregroundStyle(DuoColors.ink)
            Text("证明你已经掌握了前面的内容，\n就能直接跳到第 \(unitNumber) 单元！")
                .duoFont(.body)
                .foregroundStyle(DuoColors.inkMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            VStack(alignment: .leading, spacing: 10) {
                briefRow(icon: "list.number", text: "\(Jump.testSize) 道题，来自前面所有单元")
                briefRow(icon: "target", text: "答对 80% 以上就通过")
                briefRow(icon: "heart.fill", text: "没通过会扣 1 颗心，可以再试")
                briefRow(icon: "bolt.slash.fill", text: "跳过的课程不发经验和宝石")
            }
            .padding(16)
            .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.card)
                    .strokeBorder(DuoColors.border, lineWidth: 2)
            }
            .padding(.horizontal, 24)

            Spacer()

            Button("开始测试") {
                HapticEngine.shared.tap()
                SFXEngine.shared.play(.tap)
                withAnimation(Motion.reveal) { stage = .running }
            }
            .buttonStyle(ChunkyButtonStyle(questions.isEmpty ? .disabled : .primary))
            .disabled(questions.isEmpty && loadError == nil)
            .padding(.horizontal, 24)
            .accessibilityIdentifier("jump-start")

            Button("我再想想") { path.removeLast() }
                .buttonStyle(ChunkyButtonStyle(.ghost))
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
        }
    }

    private func briefRow(icon: String, text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(DuoColors.secondary)
                .frame(width: 24)
            Text(text)
                .duoFont(.caption)
                .foregroundStyle(DuoColors.ink)
        }
    }

    // MARK: - Runner

    @ViewBuilder
    private func runner(question q: Question) -> some View {
        VStack(spacing: 0) {
            // Header: [X] [progress] [⚡ 徽章]
            HStack(spacing: 14) {
                closeButton

                StyledProgressBar(progress: progress, height: 16, trackColor: DuoColors.surfaceAlt)

                HStack(spacing: 2) {
                    Text("⚡").font(.system(size: 11))
                    Text("\(index + 1)/\(total)")
                        .font(.system(size: 13, weight: .black))
                        .monospacedDigit()
                }
                .foregroundStyle(DuoColors.fox)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(DuoColors.fox.opacity(0.16), in: .capsule)
                .accessibilityLabel("跳级测试第 \(index + 1) 题，共 \(total) 题")
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Text("跳级测试 · 每题只有一次机会")
                        .duoFont(.caption)
                        .foregroundStyle(DuoColors.fox)
                        .padding(.top, 2)

                    HStack(alignment: .top, spacing: 10) {
                        Text(MathText.render(q.question))
                            .duoFont(.subhead, weight: .medium)
                            .foregroundStyle(DuoColors.ink)
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
                    .id("jump-\(attempt)-\(index)")
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if phase == .checked, let ok = isCorrect {
                jumpFeedback(ok: ok, question: q)
            } else {
                checkFooter(question: q)
            }
        }
        .overlay { if showQuitConfirm { quitConfirmOverlay } }
    }

    private func checkFooter(question: Question) -> some View {
        let empty = currentAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            let ok = Grade.gradeAnswer(question: question, userAnswer: currentAnswer)
            withAnimation(Motion.reveal) {
                phase = .checked
                isCorrect = ok
            }
            if ok {
                correctCount += 1
                SFXEngine.shared.play(.correct)
                HapticEngine.shared.correct()
            } else {
                // 测试口径：不扣心、不进错题本，只记分。
                SFXEngine.shared.play(.wrong)
                HapticEngine.shared.wrong()
            }
        } label: { Text("检查") }
            .buttonStyle(ChunkyButtonStyle(empty ? .disabled : .primary))
            .disabled(empty)
            .accessibilityIdentifier("检查答案")
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
            .padding(.top, 14)
            .background(DuoColors.bg)
    }

    private func jumpFeedback(ok: Bool, question: Question) -> some View {
        let accent = ok ? DuoColors.primary : DuoColors.danger
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ok ? "答对了！" : "这题不对")
                        .duoFont(.heading)
                        .foregroundStyle(accent)
                    if !ok {
                        Text("正确答案：\(MathText.render(question.answer))")
                            .duoFont(.caption)
                            .foregroundStyle(accent)
                    }
                }
                Spacer()
            }

            Button {
                advance()
            } label: { Text(index + 1 >= total ? "看结果" : "继续") }
                .buttonStyle(ChunkyButtonStyle(ok ? .primary : .danger))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 36)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(accent.opacity(0.12))
        .background(DuoColors.bg)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func advance() {
        SFXEngine.shared.play(.progressTick)
        HapticEngine.shared.tap()
        if index + 1 >= total {
            finish()
        } else {
            withAnimation(.easeInOut(duration: 0.2)) {
                index += 1
                currentAnswer = ""
                isCorrect = nil
                phase = .answering
            }
        }
    }

    private func finish() {
        if accuracy >= Jump.passAccuracy {
            // 通过：前置未完成课程批量标记（无 XP / 宝石），庆祝。
            let unlocked = progressStore.applyJumpUnlock(lessonIds: priorUncompletedIds)
            SFXEngine.shared.play(.complete)
            HapticEngine.shared.success()
            withAnimation(Motion.reveal) { stage = .passed(unlocked) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showConfetti = true }
        } else {
            // 失败：扣 1 颗红心，可重试。
            progressStore.loseHeart()
            SFXEngine.shared.play(.heartLoss)
            HapticEngine.shared.heartLoss()
            withAnimation(Motion.reveal) { stage = .failed(correctCount) }
        }
    }

    // MARK: - Passed

    private func passedView(unlocked: Int) -> some View {
        ZStack {
            ConfettiView(active: showConfetti)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            VStack(spacing: 18) {
                Spacer()
                MascotView(mood: .proud, size: 110, reactTo: .levelup)
                Text("跳级成功！")
                    .duoFont(.display)
                    .foregroundStyle(DuoColors.ink)
                Text("正确率 \(Int(round(accuracy * 100)))%，前面的 \(unlocked) 节课都算你过啦")
                    .duoFont(.body)
                    .foregroundStyle(DuoColors.inkMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Text("现在可以从第 \(unitNumber) 单元继续冒险 🗺️")
                    .duoFont(.caption)
                    .foregroundStyle(DuoColors.inkSofter)
                Spacer()
                Button("回到路径") {
                    HapticEngine.shared.tap()
                    path.removeAll()
                }
                .buttonStyle(ChunkyButtonStyle(.primary))
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
                .accessibilityIdentifier("jump-pass-continue")
            }
        }
    }

    // MARK: - Failed

    private func failedView(correct: Int) -> some View {
        let canRetry = progressStore.hearts > 0
        let canRefill = progressStore.gems >= Economy.heartRefillCost

        return VStack(spacing: 18) {
            Spacer()
            MascotView(mood: .sad, size: 110)
            Text("还差一点点")
                .duoFont(.title)
                .foregroundStyle(DuoColors.ink)
            Text("答对了 \(correct) / \(total) 题（需要 \(Int(Jump.passAccuracy * 100))%）\n先把前面的课程学扎实，或者再试一次！")
                .duoFont(.body)
                .foregroundStyle(DuoColors.inkMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.horizontal, 28)

            HStack(spacing: 4) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .heavy))
                Text("已扣 1 颗心 · 剩余 \(progressStore.hearts)")
                    .duoFont(.caption)
            }
            .foregroundStyle(DuoColors.danger)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(DuoColors.danger.opacity(0.12), in: .capsule)

            Spacer()

            VStack(spacing: 10) {
                if canRetry {
                    Button("换一套题再试") {
                        HapticEngine.shared.tap()
                        retry()
                    }
                    .buttonStyle(ChunkyButtonStyle(.primary))
                    .accessibilityIdentifier("jump-retry")
                } else {
                    Button {
                        if progressStore.buyHeartRefill(cost: Economy.heartRefillCost) {
                            HapticEngine.shared.success()
                            SFXEngine.shared.play(.unlock)
                            retry()
                        } else {
                            HapticEngine.shared.wrong()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "diamond.fill").font(.system(size: 14, weight: .heavy))
                            Text("用宝石补满心再试  \(Economy.heartRefillCost)")
                        }
                    }
                    .buttonStyle(ChunkyButtonStyle(canRefill ? .secondary : .disabled))
                    .disabled(!canRefill)
                }

                Button("下次再来") { path.removeLast() }
                    .buttonStyle(ChunkyButtonStyle(.ghost))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
    }

    /// 换一套题重试：新 seed 重抽，状态清零。
    private func retry() {
        attempt += 1
        index = 0
        correctCount = 0
        currentAnswer = ""
        isCorrect = nil
        phase = .answering
        sampleQuestions()
        withAnimation(Motion.reveal) { stage = .running }
    }

    // MARK: - Quit confirm

    private var closeButton: some View {
        Button {
            if case .running = stage, index > 0 || phase == .checked {
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
    }

    private var quitConfirmOverlay: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { showQuitConfirm = false }
                }

            VStack(spacing: Space.l) {
                MascotView(mood: .sad, size: 92)
                Text("现在退出，测试不算数哦")
                    .duoFont(.heading)
                    .foregroundStyle(DuoColors.ink)
                    .multilineTextAlignment(.center)
                Text("退出不扣心，下次可以重新来")
                    .duoFont(.caption)
                    .foregroundStyle(DuoColors.inkMuted)

                VStack(spacing: 10) {
                    Button("继续测试") {
                        withAnimation(.easeOut(duration: 0.2)) { showQuitConfirm = false }
                    }
                    .buttonStyle(ChunkyButtonStyle(.primary))

                    Button("退出") { path.removeLast() }
                        .buttonStyle(ChunkyButtonStyle(.ghost))
                        .accessibilityIdentifier("jump-quit")
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

    // MARK: - Error

    private func errorView(_ message: String) -> some View {
        VStack(spacing: Space.m) {
            Text("加载失败").duoFont(.heading)
            Text(message).duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
            Button("返回") { path.removeLast() }
                .buttonStyle(ChunkyButtonStyle(.ghost))
                .padding(.horizontal, 40)
        }
        .padding()
    }

    // MARK: - Data

    /// 收集目标单元之前所有普通课（kp 课，不含单元挑战）的题库与
    /// 未完成课程清单，然后抽第一套题。
    private func prepare() {
        do {
            let outline = try DataLoader.shared.loadOutline(bookId: bookId)
            let priorMetas = outline
                .pathLessonMetas(bookId: bookId)
                .filter { $0.unitNumber < unitNumber }
            guard !priorMetas.isEmpty else {
                loadError = "前面没有可以测试的课程"
                return
            }
            priorUncompletedIds = priorMetas
                .map(\.id)
                .filter { !progressStore.isLessonCompleted($0) }
            jumpSources = priorMetas.compactMap { meta in
                guard let lesson = try? DataLoader.shared.loadLesson(bookId: bookId, lessonId: meta.id),
                      !lesson.questions.isEmpty
                else { return nil }
                return Jump.QuestionSource(lessonId: meta.id, questions: lesson.questions)
            }
            guard !jumpSources.isEmpty else {
                loadError = "题库还没下载好，先回去下载课本吧"
                return
            }
            sampleQuestions()
        } catch {
            loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
        }
    }

    /// 前置课程题库缓存（重试重抽不用重读文件）。
    @State private var jumpSources: [Jump.QuestionSource] = []

    private func sampleQuestions() {
        questions = Jump.sampleQuestions(
            sources: jumpSources,
            seed: "jump-\(bookId)-u\(unitNumber)-\(attempt)-\(progressStore.leagueSalt ?? "local")"
        )
    }
}
