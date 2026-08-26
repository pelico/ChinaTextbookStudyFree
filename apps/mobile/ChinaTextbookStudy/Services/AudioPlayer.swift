import Foundation
import AVFoundation
import Combine

/// 统一音频会话协调器(critic-4)。
///
/// App 里有两类声音,对会话的诉求相反:
/// 1. **SFX / 判分短音** —— 走 `.ambient`:尊重静音拨片、与用户自己的音乐混音;
/// 2. **TTS / 课文长音频** —— 播放期间临时切 `.playback(.spokenAudio, .duckOthers)`
///    (静音拨片下朗读也要能听到,并把背景音乐压低),播完立刻恢复 ambient。
///
/// 此前 `SFXEngine` 与 `AudioPlayer` 各自 `setCategory` 互相打架 —— 谁后启动谁
/// 说了算,SFX 会意外顶掉朗读会话(反之亦然)。现在两边都只跟协调器打交道,
/// 类别切换有唯一出口。
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private enum Mode { case none, ambient, spokenAudio }
    private var mode: Mode = .none

    private init() {}

    /// SFX 播放前调用:保证会话至少处于 `.ambient`。
    /// 朗读进行中(.spokenAudio)不降级 —— 短音效借道播放会话即可。
    func ensureAmbient() {
        guard mode == .none else { return }
        apply(.ambient)
    }

    /// TTS / 课文长音频开始:切 `.playback(.spokenAudio, .duckOthers)`。
    func beginSpokenAudio() {
        guard mode != .spokenAudio else { return }
        apply(.spokenAudio)
    }

    /// TTS / 课文长音频结束(自然播完 / stop / 被打断):恢复 `.ambient`。
    func endSpokenAudio() {
        guard mode == .spokenAudio else { return }
        apply(.ambient)
    }

    private func apply(_ newMode: Mode) {
        let session = AVAudioSession.sharedInstance()
        do {
            switch newMode {
            case .ambient:
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            case .spokenAudio:
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            case .none:
                return
            }
            try session.setActive(true)
            mode = newMode
        } catch {
            print("[AudioSessionCoordinator] switch failed: \(error)")
        }
    }
}

/// Single-track AVAudioPlayer wrapper with a small queue API.
///
/// Question audio comes in clusters: question stem → option N → explanation.
/// Most of the time we want them played sequentially without overlapping.
/// `AudioPlayer.play(paths:)` enqueues a list and plays them in order; calling
/// `play` again interrupts the current queue.
@MainActor
final class AudioPlayer: NSObject, ObservableObject {
    static let shared = AudioPlayer()

    @Published private(set) var isPlaying: Bool = false
    /// The audio file currently being played (local file name).
    @Published private(set) var nowPlayingPath: String?
    /// Index into the `paths` array handed to `play(paths:)` for the item
    /// currently playing (content-12). Entries that were nil / unresolved keep
    /// their slot, so a reader passing `sentences.map(\.audio)` can highlight
    /// sentence N directly — duplicate sentences no longer mis-highlight the
    /// way the old `lastPathComponent` reverse lookup did.
    @Published private(set) var nowPlayingIndex: Int?
    /// Incremented every time a queued run plays through to its natural end
    /// (`stop()` / interruptions do NOT count). Readers use this to detect
    /// "the whole passage finished" for the completion gate (content-5).
    @Published private(set) var queueCompletionCount: Int = 0
    /// 乌龟慢速开关（content-11）。开启后所有后续播放降到 `slowRate`。
    @Published var isSlowMode: Bool = false
    /// Monotonic id of the most recent `play(paths:)` run. Callers that need
    /// to attribute a completion to *their* run (e.g. the read-all gate)
    /// compare this against the value captured when they started playback.
    @Published private(set) var currentRunId: Int = 0

    /// 慢速倍率 —— 儿童跟读友好的 0.65×。
    static let slowRate: Float = 0.65

    private struct QueueItem {
        let url: URL
        let index: Int
    }

    private var player: AVAudioPlayer?
    private var queue: [QueueItem] = []
    /// How many files of the current run actually started playing.
    private var currentRunPlayedCount = 0
    /// The rate captured when the current run started.
    private var currentRunRate: Float = 1.0
    private var interruptionObserverRegistered = false

    /// Play one or more files in order. Empty / nil entries are skipped but
    /// keep their index slot (see `nowPlayingIndex`).
    /// Calling this interrupts any in-flight playback.
    /// `rate` overrides the global slow-mode toggle for this run only.
    /// (`settings` defaults to nil → SettingsStore.shared; a main-actor default
    /// value expression would trip Swift 6 isolation checking.)
    func play(paths: [String?], settings: SettingsStore? = nil, rate: Float? = nil) {
        if (settings ?? SettingsStore.shared).isMuted {
            stop(); return
        }
        let items: [QueueItem] = paths.enumerated().compactMap { idx, path in
            guard let path, let url = resolve(path) else { return nil }
            return QueueItem(url: url, index: idx)
        }
        registerInterruptionObserverIfNeeded()
        stop()
        // 长音频/朗读期间临时切 spokenAudio 播放会话,播完在 playNext()/stop()
        // 里恢复 ambient(critic-4)。注意顺序:先 stop()(它会 endSpokenAudio),
        // 再 begin,否则新一轮的会话会被上一轮的收尾还原掉。
        AudioSessionCoordinator.shared.beginSpokenAudio()
        currentRunId += 1
        queue = items
        currentRunRate = rate ?? (isSlowMode ? Self.slowRate : 1.0)
        playNext()
    }

    /// Convenience for a single file.
    func play(path: String?, settings: SettingsStore? = nil, rate: Float? = nil) {
        guard let path else { return }
        play(paths: [path], settings: settings, rate: rate)
    }

    func stop() {
        player?.stop()
        player = nil
        queue.removeAll()
        currentRunPlayedCount = 0
        isPlaying = false
        nowPlayingPath = nil
        nowPlayingIndex = nil
        // 中途打断也要把会话还给 SFX(critic-4)。
        AudioSessionCoordinator.shared.endSpokenAudio()
    }

    // MARK: - Path resolution

    /// Map a `Question.audio` style path (e.g. "/audio/8e/8ec5...opus") to
    /// the local m4a file installed by SeedInstaller / AssetDownloader.
    func resolve(_ path: String) -> URL? {
        // Drop optional leading slash, swap .opus → .m4a, drop "audio/" prefix
        // because we rebase against `sandboxAudioRoot` which already points at
        // `Application Support/cstf/audio/`.
        var rel = path
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.hasPrefix("audio/") { rel.removeFirst("audio/".count) }
        if rel.hasSuffix(".opus") { rel = String(rel.dropLast(".opus".count)) + ".m4a" }
        let url = DataLoader.shared.sandboxAudioRoot.appendingPathComponent(rel)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Internals

    /// 会话类别切换已收敛到 `AudioSessionCoordinator`(critic-4);
    /// 这里只负责注册一次打断监听。
    private func registerInterruptionObserverIfNeeded() {
        guard !interruptionObserverRegistered else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        interruptionObserverRegistered = true
    }

    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            stop()
        case .ended:
            // We don't auto-resume — the user can tap the speaker again.
            break
        @unknown default:
            break
        }
    }

    private func playNext() {
        guard !queue.isEmpty else {
            let finishedNaturally = currentRunPlayedCount > 0
            currentRunPlayedCount = 0
            isPlaying = false
            nowPlayingPath = nil
            nowPlayingIndex = nil
            if finishedNaturally { queueCompletionCount += 1 }
            // 整队自然播完:恢复 ambient,把会话还给 SFX(critic-4)。
            AudioSessionCoordinator.shared.endSpokenAudio()
            return
        }
        let next = queue.removeFirst()
        do {
            let p = try AVAudioPlayer(contentsOf: next.url)
            p.delegate = self
            p.enableRate = true
            p.rate = currentRunRate
            p.prepareToPlay()
            p.play()
            self.player = p
            self.isPlaying = true
            self.nowPlayingPath = next.url.lastPathComponent
            self.nowPlayingIndex = next.index
            self.currentRunPlayedCount += 1
        } catch {
            print("[AudioPlayer] play failed for \(next.url.lastPathComponent): \(error)")
            playNext()
        }
    }
}

extension AudioPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.playNext()
        }
    }
}
