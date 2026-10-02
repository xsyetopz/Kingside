import ChessContent
import Foundation
import Observation

/// Saved puzzle progress: rated puzzle rating and history, streak, Puzzle Rush bests,
/// seen puzzle ids and solved Daily Puzzle days. The synthesized Codable shape is the one
/// stored under `Kingside.puzzleProgress.v1`.
public struct PuzzleProgress: Codable, Equatable, Sendable {
  public var rating: Int
  /// Number of rated results recorded (drives the K-factor).
  var ratedPlayed = 0
  public var streak = 0
  var bestStreak = 0
  /// Best score per `PuzzleRushMode.rawValue`.
  public var rushBest: [String: Int] = [:]
  var seenIDs: Set<String> = []
  /// `PuzzleDay.key` values of solved Daily Puzzles.
  var dailySolved: Set<String> = []

  /// Fresh progress; `rating` is `ContentCatalog.tuning.puzzleRating.initial`.
  init(rating: Int) {
    self.rating = rating
  }
}

/// Persists `PuzzleProgress` as JSON under one UserDefaults key.
@preconcurrency
@Observable
@MainActor
public final class PuzzleProgressStore {
  static let defaultsKey = "Kingside.puzzleProgress.v1"

  public private(set) var progress: PuzzleProgress { didSet { save() } }
  private let defaults: UserDefaults
  private let rating: PuzzleRatingTuning

  /// `rating` is `ContentCatalog.tuning.puzzleRating`.
  public init(defaults: UserDefaults, rating: PuzzleRatingTuning) {
    self.defaults = defaults
    self.rating = rating
    if let data = defaults.data(forKey: Self.defaultsKey),
      let decoded = try? JSONDecoder().decode(PuzzleProgress.self, from: data)
    {
      progress = decoded
    } else {
      progress = PuzzleProgress(rating: rating.initial)
    }
  }

  /// Applies a rated result and returns the rating change.
  @discardableResult
  func recordRated(puzzleRating: Int, solved: Bool) -> Int {
    let delta = rating.change(
      rating: progress.rating,
      puzzleRating: puzzleRating,
      solved: solved,
      puzzlesPlayed: progress.ratedPlayed
    )
    progress.rating = max(rating.minimum, progress.rating + delta)
    progress.ratedPlayed += 1
    recordStreak(solved: solved)
    return delta
  }

  /// Updates the streak without a rating change (unrated attempts).
  func recordStreak(solved: Bool) {
    progress.streak = solved ? progress.streak + 1 : 0
    progress.bestStreak = max(progress.bestStreak, progress.streak)
  }

  func markSeen(_ id: String) { progress.seenIDs.insert(id) }

  func resetSeen() { progress.seenIDs.removeAll() }

  public func rushBest(for mode: PuzzleRushMode) -> Int { progress.rushBest[mode.rawValue] ?? 0 }

  /// Saves `score` if it beats the stored best; returns true for a new best.
  @discardableResult
  func recordRush(mode: PuzzleRushMode, score: Int) -> Bool {
    guard score > rushBest(for: mode) else { return false }
    progress.rushBest[mode.rawValue] = score
    return true
  }

  public func isDailySolved(_ day: PuzzleDay) -> Bool { progress.dailySolved.contains(day.key) }

  func markDailySolved(_ day: PuzzleDay) { progress.dailySolved.insert(day.key) }

  private func save() {
    if let data = try? JSONEncoder().encode(progress) {
      defaults.set(data, forKey: Self.defaultsKey)
    }
  }
}
