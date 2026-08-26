import Foundation
import AVFoundation
import Combine

/// 统一音频会话协调器(critic-4)。
///
/// App 里有三类声音,对会话的诉求互相冲突:
/// 1. **SFX / 判分短音** —— 走 `.ambient`:尊重静音拨片、与用户自己的音乐混音;
/// 2. **TTS / 课文长音频** —— 播放期间临时切 `.playback(.spokenAudio, .duckOthers)`
///    (静音拨片下朗读也要能听到,并把背景音乐压低),播完立刻恢复 ambient;
/// 3. **跟读录音** —— 需要 `.playAndRecord`,否则 `AVAudioRecorder.record()`
///    直接返回 false、连文件都不生成(iosretention-1)。
///
/// 此前 `SFXEngine` / `AudioPlayer` / `FollowupSession` 各自 `setCategory` 互相
/// 打架 —— 谁后启动谁说了算。现在**所有**类别切换只有这一个出口:任何地方直接
/// 调 `AVAudioSession.setCategory` 都会让 `mode` 与真实会话漂移,是 bug。
@MainActor
final class AudioSessionCoordinator {
    static let shared = AudioSessionCoordinator()

    private enum Mode { case none, ambient, spokenAudio, record }
    private var mode: Mode = .none

    private init() {}

    /// SFX 播放前调用:保证会话至少处于 `.ambient`。
    ///
    /// 朗读(.spokenAudio)/ 录音(.record)进行中不降级 —— 短音效借道当前会话即可,
    /// 尤其录音期间切走类别会让下一次 `record()` 静默失败。
    ///
    /// 其余情况**校验真实会话**再决定是否重新 apply:历史上有代码绕过协调器直接
    /// `setCategory(.playback)`,`mode` 停在 `.ambient` 而系统会话是 `.playback`,
    /// 旧的 `guard mode == .none` 让协调器永远回不到 ambient,静音拨片对音效彻底
    /// 失效(iosretention-2)。这里比对一次 `session.category` 就能自愈。
    func ensureAmbient() {
        guard mode != .spokenAudio, mode != .record else { return }
        if mode == .ambient, AVAudioSession.sharedInstance().category == .ambient { return }
        apply(.ambient)
    }

    /// TTS / 课文长音频开始:切 `.playback(.spokenAudio, .duckOthers)`。
    /// 录音会话进行中不抢类别 —— `.playAndRecord` 同样能播放,而切走会让紧接着
    /// 的 `AVAudioRecorder.record()` 失败(跟读「听原音 → 录音」交替进行)。
    func beginSpokenAudio() {
        guard mode != .spokenAudio, mode != .record else { return }
        apply(.spokenAudio)
    }

    /// TTS / 课文长音频结束(自然播完 / stop / 被打断):恢复 `.ambient`。
    /// 录音会话进行中是 no-op(`mode != .spokenAudio`)。
    func endSpokenAudio() {
        guard mode == .spokenAudio else { return }
        apply(.ambient)
    }

    /// 跟读录音开始:切 `.playAndRecord`。返回 false 表示会话没能切过去,
    /// 调用方必须放弃录音并给用户可见提示,不要硬着头皮 `record()`。
    /// 幂等 —— 已经在录音会话里直接返回 true。
    @discardableResult
    func beginRecording() -> Bool {
        if mode == .record { return true }
        return apply(.record)
    }

    /// 跟读录音结束(整轮走完 / 中止 / 失败):恢复 `.ambient`,把静音拨片还给用户。
    func endRecording() {
        guard mode == .record else { return }
        apply(.ambient)
    }

    @discardableResult
    private func apply(_ newMode: Mode) -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            switch newMode {
            case .ambient:
                try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            case .spokenAudio:
                try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            case .record:
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
            case .none:
                return false
            }
            try session.setActive(true)
            mode = newMode
            return true
        } catch {
            print("[AudioSessionCoordinator] switch failed: \(error)")
            return false
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

    /// 这批路径里**至少有一条**能落到本地文件吗?
    ///
    /// 音频包没下载(或被 SeedInstaller 整体清掉)时,`play(paths:)` 会得到空队列 ——
    /// `isPlaying` 恒 false、`queueCompletionCount` 不动,依赖「整队自然播完」的
    /// 完成门槛就永远解不开(iosretention-6)。UI 需要提前知道这件事,才能把
    /// 「朗读全文」置灰并给一条不依赖音频的出路。
    /// 命中第一条就返回,常见情况只做一次 `fileExists`。
    func hasAnyResolvable(_ paths: [String?]) -> Bool {
        paths.contains { path in
            guard let path else { return false }
            return resolve(path) != nil
        }
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
