import AVFAudio
import ChessContent
import Testing

@testable import ChessFeedback

@MainActor
@Suite
struct AudioFeedbackTests {
  /// True when the host has an audio output; CI machines often have none.
  nonisolated static var hasOutputDevice: Bool {
    // The output node needs its engine alive; a temporary engine crashes in AVFAudio.
    let engine = AVAudioEngine()
    return withExtendedLifetime(engine) {
      engine.outputNode.outputFormat(forBus: 0).channelCount > 0
    }
  }

  private func pack() throws -> SoundPack {
    let catalog = try ContentCatalog.load()
    return try #require(catalog.soundPack(id: catalog.defaults.soundPackID))
  }

  @Test
  func playsAnEffectOrStaysSilentWithoutADevice() throws {
    let audio = AudioFeedback(pack: try pack())
    audio.play(.move)
    audio.isEnabled = false
    audio.play(.capture)
  }

  @Test(.enabled(if: hasOutputDevice, "the host has no audio output device"))
  func startsTheEngineAndPlays() throws {
    let audio = AudioFeedback(pack: try pack(), volume: 0)
    audio.play(.move)
    #expect(audio.isRunning)
  }
}
