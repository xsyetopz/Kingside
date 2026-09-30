import ChessContent
import Foundation

/// Elo update for rated puzzles: the player "plays" the puzzle as an opponent with the
/// puzzle's rating. K is `provisionalKFactor` for the first `provisionalGames` rated puzzles,
/// then `establishedKFactor`.
extension PuzzleRatingTuning {
  public func kFactor(puzzlesPlayed: Int) -> Double {
    puzzlesPlayed < provisionalGames ? provisionalKFactor : establishedKFactor
  }

  public static func expectedScore(rating: Int, puzzleRating: Int) -> Double {
    1 / (1 + pow(10, Double(puzzleRating - rating) / 400))
  }

  /// Rating change for one result; `puzzlesPlayed` counts rated puzzles before this one.
  public func change(rating: Int, puzzleRating: Int, solved: Bool, puzzlesPlayed: Int) -> Int {
    let score: Double = solved ? 1 : 0
    let expected = Self.expectedScore(rating: rating, puzzleRating: puzzleRating)
    return Int((kFactor(puzzlesPlayed: puzzlesPlayed) * (score - expected)).rounded())
  }
}
