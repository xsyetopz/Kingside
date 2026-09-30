import ChessContent
import Foundation
import Observation

/// Rated puzzle training: picks an unseen puzzle near the player's rating, records the first
/// decisive result in `PuzzleProgressStore`, and keeps the streak.
@Observable
@MainActor
public final class RatedPuzzleSession {
    public let board: PuzzleBoardSession
    public private(set) var puzzle: Puzzle?
    /// Set once the attempt is decided (solved, failed, or unrated after a hint).
    public private(set) var outcome: PuzzleSession.RatedOutcome?
    /// The rating change of the decided attempt; nil while open and for an unrated attempt.
    public private(set) var ratingChange: Int?

    private let puzzles: [Puzzle]
    private let selector: PuzzleSelector
    private let progress: PuzzleProgressStore
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()

    public init(catalog: ContentCatalog, progress: PuzzleProgressStore, board: PuzzleBoardSession) {
        puzzles = catalog.puzzles
        selector = PuzzleSelector(tuning: catalog.tuning.puzzleSelection)
        self.progress = progress
        self.board = board
        board.onOutcome = { [weak self] in self?.record($0) }
    }

    /// Loads the first puzzle; later calls keep the current one.
    public func start() {
        if puzzle == nil { next() }
    }

    /// Loads the next puzzle. When every puzzle has been seen, the seen list starts over.
    public func next() {
        let rating = progress.progress.rating
        var pick = selector.rated(from: puzzles, rating: rating, seen: progress.progress.seenIDs, using: &generator)
        if pick == nil {
            progress.resetSeen()
            pick = selector.rated(from: puzzles, rating: rating, seen: [], using: &generator)
        }
        guard let pick else { return }
        progress.markSeen(pick.id)
        puzzle = pick
        outcome = nil
        ratingChange = nil
        board.load(pick)
    }

    private func record(_ result: PuzzleSession.RatedOutcome) {
        outcome = result
        guard let puzzle else { return }
        switch result {
        case .solved, .failed: ratingChange = progress.recordRated(puzzleRating: puzzle.rating, solved: result == .solved)
        case .unrated: progress.recordStreak(solved: false)
        }
    }
}
