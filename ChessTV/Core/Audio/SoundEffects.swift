import AVFoundation

enum SoundEffect: CaseIterable {
    case move, capture, castle, check, promote, gameStart, gameEnd, illegal, puzzleCorrect, puzzleWrong, lowTime
}

/// Procedurally generated sound effects played through a small pool of player nodes.
@MainActor
final class SoundEffects {
    static let shared = SoundEffects()

    var isEnabled = true

    private static let sampleRate = 44_100.0
    private static let voiceCount = 4

    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundEffects.sampleRate, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var isRunning = false

    private init() {
        for effect in SoundEffect.allCases {
            buffers[effect] = makeBuffer(for: effect)
        }
        for _ in 0..<Self.voiceCount {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        #if !os(macOS)
        try? AVAudioSession.sharedInstance().setCategory(.ambient)
        #endif
        startEngine()
    }

    func play(_ effect: SoundEffect) {
        guard isEnabled, let buffer = buffers[effect] else { return }
        if !engine.isRunning { startEngine() }
        guard isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        player.play()
    }

    private func startEngine() {
        do {
            #if !os(macOS)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            try engine.start()
            isRunning = true
        } catch {
            isRunning = false
        }
    }

    // MARK: - Synthesis

    private struct Partial {
        var frequency: Double
        var amplitude: Double
        var decay: Double  // exponential decay rate, 1/seconds
    }

    private func makeBuffer(for effect: SoundEffect) -> AVAudioPCMBuffer? {
        var samples: [Float]
        switch effect {
        case .move:
            samples = tock(pitch: 190)
        case .capture:
            samples = mix([(0, tock(pitch: 260, brightness: 1.6)), (0.07, tock(pitch: 200, brightness: 1.6))])
        case .castle:
            samples = mix([(0, tock(pitch: 190)), (0.14, tock(pitch: 230))])
        case .check:
            samples = mix([(0, tock(pitch: 190)), (0.05, tone([Partial(frequency: 1_046, amplitude: 0.5, decay: 9),
                                                              Partial(frequency: 2_093, amplitude: 0.2, decay: 12)],
                                                             duration: 0.35))])
        case .promote:
            samples = chime([659, 880, 1_319], spacing: 0.08)
        case .gameStart:
            samples = chime([523, 659, 784], spacing: 0.11)
        case .gameEnd:
            samples = chime([784, 659, 523], spacing: 0.14)
        case .illegal:
            samples = buzz(frequency: 110, duration: 0.16)
        case .puzzleCorrect:
            samples = chime([659, 988], spacing: 0.1)
        case .puzzleWrong:
            samples = buzz(frequency: 85, duration: 0.3)
        case .lowTime:
            samples = tone([Partial(frequency: 1_800, amplitude: 0.5, decay: 90)], duration: 0.06)
        }
        guard let peak = samples.map(abs).max(), peak > 0 else { return nil }
        let gain = min(1, 0.8 / peak)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        for i in samples.indices { channel[i] = samples[i] * gain }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }

    private func tone(_ partials: [Partial], duration: Double) -> [Float] {
        let count = Int(duration * Self.sampleRate)
        return (0..<count).map { i in
            let t = Double(i) / Self.sampleRate
            let attack = min(1, t / 0.002)
            var value = 0.0
            for p in partials {
                value += p.amplitude * exp(-p.decay * t) * sin(2 * .pi * p.frequency * t)
            }
            return Float(value * attack)
        }
    }

    /// Short wooden knock: a few inharmonic decaying partials plus a brief noise click.
    private func tock(pitch: Double, brightness: Double = 1) -> [Float] {
        var samples = tone([Partial(frequency: pitch, amplitude: 1.0, decay: 38),
                            Partial(frequency: pitch * 2.3, amplitude: 0.5, decay: 55),
                            Partial(frequency: pitch * 3.9, amplitude: 0.25 * brightness, decay: 80),
                            Partial(frequency: pitch * 6.1, amplitude: 0.12 * brightness, decay: 110)],
                           duration: 0.14)
        for i in 0..<min(samples.count, 200) {
            let noise = Float.random(in: -1...1) * Float(exp(-Double(i) / 30)) * Float(0.35 * brightness)
            samples[i] += noise
        }
        return samples
    }

    private func chime(_ frequencies: [Double], spacing: Double) -> [Float] {
        mix(frequencies.enumerated().map { index, f in
            (Double(index) * spacing, tone([Partial(frequency: f, amplitude: 0.6, decay: 6),
                                            Partial(frequency: f * 2, amplitude: 0.15, decay: 9)],
                                           duration: 0.6))
        })
    }

    private func buzz(frequency: Double, duration: Double) -> [Float] {
        let count = Int(duration * Self.sampleRate)
        return (0..<count).map { i in
            let t = Double(i) / Self.sampleRate
            let phase = (t * frequency).truncatingRemainder(dividingBy: 1)
            let square = phase < 0.5 ? 1.0 : -1.0
            let envelope = min(1, t / 0.005) * min(1, (duration - t) / 0.03)
            return Float(0.5 * (0.6 * square + 0.4 * sin(2 * .pi * frequency * 2 * t)) * envelope)
        }
    }

    private func mix(_ layers: [(offset: Double, samples: [Float])]) -> [Float] {
        let total = layers.map { Int($0.offset * Self.sampleRate) + $0.samples.count }.max() ?? 0
        var out = [Float](repeating: 0, count: total)
        for layer in layers {
            let start = Int(layer.offset * Self.sampleRate)
            for (i, s) in layer.samples.enumerated() { out[start + i] += s }
        }
        return out
    }
}
