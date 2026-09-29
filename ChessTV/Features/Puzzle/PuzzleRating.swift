import Foundation

/// Elo update for rated puzzles: the player "plays" the puzzle as an opponent with the
/// puzzle's rating. K is 32 for the first 50 rated puzzles, then 16.
enum PuzzleRating {
    static let initial = 800
    static let provisionalGames = 50

    static func kFactor(puzzlesPlayed: Int) -> Double {
        puzzlesPlayed < provisionalGames ? 32 : 16
    }

    static func expectedScore(rating: Int, puzzleRating: Int) -> Double {
        1 / (1 + pow(10, Double(puzzleRating - rating) / 400))
    }

    /// Rating change for one result; `puzzlesPlayed` counts rated puzzles before this one.
    static func change(rating: Int, puzzleRating: Int, solved: Bool, puzzlesPlayed: Int) -> Int {
        let score: Double = solved ? 1 : 0
        let delta = kFactor(puzzlesPlayed: puzzlesPlayed) * (score - expectedScore(rating: rating, puzzleRating: puzzleRating))
        return Int(delta.rounded())
    }
}
