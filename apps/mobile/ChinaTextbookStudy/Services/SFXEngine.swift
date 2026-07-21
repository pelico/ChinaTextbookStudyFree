import AVFoundation
import Foundation

/// Zero-dependency FM synthesis sound effects engine.
/// Direct port of `apps/web/src/lib/sfx.ts` using AVAudioEngine.
///
/// Architecture: AVAudioSourceNode (real-time sample generation) → mixer → output
/// Each `play()` call schedules a short-lived source node that auto-disconnects.
final class SFXEngine {
    static let shared = SFXEngine()

    enum Sound: String, CaseIterable {
        case correct, wrong, tap, complete, star, heartLoss, combo, unlock, progressTick
    }

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

    @MainActor
    func play(_ sound: Sound) {
        guard !SettingsStore.shared.isMuted else { return }
        ensureRunning()
        let events = buildEvents(for: sound)
        scheduleEvents(events)
    }

    // MARK: - Engine lifecycle

    private func ensureRunning() {
        guard !engine.isRunning else { return }
        do {
            // Configure session for playback alongside TTS.
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
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
        case sine, triangle
    }

    // MARK: - Sound definitions (ported from sfx.ts)

    private func buildEvents(for sound: Sound) -> [SynthEvent] {
        switch sound {
        case .correct:
            // Two FM bells (F#5 → A#5) + shimmer overtone
            return [
                SynthEvent(startTime: 0, duration: 0.42, frequency: 739.99,
                           volume: 0.30, modRatio: 3.01, modDepth: 180),
                SynthEvent(startTime: 0.11, duration: 0.55, frequency: 932.33,
                           volume: 0.34, modRatio: 3.01, modDepth: 200),
                SynthEvent(startTime: 0.11, duration: 0.35, frequency: 1864.66,
                           volume: 0.08, modRatio: 4.5, modDepth: 60),
            ]

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
            // Victory: C5-E5-G5-C6 arpeggio
            let notes: [(Double, Double)] = [(523.25, 0), (659.25, 0.12), (783.99, 0.24), (1046.5, 0.36)]
            return notes.map { freq, t in
                SynthEvent(startTime: t, duration: 0.6, frequency: freq,
                           volume: 0.28, modRatio: 3.01, modDepth: 160)
            } + [
                SynthEvent(startTime: 0.36, duration: 0.8, frequency: 2093,
                           volume: 0.14, modRatio: 4.2, modDepth: 80)
            ]

        case .star:
            // Two bright bells A6 → E7
            return [
                SynthEvent(startTime: 0, duration: 0.28, frequency: 1760,
                           volume: 0.28, modRatio: 3.5, modDepth: 100),
                SynthEvent(startTime: 0.08, duration: 0.32, frequency: 2637,
                           volume: 0.22, modRatio: 3.5, modDepth: 90),
            ]

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
        }
    }

    // MARK: - Real-time synthesis

    private func scheduleEvents(_ events: [SynthEvent]) {
        for event in events {
            let node = AVAudioSourceNode(format: format) { [sampleRate] _, _, frameCount, audioBufferList -> OSStatus in
                return noErr // Will be replaced per-event below
            }

            // Each event gets its own source node with a render callback.
            var phase: Double = 0
            var modPhase: Double = 0
            var sampleIndex: Int = 0
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
