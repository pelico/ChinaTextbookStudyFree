import SwiftUI

/// Walks the SRS-due mistakes one at a time — same tactile feel as a lesson,
/// but no hearts are lost and finishing awards review XP.
struct MistakeReviewRunnerView: View {
    @ObservedObject var progressStore: ProgressStore
    @Binding var path: [AppRoute]

    @State private var queue: [MistakeEntry] = []
    @State private var index: Int = 0
    @State private var phase: LessonRunnerView.QuestionPhase = .answering
    @State private var currentAnswer: String = ""
    @State private var isCorrect: Bool? = nil
    @State private var correctCount: Int = 0
    @State private var awarded = false

    private let xpPerCorrect = 5

    var body: some View {
        Group {
            if queue.isEmpty {
                emptyState
            } else if index >= queue.count {
                summary
            } else {
                runner
            }
        }
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationTitle("错题复习")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MuteToggle() } }
        .onAppear { if queue.isEmpty { queue = progressStore.dueMistakes } }
        .onDisappear { AudioPlayer.shared.stop() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            MascotView(mood: .proud, size: 96)
            Text("没有要复习的错题").duoFont(.heading).foregroundStyle(DuoColors.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var summary: some View {
        VStack(spacing: 18) {
            MascotView(mood: .proud, size: 110, reactTo: .levelup)
            Text("复习完成！").duoFont(.title).foregroundStyle(DuoColors.ink)
            Text("答对 \(correctCount) / \(queue.count)").duoFont(.subhead).foregroundStyle(DuoColors.inkMuted)
            HStack(spacing: 6) {
                Image(systemName: "bolt.fill").font(.system(size: 15, weight: .heavy))
                Text("+\(correctCount * xpPerCorrect) XP").duoNumeral(.subhead)
            }
            .foregroundStyle(DuoColors.secondary)
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(DuoColors.secondary.opacity(0.14), in: .capsule)

            Button("返回错题本") { path.removeLast() }
                .buttonStyle(ChunkyButtonStyle(.primary))
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .onAppear {
            guard !awarded else { return }
            awarded = true
            progressStore.awardReviewXP(correctCount * xpPerCorrect, reviewedCount: queue.count)
            SFXEngine.shared.play(.complete); HapticEngine.shared.success()
        }
    }

    private var runner: some View {
        let entry = queue[index]
        let q = entry.question
        return VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button { path.removeLast() } label: {
                    Image(systemName: "xmark").font(.system(size: 20, weight: .black)).foregroundStyle(DuoColors.inkMuted).frame(width: 36, height: 36)
                }
                StyledProgressBar(progress: Double(index) / Double(max(queue.count, 1)), height: 14, trackColor: DuoColors.surfaceAlt)
                Text("\(index + 1)/\(queue.count)").duoNumeral(.caption).foregroundStyle(DuoColors.inkMuted)
            }
            .padding(.horizontal, 18).padding(.top, 6).padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("复习错题").duoFont(.caption).foregroundStyle(DuoColors.fox)
                    HStack(alignment: .top, spacing: 8) {
                        Text(q.question).duoFont(.subhead, weight: .medium).foregroundStyle(DuoColors.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TTSButton(path: q.audio?.question)
                    }
                    QuestionRendererView(question: q, answer: currentAnswer, phase: phase, isCorrect: isCorrect, onChange: { currentAnswer = $0 })
                        .id(q.id)
                }
                .padding(20)
            }
        }
        .safeAreaInset(edge: .bottom) {
            footer(entry: entry, q: q)
        }
    }

    @ViewBuilder
    private func footer(entry: MistakeEntry, q: Question) -> some View {
        VStack(spacing: 0) {
            if phase == .checked, let ok = isCorrect {
                HStack(spacing: 10) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(ok ? DuoColors.primary : DuoColors.danger)
                    Text(ok ? "答对了！" : "正确答案：\(q.answer)")
                        .duoFont(.caption).foregroundStyle(ok ? DuoColors.primary : DuoColors.danger)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 12)
            }
            Button {
                phase == .answering ? check(entry: entry) : advance()
            } label: {
                Text(phase == .answering ? "检查" : (index + 1 >= queue.count ? "完成复习" : "下一题"))
            }
            .buttonStyle(ChunkyButtonStyle(phase == .answering && currentAnswer.trimmingCharacters(in: .whitespaces).isEmpty ? .disabled : .primary))
            .disabled(phase == .answering && currentAnswer.trimmingCharacters(in: .whitespaces).isEmpty)
            .padding(.horizontal, 20).padding(.bottom, 32).padding(.top, 12)
        }
        .background(DuoColors.bg)
    }

    private func check(entry: MistakeEntry) {
        let ok = Grade.gradeAnswer(question: entry.question, userAnswer: currentAnswer)
        withAnimation(Motion.reveal) { phase = .checked; isCorrect = ok }
        if ok { correctCount += 1; SFXEngine.shared.play(.correct); HapticEngine.shared.correct() }
        else { SFXEngine.shared.play(.wrong); HapticEngine.shared.wrong() }
        progressStore.reviewMistake(lessonId: entry.lessonId, questionId: entry.question.id, isCorrect: ok)
    }

    private func advance() {
        SFXEngine.shared.play(.progressTick); HapticEngine.shared.tap()
        withAnimation(.easeInOut(duration: 0.2)) {
            index += 1; currentAnswer = ""; isCorrect = nil; phase = .answering
        }
    }
}
