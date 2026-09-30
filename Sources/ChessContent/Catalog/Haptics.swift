import Foundation

/// `haptics.json`: the tunable choices of `ChessFeedback`. That is the Core Haptics patterns, the
/// sound and haptic of each game event, and the game-controller repeat timing.
public struct FeedbackTuning: Codable, Hashable, Sendable {
  public let haptics: [HapticEventID: HapticPattern]
  /// The sound and haptic of each event other than a move.
  public let events: [FeedbackEventKind: FeedbackCue]
  /// The haptic of a move, by the move's sound. The sound itself comes with the event.
  public let moveHaptics: [SoundEffectID: HapticEventID]
  public let controller: ControllerTuning
}

/// Moments that play a haptic pattern.
public enum HapticEventID: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
  case move, capture, check, illegalMove, gameOver
}

/// Feedback events that carry no sound of their own; a move names its sound.
public enum FeedbackEventKind: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
  case gameStarted, illegalMove, gameOver, lowTime, puzzleCorrect, puzzleWrong
}

/// What an event plays; a nil member plays nothing.
public struct FeedbackCue: Codable, Hashable, Sendable {
  public let sound: SoundEffectID?
  public let haptic: HapticEventID?
}

/// A Core Haptics pattern as a list of pulses.
public struct HapticPattern: Codable, Hashable, Sendable {
  public let pulses: [HapticPulse]
}

public struct HapticPulse: Codable, Hashable, Sendable {
  /// Start time within the pattern, in seconds.
  public let time: Double
  /// Length in seconds; zero plays a transient tap, more plays a continuous buzz.
  public let duration: Double
  /// 0...1.
  public let intensity: Double
  /// 0...1: dull to crisp.
  public let sharpness: Double
}

/// How a held d-pad or thumbstick direction moves the board cursor.
public struct ControllerTuning: Codable, Hashable, Sendable {
  /// Seconds a direction is held before the cursor starts to repeat.
  public let repeatDelay: Double
  /// Seconds between repeats after the delay.
  public let repeatInterval: Double
  /// Axis value, 0...1, from which a thumbstick or touch surface counts as a direction.
  public let axisThreshold: Double
}
