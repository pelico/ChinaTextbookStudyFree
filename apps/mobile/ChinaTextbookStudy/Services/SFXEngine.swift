import AVFoundation
import Foundation

/// Zero-dependency FM synthesis sound effects engine.
/// Direct port of `apps/web/src/lib/sfx.ts` using AVAudioEngine.
///
/// Architecture: AVAudioSourceNode (real-time sample generation) → mixer → output
/// Each `play()` call schedules a short-lived source node that auto-disconnects.
///
/// Wave F additions:
/// - `play(_:pitchStep:)` — 连对升调(ios-lesson-12):每级约 +1 半音,封顶 8 级;
/// - 新事件 `.pairMatch` / `.purchase` / `.questClaim` / `.chestOpen`(ios-feel-10/12);
/// - correct / complete / star 增厚:白噪 click 瞬态 + 轻微 detune 双振荡器(ios-feel-11);
/// - 音频会话统一交给 `AudioSessionCoordinator`(critic-4),SFX 走 `.ambient`。
final class SFXEngine {
    static let shared = SFXEngine()

    /// 跨分区约定的事件名(Wave F):其他分区按 `play(_ sfx: SFX, pitchStep:)` 调用。
    enum SFX: String, CaseIterable {
        case correct, wrong, tap, complete, star, heartLoss, combo, unlock, progressTick
        // Wave F(ios-feel-10/12)
        case pairMatch      // 配对成功:上行双音(支持 pitchStep 连对升调)
        case purchase       // 商店购买:收银双音
        case questClaim     // 任务领奖:短双音
        case chestOpen      // 开宝箱:上行琶音 + shimmer
    }

    /// 兼容旧名 —— 早期代码以 `Sound` 引用该枚举。
    typealias Sound = SFX

    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private let sampleRate: Double = 44100
    private let format: AVAudioFormat

    private init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        engine.attach(mixer)
        mixer.outputVolume = 0.55
        engine.connect(mixer, to: engine.mainMixerNode, format: format)
    }

    /// 播放一个音效。
    ///
    /// `pitchStep`(ios-lesson-12):整组事件的频率乘 `2^(min(step, 8)/12)`,
    /// 即每级抬高约 1 个半音、封顶 8 级 —— 连对越长音越亮,和多邻国一致。
    /// 主要供 `.correct` / `.pairMatch` 使用,其他事件传 0(默认值)即可。
    @MainActor
    func play(_ sfx: SFX, pitchStep: Int = 0) {
        guard !SettingsStore.shared.isMuted else { return }
        ensureRunning()
        var events = buildEvents(for: sfx)
        let step = max(0, min(pitchStep, 8))
        if step > 0 {
            let ratio = pow(2.0, Double(step) / 12.0)
            for i in events.indices {
                events[i].frequency *= ratio
                if let end = events[i].endFrequency {
                    events[i].endFrequency = end * ratio
                }
            }
        }
        scheduleEvents(events)
    }

    // MARK: - Engine lifecycle

    @MainActor
    private func ensureRunning() {
        // 会话类别统一交给协调器(critic-4):SFX 走 .ambient,
        // 尊重静音拨片、与用户音乐混音;不再自己 setCategory。
        AudioSessionCoordinator.shared.ensureAmbient()
        guard !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            print("[SFXEngine] start failed: \(error)")
        }
    }

    // MARK: - Event model

    /// A single synthesis event (one oscillator burst).
    private struct SynthEvent {
        var startTime: Double = 0        // seconds from "now"
        var duration: Double = 0.3
        var frequency: Double = 440
        var endFrequency: Double?         // for glide
        var volume: Float = 0.25
        var attack: Double = 0.004
        var waveform: Waveform = .sine
        var modRatio: Double?             // FM: modulator freq = freq * modRatio
        var modDepth: Double?             // FM: modulation amplitude (Hz)
    }

    private enum Waveform {
        case sine, triangle, noise
    }

    // MARK: - Thickening helpers (ios-feel-11)

    /// 3–8ms 白噪 click 瞬态:给关键音一个「敲击感」的起振,类似打击乐的 attack。
    private func click(at start: Double = 0, volume: Float = 0.11) -> SynthEvent {
        SynthEvent(startTime: start, duration: 0.005, frequency: 1000,
                   volume: volume, attack: 0.0004, waveform: .noise)
    }

    /// 轻微 detune 双振荡器:把整组事件抬高几音分、压低音量后叠回原事件,
    /// 两组振荡器间的缓慢拍频让音色更「厚」—— 纯代码,无音频资源。
    private func detuned(_ events: [SynthEvent], cents: Double = 7, gain: Float = 0.32) -> [SynthEvent] {
        let ratio = pow(2.0, cents / 1200.0)
        return events.map { e in
            var d = e
            d.frequency *= ratio
            if let end = d.endFrequency { d.endFrequency = end * ratio }
            d.volume *= gain
            return d
        }
    }

    // MARK: - Sound definitions (ported from sfx.ts)

    private func buildEvents(for sound: SFX) -> [SynthEvent] {
        switch sound {
        case .correct:
            // Two FM bells (F#5 → A#5) + shimmer overtone,
            // 增厚:白噪 click + detune 副本(ios-feel-11)。
            let bells = [
                SynthEvent(startTime: 0, duration: 0.42, frequency: 739.99,
                           volume: 0.30, modRatio: 3.01, modDepth: 180),
                SynthEvent(startTime: 0.11, duration: 0.55, frequency: 932.33,
                           volume: 0.34, modRatio: 3.01, modDepth: 200),
                SynthEvent(startTime: 0.11, duration: 0.35, frequency: 1864.66,
                           volume: 0.08, modRatio: 4.5, modDepth: 60),
            ]
            return bells + detuned(bells) + [click(volume: 0.12)]

        case .wrong:
            // Gentle descending E4→D4 triangle + low sine pad
            return [
                SynthEvent(startTime: 0, duration: 0.32, frequency: 329.63,
                           endFrequency: 277.18, volume: 0.26, attack: 0.008,
                           waveform: .triangle),
                SynthEvent(startTime: 0, duration: 0.34, frequency: 164.81,
                           endFrequency: 138.59, volume: 0.18, attack: 0.01),
            ]

        case .tap:
            // Short high sine pop
            return [
                SynthEvent(startTime: 0, duration: 0.04, frequency: 2400,
                           volume: 0.10, attack: 0.0005),
            ]

        case .complete:
            // Victory: C5-E5-G5-C6 arpeggio,增厚同 correct(ios-feel-11)。
            let notes: [(Double, Double)] = [(523.25, 0), (659.25, 0.12), (783.99, 0.24), (1046.5, 0.36)]
            let arp = notes.map { freq, t in
                SynthEvent(startTime: t, duration: 0.6, frequency: freq,
                           volume: 0.28, modRatio: 3.01, modDepth: 160)
            }
            let shimmer = [
                SynthEvent(startTime: 0.36, duration: 0.8, frequency: 2093,
                           volume: 0.14, modRatio: 4.2, modDepth: 80)
            ]
            return arp + detuned(arp, gain: 0.28) + shimmer + [click(volume: 0.10)]

        case .star:
            // Two bright bells A6 → E7,增厚(ios-feel-11)。
            let bells = [
                SynthEvent(startTime: 0, duration: 0.28, frequency: 1760,
                           volume: 0.28, modRatio: 3.5, modDepth: 100),
                SynthEvent(startTime: 0.08, duration: 0.32, frequency: 2637,
                           volume: 0.22, modRatio: 3.5, modDepth: 90),
            ]
            return bells + detuned(bells, cents: 6, gain: 0.30) + [click(volume: 0.09)]

        case .heartLoss:
            // Descending bell + triangle glide
            return [
                SynthEvent(startTime: 0, duration: 0.35, frequency: 523.25,
                           volume: 0.24, modRatio: 2.8, modDepth: 140),
                SynthEvent(startTime: 0.05, duration: 0.38, frequency: 440,
                           endFrequency: 220, volume: 0.18, attack: 0.005,
                           waveform: .triangle),
            ]

        case .combo:
            // C5-E5-G5 arpeggio
            let notes = [523.25, 659.25, 783.99]
            return notes.enumerated().map { i, f in
                SynthEvent(startTime: Double(i) * 0.07, duration: 0.34, frequency: f,
                           volume: 0.26, modRatio: 3.01, modDepth: 150)
            }

        case .unlock:
            // Rich C6 harmonics
            let fundamental = 1046.5
            return [1.0, 2.0, 3.01].enumerated().map { i, mult in
                SynthEvent(startTime: Double(i) * 0.02, duration: 0.9,
                           frequency: fundamental * mult,
                           volume: Float(0.22 / Double(i + 1)),
                           modRatio: 3.5, modDepth: 120)
            } + [
                SynthEvent(startTime: 0.06, duration: 1.0, frequency: 523.25,
                           volume: 0.10, modRatio: 2.01, modDepth: 80)
            ]

        case .progressTick:
            // Very short ding
            return [
                SynthEvent(startTime: 0, duration: 0.08, frequency: 1760,
                           volume: 0.12, modRatio: 3.01, modDepth: 60),
            ]

        case .pairMatch:
            // 配对成功(ios-feel-10):E5→A5 上行双音,比 correct 轻快短促,
            // 供连连看 / 配对题连击时叠 pitchStep 升调。
            return [
                SynthEvent(startTime: 0, duration: 0.20, frequency: 659.25,
                           volume: 0.22, modRatio: 3.01, modDepth: 110),
                SynthEvent(startTime: 0.07, duration: 0.30, frequency: 880.0,
                           volume: 0.26, modRatio: 3.01, modDepth: 130),
            ]

        case .purchase:
            // 商店购买(ios-feel-12):收银「叮-叮」双音,B5→E6,
            // 开头一点白噪 click,像硬币落进存钱罐。
            return [
                click(volume: 0.10),
                SynthEvent(startTime: 0, duration: 0.18, frequency: 987.77,
                           volume: 0.24, modRatio: 4.0, modDepth: 90),
                SynthEvent(startTime: 0.09, duration: 0.34, frequency: 1318.51,
                           volume: 0.26, modRatio: 4.0, modDepth: 110),
            ]

        case .questClaim:
            // 任务领奖(ios-feel-12):G5→C6 短双音 —— 比 complete 轻,
            // 天天听也不腻。
            return [
                SynthEvent(startTime: 0, duration: 0.20, frequency: 783.99,
                           volume: 0.26, modRatio: 3.01, modDepth: 140),
                SynthEvent(startTime: 0.08, duration: 0.32, frequency: 1046.5,
                           volume: 0.28, modRatio: 3.01, modDepth: 150),
            ]

        case .chestOpen:
            // 开宝箱(ios-feel-12):C5-E5-G5-C6 快速上行琶音 + 双层高频 shimmer。
            let notes: [(Double, Double)] = [(523.25, 0), (659.25, 0.08), (783.99, 0.16), (1046.5, 0.24)]
            let arp = notes.map { freq, t in
                SynthEvent(startTime: t, duration: 0.5, frequency: freq,
                           volume: 0.26, modRatio: 3.01, modDepth: 150)
            }
            let shimmer = [
                SynthEvent(startTime: 0.24, duration: 0.7, frequency: 2093,
                           volume: 0.12, modRatio: 4.5, modDepth: 70),
                SynthEvent(startTime: 0.32, duration: 0.6, frequency: 3135.96,
                           volume: 0.07, modRatio: 5.0, modDepth: 50),
            ]
            return arp + shimmer
        }
    }

    // MARK: - Real-time synthesis

    private func scheduleEvents(_ events: [SynthEvent]) {
        for event in events {
            // Each event gets its own source node with a render callback.
            var phase: Double = 0
            var modPhase: Double = 0
            var sampleIndex: Int = 0
            // 白噪声用 xorshift32 —— 渲染线程上零分配、零锁。
            var noiseState: UInt32 = 0x9E3779B9
            let sr = sampleRate
            let totalSamples = Int(event.duration * sr)
            let attackSamples = Int(event.attack * sr)
            let startSample = Int(event.startTime * sr)

            let sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList -> OSStatus in
                let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
                let frames = Int(frameCount)

                for frame in 0..<frames {
                    let currentSample = sampleIndex + frame
                    let activeSample = currentSample - startSample

                    guard activeSample >= 0, activeSample < totalSamples else {
                        ablPointer[0].mData?.assumingMemoryBound(to: Float.self)[frame] = 0
                        if activeSample >= totalSamples {
                            // Signal done — will be cleaned up after buffer completes
                        }
                        continue
                    }

                    let t = Double(activeSample) / sr
                    let progress = t / event.duration

                    // Frequency (with optional glide)
                    let freq: Double
                    if let endFreq = event.endFrequency {
                        freq = event.frequency * pow(endFreq / event.frequency, progress)
                    } else {
                        freq = event.frequency
                    }

                    // Amplitude envelope: attack → sustain → exponential decay
                    let env: Float
                    if activeSample < attackSamples {
                        env = event.volume * Float(activeSample) / Float(max(1, attackSamples))
                    } else {
                        // Exponential decay from peak to near-zero
                        let decayProgress = (t - event.attack) / (event.duration - event.attack)
                        env = event.volume * Float(exp(-4.0 * decayProgress))
                    }

                    // Generate sample
                    var sample: Float
                    if let modRatio = event.modRatio, let modDepth = event.modDepth {
                        // FM synthesis: carrier + modulator
                        let modFreq = freq * modRatio
                        let modEnv = modDepth * exp(-3.0 * progress) // Modulation decays faster
                        let modSignal = sin(modPhase * 2.0 * .pi)
                        let carrierFreq = freq + modEnv * modSignal
                        sample = env * Float(sin(phase * 2.0 * .pi))

                        phase += carrierFreq / sr
                        modPhase += modFreq / sr
                    } else {
                        // Simple oscillator
                        switch event.waveform {
                        case .sine:
                            sample = env * Float(sin(phase * 2.0 * .pi))
                        case .triangle:
                            let p = phase.truncatingRemainder(dividingBy: 1.0)
                            sample = env * Float(2.0 * abs(2.0 * p - 1.0) - 1.0)
                        case .noise:
                            // White-noise click transient (ios-feel-11)
                            noiseState ^= noiseState << 13
                            noiseState ^= noiseState >> 17
                            noiseState ^= noiseState << 5
                            sample = env * (Float(noiseState) / Float(UInt32.max) * 2.0 - 1.0)
                        }
                        phase += freq / sr
                    }

                    ablPointer[0].mData?.assumingMemoryBound(to: Float.self)[frame] = sample
                }

                sampleIndex += frames
                return noErr
            }

            engine.attach(sourceNode)
            engine.connect(sourceNode, to: mixer, format: format)

            // Auto-detach after the event finishes.
            let cleanupDelay = event.startTime + event.duration + 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + cleanupDelay) { [weak self] in
                guard let self else { return }
                self.engine.disconnectNodeOutput(sourceNode)
                self.engine.detach(sourceNode)
            }
        }
    }
}
