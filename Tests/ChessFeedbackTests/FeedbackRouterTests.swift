import ChessContent
import ChessPlay
import Foundation
import Testing

@testable import ChessFeedback

@MainActor
private final class RecordingOutput: SoundOutput, HapticOutput {
  var sounds: [SoundEffectID] = []
  var haptics: [HapticEventID] = []
  func play(_ effect: SoundEffectID) { sounds.append(effect) }
  func play(_ haptic: HapticEventID) { haptics.append(haptic) }
}

@MainActor
@Suite
struct FeedbackRouterTests {
  @Test(arguments: [
    (FeedbackEvent.gameStarted, SoundEffectID.gameStart, HapticEventID?.none),
    (.moved(.move), .move, .move),
    (.moved(.capture), .capture, .capture),
    (.moved(.castle), .castle, .move),
    (.moved(.check), .check, .check),
    (.moved(.promote), .promote, .move),
    (.illegalMove, .illegal, .illegalMove),
    (.gameOver(.whiteWon), .gameEnd, .gameOver),
    (.gameOver(.draw), .gameEnd, .gameOver),
    (.lowTime, .lowTime, nil),
    (.puzzleCorrect, .puzzleCorrect, .move),
    (.puzzleWrong, .puzzleWrong, .illegalMove),
  ])
  func sendsTheSoundAndHapticOfEachEvent(
    event: FeedbackEvent,
    sound: SoundEffectID,
    haptic: HapticEventID?
  ) throws {
    let output = RecordingOutput()
    let router = FeedbackRouter(
      sound: output,
      haptics: output,
      tuning: try ContentCatalog.load().feedback
    )
    router.receive(event)
    #expect(output.sounds == [sound])
    #expect(output.haptics == (haptic.map { [$0] } ?? []))
  }
}
