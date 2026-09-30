import ChessContent
import Foundation

/// A Puzzle Rush mode. The raw value keys the stored best scores and the mode's entry in
/// `ContentCatalog.tuning.puzzleRush.timeLimits`.
public enum PuzzleRushMode: String, CaseIterable, Codable, Identifiable, Sendable {
  case threeMinutes, fiveMinutes, survival

  public var id: String { rawValue }

  /// Localisation key of the mode's name.
  public var nameKey: String { "puzzleRush.mode.\(rawValue).name" }

  /// Countdown length; nil for a mode without a time limit (Survival).
  public func timeLimit(tuning: PuzzleRushTuning) -> TimeInterval? { tuning.timeLimits[rawValue] }
}

/// Pure score, strike, and clock state of one Puzzle Rush run.
/// The run ends at `maxStrikes` wrong puzzles, or when a timed mode's clock reaches zero.
public struct PuzzleRushRun: Equatable, Sendable {
  public let mode: PuzzleRushMode
  public let maxStrikes: Int
  public private(set) var score = 0
  public private(set) var strikes = 0
  /// Seconds left; nil in Survival.
  public private(set) var remaining: TimeInterval?

  /// `tuning` is `ContentCatalog.tuning.puzzleRush`.
  public init(mode: PuzzleRushMode, tuning: PuzzleRushTuning) {
    self.mode = mode
    maxStrikes = tuning.maxStrikes
    remaining = mode.timeLimit(tuning: tuning)
  }

  /// Number of puzzles finished (solved or failed), which is the index of the next puzzle.
  public var puzzlesPlayed: Int { score + strikes }

  public var isOver: Bool {
    strikes >= maxStrikes || (remaining.map { $0 <= 0 } ?? false)
  }

  public mutating func recordSolved() {
    guard !isOver else { return }
    score += 1
  }

  public mutating func recordFailed() {
    guard !isOver else { return }
    strikes += 1
  }

  /// Counts the clock down by `elapsed` seconds (no effect in Survival).
  public mutating func tick(_ elapsed: TimeInterval) {
    guard !isOver, let left = remaining else { return }
    remaining = max(0, left - elapsed)
  }
}
