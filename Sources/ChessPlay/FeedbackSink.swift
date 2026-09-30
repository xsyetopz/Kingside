import ChessContent
import Foundation

/// A moment that the player should hear or feel. `ChessFeedback` maps each event to sound and
/// haptics; sessions only report what happened.
public enum FeedbackEvent: Equatable, Sendable {
  /// A new game starts.
  case gameStarted
  /// A move that did not end the game; the effect is chosen by `MoveSound`.
  case moved(SoundEffectID)
  /// The player chose a square that the selected piece cannot move to.
  case illegalMove
  case gameOver(GameResult)
  /// The side to move reached `ContentCatalog.tuning.clock.lowTimeSeconds`; once per side and game.
  case lowTime
  /// The solver played a correct puzzle move; replaces `.moved` for that move.
  case puzzleCorrect
  /// The solver played a wrong puzzle move.
  case puzzleWrong
}

/// Receives the feedback events of a session.
@preconcurrency
@MainActor
public protocol FeedbackSink {
  func receive(_ event: FeedbackEvent)
}

/// Ignores every event.
public struct NullFeedbackSink: FeedbackSink {
  public init() {}
  public func receive(_ event: FeedbackEvent) {}
}
