import Foundation

/// `sound-packs.json` entry: sound effects described as synthesis recipes.
///
/// Each effect is a mix of layers. A layer's sample at time `t` (seconds from the
/// layer's offset) is the sum of its partials, each `amplitude * exp(-decay * t) * wave`,
/// plus the optional noise burst, times the envelope
/// `min(1, t / attack) * min(1, (duration - t) / release)` (a zero release is skipped).
/// The mixed effect is scaled so its peak is at most `peakLevel`.
public struct SoundPack: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let nameKey: String
    public let attributionID: String
    public let sampleRate: Double
    /// Effects that can play at once.
    public let voiceCount: Int
    public let peakLevel: Double
    public let effects: [SoundEffectID: SoundEffectSpec]
}

/// Moments that play a sound.
public enum SoundEffectID: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case move, capture, castle, check, promote, gameStart, gameEnd, illegal, puzzleCorrect, puzzleWrong, lowTime
}

public struct SoundEffectSpec: Codable, Hashable, Sendable {
    public let layers: [SoundLayer]
}

public struct SoundLayer: Codable, Hashable, Sendable {
    /// Start time within the effect, in seconds.
    public let offset: Double
    public let duration: Double
    public let attack: Double
    public let release: Double
    public let partials: [SoundPartial]
    public let noise: SoundNoise?
}

public struct SoundPartial: Codable, Hashable, Sendable {
    public enum Waveform: String, Codable, Sendable {
        case sine, square
    }

    public let waveform: Waveform
    public let frequency: Double
    public let amplitude: Double
    /// Exponential decay rate, per second.
    public let decay: Double
}

/// A uniform white-noise click at the start of a layer.
public struct SoundNoise: Codable, Hashable, Sendable {
    public let amplitude: Double
    public let duration: Double
    /// Exponential decay rate, per second.
    public let decay: Double
}
