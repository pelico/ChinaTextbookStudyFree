import SwiftUI

/// Per-book story list — illustrated cards with completion crowns.
struct StoryListView: View {
    let bookId: String
    @Binding var path: [AppRoute]
    @ObservedObject private var progressStore = ProgressStore.shared

    @State private var stories: [Story] = []
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            if !stories.isEmpty {
                VStack(spacing: 12) {
                    ForEach(stories, id: \.id) { s in
                        Button { path.append(.storyReader(bookId: bookId, storyId: s.id)) } label: {
                            ReadingCard(
                                title: s.title,
                                subtitle: "第\(s.unitNumber)单元 · \(s.questions.count) 题",
                                symbol: "book.pages.fill",
                                tint: DuoColors.beetle,
                                done: progressStore.isReadingCompleted(s.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "book.closed").font(.system(size: 44)).foregroundStyle(DuoColors.inkSofter)
                    Text(loadError ?? "这本书还没有课外故事").duoFont(.subhead).foregroundStyle(DuoColors.inkMuted)
                }
                .padding(40)
            }
        }
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationTitle("课外故事")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private func load() {
        do { stories = (try DataLoader.shared.loadStories(bookId: bookId))?.stories ?? [] }
        catch { loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error) }
    }
}

/// Story reader: karaoke sentences + interactive graded comprehension.
struct StoryReaderView: View {
    let bookId: String
    let storyId: String
    @State private var story: Story?
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @ObservedObject private var progressStore = ProgressStore.shared

    var body: some View {
        Group {
            if let story {
                reader(story)
            } else {
                ProgressView().tint(DuoColors.primary)
            }
        }
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationTitle(story?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MuteToggle() } }
        .task {
            story = (try? DataLoader.shared.loadStories(bookId: bookId))?.stories.first { $0.id == storyId }
        }
        .onDisappear { AudioPlayer.shared.stop() }
    }

    private func reader(_ story: Story) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ReadAllButton(sentences: story.sentences, isPlaying: audioPlayer.isPlaying)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(story.sentences.enumerated()), id: \.offset) { idx, s in
                            sentenceRow(s, index: idx, sentences: story.sentences).id(idx)
                        }
                    }

                    if !story.questions.isEmpty {
                        Text("阅读理解").duoFont(.heading).foregroundStyle(DuoColors.ink).padding(.top, 8)
                        ForEach(story.questions) { q in
                            StoryQuizItem(question: Self.question(from: q))
                        }
                    }

                    completionButton(story)
                }
                .padding(20)
            }
            .onChange(of: audioPlayer.nowPlayingPath) { _, _ in
                if let i = activeIndex(story.sentences) {
                    withAnimation(Motion.reveal) { proxy.scrollTo(i, anchor: .center) }
                }
            }
        }
    }

    private func sentenceRow(_ s: PassageSentence, index: Int, sentences: [PassageSentence]) -> some View {
        let active = activeIndex(sentences) == index
        return HStack(alignment: .top, spacing: 10) {
            Text(s.text)
                .font(.system(size: 20, weight: active ? .heavy : .regular, design: .rounded))
                .foregroundStyle(active ? DuoColors.primary : DuoColors.ink)
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            TTSButton(path: s.audio, size: 16)
        }
        .padding(12)
        .background(active ? DuoColors.primary.opacity(0.10) : Color.clear, in: .rect(cornerRadius: Radius.control))
    }

    @ViewBuilder
    private func completionButton(_ story: Story) -> some View {
        let done = progressStore.isReadingCompleted(story.id)
        Button {
            guard !done else { return }
            progressStore.completeReading(id: story.id, xp: 15)
            HapticEngine.shared.success(); SFXEngine.shared.play(.complete)
        } label: {
            Text(done ? "已读完 ✓" : "读完了  +15 XP")
        }
        .buttonStyle(ChunkyButtonStyle(done ? .disabled : .primary))
        .disabled(done)
        .padding(.top, 8)
    }

    private func activeIndex(_ sentences: [PassageSentence]) -> Int? {
        guard let now = audioPlayer.nowPlayingPath else { return nil }
        return sentences.firstIndex { s in
            guard let a = s.audio else { return false }
            return AudioPlayer.shared.resolve(a)?.lastPathComponent == now
        }
    }

    /// Adapt a StoryQuestion into the lesson Question type so the shared
    /// renderer + grader can drive it.
    static func question(from q: StoryQuestion) -> Question {
        let type: QuestionType
        switch q.type {
        case "true_false": type = .trueFalse
        case "choice":     type = .choice
        default:            type = .fillBlankText
        }
        return Question(
            id: q.id, type: type, score: 1, difficulty: 1, knowledgePoint: "",
            question: q.question, options: q.options, answer: q.answer,
            explanation: q.explanation, audio: q.audio
        )
    }
}

/// One graded comprehension question — reuses the lesson question renderer.
private struct StoryQuizItem: View {
    let question: Question
    @State private var answer = ""
    @State private var phase: LessonRunnerView.QuestionPhase = .answering
    @State private var isCorrect: Bool?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                Text(question.question).duoFont(.subhead).foregroundStyle(DuoColors.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TTSButton(path: question.audio?.question, size: 15)
            }

            QuestionRendererView(question: question, answer: answer, phase: phase, isCorrect: isCorrect, onChange: { answer = $0 })

            if phase == .answering {
                Button("检查") { check() }
                    .buttonStyle(ChunkyButtonStyle(answer.trimmingCharacters(in: .whitespaces).isEmpty ? .disabled : .primary))
                    .disabled(answer.trimmingCharacters(in: .whitespaces).isEmpty)
            } else if let ok = isCorrect {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(ok ? DuoColors.primary : DuoColors.danger)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ok ? "答对了！" : "正确答案：\(question.answer)")
                            .duoFont(.caption).foregroundStyle(ok ? DuoColors.primary : DuoColors.danger)
                        if !question.explanation.isEmpty {
                            Text(question.explanation).duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(DuoColors.border, lineWidth: 2) }
    }

    private func check() {
        let ok = Grade.gradeAnswer(question: question, userAnswer: answer)
        withAnimation(Motion.reveal) { isCorrect = ok; phase = .checked }
        if ok { SFXEngine.shared.play(.correct); HapticEngine.shared.correct() }
        else { SFXEngine.shared.play(.wrong); HapticEngine.shared.wrong() }
    }
}
