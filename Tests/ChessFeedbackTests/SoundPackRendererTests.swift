import ChessContent
import Testing

@testable import ChessFeedback

@Suite
struct SoundPackRendererTests {
  private static let pack: SoundPack = {
    let catalog = try! ContentCatalog.load()
    return catalog.soundPack(id: catalog.defaults.soundPackID)!
  }()

  @Test
  func rendersTheSameSamplesEveryTime() {
    let first = SoundPackRenderer.samples(for: .capture, in: Self.pack)
    let second = SoundPackRenderer.samples(for: .capture, in: Self.pack)
    #expect(!first.isEmpty)
    #expect(first == second)
  }

  @Test(arguments: SoundEffectID.allCases)
  func rendersEveryShippedEffect(effect: SoundEffectID) throws {
    let pack = Self.pack
    let spec = try #require(pack.effects[effect])
    let samples = SoundPackRenderer.samples(for: effect, in: pack)

    // The length is the layers' extent at the pack's sample rate.
    let extent = spec.layers.map { $0.offset + $0.duration }.max() ?? 0
    #expect(samples.count == Int((extent * pack.sampleRate).rounded()))

    // The peak is at most the pack's level, and the effect is not silent.
    let peak = samples.map(abs).max() ?? 0
    #expect(peak <= Float(pack.peakLevel))
    #expect(peak > 0.1, "\(effect) is silent")

    // Every layer here has an attack, so the first sample is 0 and the start rises from near 0.
    #expect(samples[0] == 0)
    #expect(abs(samples[1]) < 0.1 * peak)
  }

  @Test
  func noiseDependsOnTheEffectSeed() throws {
    let spec = try #require(Self.pack.effects[.move])
    let a = SoundPackRenderer.render(spec, sampleRate: 44_100, peakLevel: 1, seed: 1)
    let b = SoundPackRenderer.render(spec, sampleRate: 44_100, peakLevel: 1, seed: 2)
    #expect(a != b)
    #expect(SoundPackRenderer.seed(for: .move) != SoundPackRenderer.seed(for: .capture))
  }
}
