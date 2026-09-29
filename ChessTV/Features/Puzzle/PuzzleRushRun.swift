import Foundation

/// Pure score, strike and clock state of one Puzzle Rush run.
/// The run ends at `maxStrikes` wrong puzzles, or when a timed mode's clock reaches zero.
struct PuzzleRushRun: Equatable, Sendable {
    static let maxStrikes = 3

    let mode: PuzzleRushMode
    private(set) var score = 0
    private(set) var strikes = 0
    /// Seconds left; nil in Survival.
    private(set) var remaining: TimeInterval?

    init(mode: PuzzleRushMode) {
        self.mode = mode
        remaining = mode.timeLimit
    }

    /// Number of puzzles finished (solved or failed), which is the index of the next puzzle.
    var puzzlesPlayed: Int { score + strikes }

    var isOver: Bool {
        strikes >= Self.maxStrikes || (remaining.map { $0 <= 0 } ?? false)
    }

    mutating func recordSolved() {
        guard !isOver else { return }
        score += 1
    }

    mutating func recordFailed() {
        guard !isOver else { return }
        strikes += 1
    }

    /// Counts the clock down by `elapsed` seconds (no effect in Survival).
    mutating func tick(_ elapsed: TimeInterval) {
        guard !isOver, let left = remaining else { return }
        remaining = max(0, left - elapsed)
    }
}
