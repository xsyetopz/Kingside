import ChessContent
// Foundation provides the C math functions `exp` and `sin`; unused_import does not attribute them.
// swiftlint:disable:next unused_import
import Foundation

/// Renders the synthesis recipes of a `SoundPack` into mono PCM samples.
///
/// The formula is the one documented on `SoundPack`. Noise comes from a generator seeded by the
/// effect id, so the same recipe always renders the same samples.
enum SoundPackRenderer {
  /// The samples of `effect` at `pack.sampleRate`; empty when the pack has no such effect.
  static func samples(for effect: SoundEffectID, in pack: SoundPack) -> [Float] {
    guard let spec = pack.effects[effect] else { return [] }
    return render(
      spec,
      sampleRate: pack.sampleRate,
      peakLevel: pack.peakLevel,
      seed: seed(for: effect)
    )
  }

  /// Mixes the layers of `spec`, then scales the mix so its peak is at most `peakLevel`.
  static func render(
    _ spec: SoundEffectSpec,
    sampleRate: Double,
    peakLevel: Double,
    seed: UInt64
  ) -> [Float] {
    let extent = spec.layers.map { $0.offset + $0.duration }.max() ?? 0
    let count = frameIndex(extent, sampleRate)
    var mix = [Double](repeating: 0, count: count)
    var generator = SplitMix64(seed: seed)
    for layer in spec.layers {
      let start = frameIndex(layer.offset, sampleRate)
      let end = min(count, frameIndex(layer.offset + layer.duration, sampleRate))
      guard start < end else { continue }
      for frame in start..<end {
        let t = Double(frame - start) / sampleRate
        mix[frame] += sample(of: layer, at: t, noise: &generator)
      }
    }
    let peak = mix.lazy.map(abs).max() ?? 0
    let gain = peak > 0 ? min(1, peakLevel / peak) : 0
    return mix.map { Float($0 * gain) }
  }

  /// One layer's value at `t` seconds from its offset.
  private static func sample(of layer: SoundLayer, at t: Double, noise: inout SplitMix64) -> Double
  {
    var value = 0.0
    for partial in layer.partials {
      value +=
        partial.amplitude * exp(-partial.decay * t) * wave(partial.waveform, partial.frequency, t)
    }
    if let burst = layer.noise, t < burst.duration {
      value += burst.amplitude * exp(-burst.decay * t) * noise.nextUniform()
    }
    let attack = layer.attack > 0 ? min(1, t / layer.attack) : 1
    let release = layer.release > 0 ? min(1, (layer.duration - t) / layer.release) : 1
    return value * attack * release
  }

  private static func wave(
    _ waveform: SoundPartial.Waveform,
    _ frequency: Double,
    _ t: Double
  ) -> Double {
    switch waveform {
    case .sine: sin(2 * .pi * frequency * t)
    case .square: (frequency * t).truncatingRemainder(dividingBy: 1) < 0.5 ? 1 : -1
    }
  }

  private static func frameIndex(_ seconds: Double, _ sampleRate: Double) -> Int {
    Int((seconds * sampleRate).rounded())
  }

  /// FNV-1a of the effect id, so the seed is stable across launches (unlike `hashValue`).
  static func seed(for effect: SoundEffectID) -> UInt64 {
    effect.rawValue.utf8.reduce(0xcbf2_9ce4_8422_2325) {
      ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3
    }
  }
}

/// A small seeded generator (SplitMix64) for reproducible noise.
struct SplitMix64: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9e37_79b9_7f4a_7c15
    var z = state
    z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
    z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
    return z ^ (z >> 31)
  }

  /// A uniform value in -1...1.
  mutating func nextUniform() -> Double { Double.random(in: -1...1, using: &self) }
}
