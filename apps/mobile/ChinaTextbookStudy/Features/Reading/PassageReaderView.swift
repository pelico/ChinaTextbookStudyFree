import SwiftUI

extension PassageKind {
    var displayName: String {
        switch self {
        case .poem, .ancientPoem: return "古诗"
        case .prose:              return "课文"
        case .story:              return "故事"
        case .song:               return "儿歌"
        case .dialogue:           return "对话"
        }
    }
    var symbol: String {
        switch self {
        case .poem, .ancientPoem: return "scroll.fill"
        case .prose:              return "text.alignleft"
        case .story:              return "book.fill"
        case .song:               return "music.note"
        case .dialogue:           return "bubble.left.and.bubble.right.fill"
        }
    }
}

/// Per-book passage list — illustrated cards with completion crowns.
struct PassageListView: View {
    let bookId: String
    @Binding var path: [AppRoute]
    @ObservedObject private var progressStore = ProgressStore.shared

    @State private var passages: [Passage] = []
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            if !passages.isEmpty {
                VStack(spacing: 12) {
                    ForEach(passages, id: \.id) { p in
                        Button { path.append(.passageReader(bookId: bookId, passageId: p.id)) } label: {
                            ReadingCard(
                                title: p.title,
                                subtitle: "\(p.kind.displayName) · \(p.sentences.count) 句",
                                symbol: p.kind.symbol,
                                tint: DuoColors.secondary,
                                done: progressStore.isReadingCompleted(p.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)
            } else {
                emptyState
            }
        }
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationTitle("课文听读")
        .navigationBarTitleDisplayMode(.inline)
        .task { load() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.book.closed").font(.system(size: 44)).foregroundStyle(DuoColors.inkSofter)
            Text(loadError ?? "这本书还没有课文听读")
                .duoFont(.subhead).foregroundStyle(DuoColors.inkMuted)
                .multilineTextAlignment(.center)
        }
        .padding(40)
    }

    private func load() {
        do { passages = (try DataLoader.shared.loadPassages(bookId: bookId))?.passages ?? [] }
        catch { loadError = (error as? LocalizedError)?.errorDescription ?? String(describing: error) }
    }
}

/// Shared illustrated card for passages & stories.
struct ReadingCard: View {
    let title: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let done: Bool

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.control)
                    .fill(LinearGradient(colors: [tint.opacity(0.85), tint], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 60, height: 60)
                Image(systemName: symbol).font(.system(size: 26, weight: .bold)).foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).duoFont(.subhead).foregroundStyle(DuoColors.ink).lineLimit(2).multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(subtitle).duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                    if !done {
                        HStack(spacing: 2) {
                            Image(systemName: "bolt.fill").font(.system(size: 9, weight: .heavy))
                            Text("+10").duoFont(.micro)
                        }
                        .foregroundStyle(DuoColors.secondary)
                    }
                }
            }
            Spacer()
            if done {
                Image(systemName: "crown.fill").font(.system(size: 22)).foregroundStyle(DuoColors.bee)
            } else {
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .heavy)).foregroundStyle(DuoColors.inkSofter)
            }
        }
        .padding(14)
        .background(DuoColors.surface, in: .rect(cornerRadius: Radius.card))
        .overlay { RoundedRectangle(cornerRadius: Radius.card).strokeBorder(done ? DuoColors.bee.opacity(0.5) : DuoColors.border, lineWidth: 2) }
    }
}

/// Sentence-by-sentence reader with karaoke play-through + per-line TTS.
struct PassageReaderView: View {
    let bookId: String
    let passageId: String
    @State private var passage: Passage?
    @ObservedObject private var audioPlayer = AudioPlayer.shared
    @ObservedObject private var progressStore = ProgressStore.shared

    var body: some View {
        Group {
            if let passage {
                reader(passage)
            } else {
                ProgressView().tint(DuoColors.primary)
            }
        }
        .background(DuoColors.bg.ignoresSafeArea())
        .navigationTitle(passage?.title ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { MuteToggle() } }
        .task {
            passage = (try? DataLoader.shared.loadPassages(bookId: bookId))?.passages.first { $0.id == passageId }
        }
        .onDisappear { AudioPlayer.shared.stop() }
    }

    private func reader(_ passage: Passage) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let author = passage.author, !author.isEmpty {
                        Text("—— \(author)").duoFont(.caption).foregroundStyle(DuoColors.inkMuted)
                    }

                    ReadAllButton(sentences: passage.sentences, isPlaying: audioPlayer.isPlaying)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(passage.sentences.enumerated()), id: \.offset) { idx, s in
                            sentenceRow(s, index: idx)
                                .id(idx)
                        }
                    }

                    completionButton(passage)
                }
                .padding(20)
            }
            .onChange(of: audioPlayer.nowPlayingPath) { _, _ in
                if let i = activeIndex(passage.sentences) {
                    withAnimation(Motion.reveal) { proxy.scrollTo(i, anchor: .center) }
                }
            }
        }
    }

    private func sentenceRow(_ s: PassageSentence, index: Int) -> some View {
        let active = activeIndex(passage?.sentences ?? []) == index
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
    private func completionButton(_ passage: Passage) -> some View {
        let done = progressStore.isReadingCompleted(passage.id)
        Button {
            guard !done else { return }
            progressStore.completeReading(id: passage.id, xp: 10)
            HapticEngine.shared.success(); SFXEngine.shared.play(.complete)
        } label: {
            Text(done ? "已读完 ✓" : "读完了  +10 XP")
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
}

/// "Read the whole thing" button — queues every sentence's audio.
struct ReadAllButton: View {
    let sentences: [PassageSentence]
    let isPlaying: Bool

    var body: some View {
        Button {
            if isPlaying {
                AudioPlayer.shared.stop()
            } else {
                HapticEngine.shared.tap()
                AudioPlayer.shared.play(paths: sentences.map(\.audio))
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill").font(.system(size: 15, weight: .heavy))
                Text(isPlaying ? "停止朗读" : "朗读全文")
            }
        }
        .buttonStyle(ChunkySmallButtonStyle(
            background: isPlaying ? DuoColors.danger : DuoColors.primary,
            shadowColor: isPlaying ? DuoColors.dangerDark : DuoColors.primaryDark
        ))
    }
}
