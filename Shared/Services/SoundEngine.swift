import AVFoundation

/// Noise generator state, read on the audio render thread.
private final class NoiseSource: @unchecked Sendable {
    var kind: Ambient = .off
    var targetGain: Float = 0
    private var gain: Float = 0
    private var seed: UInt32 = 0x9E37_79B9
    private var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0
    private var brown: Float = 0

    private func random() -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        return Float(seed) / Float(UInt32.max) * 2 - 1
    }

    func sample() -> Float {
        gain += (targetGain - gain) * 0.0004 // ~50 ms glide, no clicks
        guard gain > 0.0001 else { return 0 }
        let white = random()
        let value: Float
        switch kind {
        case .off:
            value = 0
        case .white:
            value = white * 0.25
        case .pink: // Paul Kellet's filter
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            value = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362) * 0.08
            b6 = white * 0.115926
        case .brown:
            brown = (brown + 0.02 * white) / 1.02
            value = brown * 2.2
        }
        return value * gain
    }
}

/// Every sound is synthesized, so the app ships with no audio files.
@MainActor
final class SoundEngine {
    static let shared = SoundEngine()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let noise = NoiseSource()
    private let noiseNode: AVAudioSourceNode
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var buffers: [Chime: AVAudioPCMBuffer] = [:]
    private var tickBuffer: AVAudioPCMBuffer?
    private var ambientPlaying = false
    private var stopTask: Task<Void, Never>?

    private init() {
        noiseNode = Self.makeNoiseNode(noise, format: format)
        engine.attach(player)
        engine.attach(noiseNode)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        engine.connect(noiseNode, to: engine.mainMixerNode, format: format)
    }

    private nonisolated static func makeNoiseNode(_ noise: NoiseSource, format: AVAudioFormat) -> AVAudioSourceNode {
        AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let s = noise.sample()
                for buffer in buffers {
                    buffer.mData?.assumingMemoryBound(to: Float.self)[frame] = s
                }
            }
            return noErr
        }
    }

    // MARK: Public

    func play(_ chime: Chime, volume: Double) {
        guard Preferences.shared.soundEnabled, chime != .none, let buffer = buffer(for: chime) else { return }
        guard ensureRunning() else { return }
        player.volume = Float(volume)
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        scheduleStopIfIdle(after: 6)
    }

    /// Four seconds of ticking, so you can hear what it sounds like.
    func previewTicks() {
        Task { @MainActor in
            for _ in 0..<4 {
                tick()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func tick() {
        guard Preferences.shared.soundEnabled else { return }
        if tickBuffer == nil {
            tickBuffer = Self.synthesize(duration: 0.04, format: format) { t, noise in
                noise * exp(-t * 260) * 0.35
            }
        }
        guard let tickBuffer, ensureRunning() else { return }
        player.volume = 0.6
        player.scheduleBuffer(tickBuffer)
        scheduleStopIfIdle(after: 3)
    }

    func syncAmbient(playing: Bool) {
        let prefs = Preferences.shared
        let shouldPlay = playing && prefs.soundEnabled && prefs.ambient != .off
        noise.kind = prefs.ambient
        noise.targetGain = shouldPlay ? Float(prefs.ambientVolume) : 0
        ambientPlaying = shouldPlay
        if shouldPlay {
            stopTask?.cancel()
            _ = ensureRunning()
        } else {
            scheduleStopIfIdle(after: 1)
        }
    }

    /// Short preview while choosing a sound in Settings.
    func preview(_ ambient: Ambient, volume: Double) {
        guard ambient != .off else { syncAmbient(playing: false); return }
        noise.kind = ambient
        noise.targetGain = Float(volume)
        _ = ensureRunning()
        scheduleStopIfIdle(after: 4, fadeAmbient: true)
    }

    // MARK: Engine lifecycle

    private func ensureRunning() -> Bool {
        stopTask?.cancel()
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
        if !engine.isRunning {
            do { try engine.start() } catch { return false }
        }
        if !player.isPlaying { player.play() }
        return true
    }

    private func scheduleStopIfIdle(after seconds: Double, fadeAmbient: Bool = false) {
        stopTask?.cancel()
        stopTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            if fadeAmbient && !self.ambientPlaying { self.noise.targetGain = 0 }
            guard !self.ambientPlaying else { return }
            try? await Task.sleep(for: .seconds(0.3))
            guard !Task.isCancelled, !self.ambientPlaying else { return }
            self.player.stop()
            self.engine.stop()
        }
    }

    // MARK: Synthesis

    private func buffer(for chime: Chime) -> AVAudioPCMBuffer? {
        if let cached = buffers[chime] { return cached }
        let made: AVAudioPCMBuffer?
        switch chime {
        case .bell:
            // Two soft bell strikes, a fifth apart.
            made = Self.synthesize(duration: 2.6, format: format) { t, _ in
                func strike(_ f: Double, _ t: Double) -> Double {
                    guard t >= 0 else { return 0 }
                    let env = exp(-t * 3.2) * min(1, t * 400)
                    return env * (sin(2 * .pi * f * t) + 0.35 * sin(2 * .pi * f * 2.01 * t) + 0.12 * sin(2 * .pi * f * 3.02 * t))
                }
                return 0.3 * (strike(880, t) + strike(1318.5, t - 0.22))
            }
        case .bowl:
            made = Self.synthesize(duration: 5, format: format) { t, _ in
                let env = exp(-t * 0.9) * min(1, t * 60)
                let f = 220.0
                let tone = sin(2 * .pi * f * t) + sin(2 * .pi * (f + 1.3) * t)
                    + 0.5 * sin(2 * .pi * f * 2.71 * t) + 0.25 * sin(2 * .pi * f * 5.15 * t)
                return 0.16 * env * tone
            }
        case .wood:
            made = Self.synthesize(duration: 0.9, format: format) { t, noise in
                func knock(_ t: Double) -> Double {
                    guard t >= 0 else { return 0 }
                    return exp(-t * 38) * (sin(2 * .pi * 1050 * t) + 0.5 * sin(2 * .pi * 2210 * t)) + noise * exp(-t * 400) * 0.3
                }
                return 0.45 * (knock(t) + 0.8 * knock(t - 0.16) + 0.6 * knock(t - 0.32))
            }
        case .none:
            made = nil
        }
        buffers[chime] = made
        return made
    }

    private static func synthesize(duration: Double, format: AVAudioFormat,
                                   _ sample: (_ t: Double, _ noise: Double) -> Double) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let frames = AVAudioFrameCount(duration * rate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let data = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames
        var seed: UInt32 = 12345
        for i in 0..<Int(frames) {
            seed = seed &* 1_664_525 &+ 1_013_904_223
            let noise = Double(seed) / Double(UInt32.max) * 2 - 1
            let t = Double(i) / rate
            // Fade the last 30 ms so nothing clicks.
            let tail = min(1, (duration - t) / 0.03)
            data[i] = Float(sample(t, noise) * tail)
        }
        return buffer
    }
}
