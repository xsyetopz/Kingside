import Foundation
import ChessCore

/// Remaining time of both sides under a `TimeControl`. Pure value; the game view model drives it.
/// Rules (chess.com style):
/// - The clock runs only after both sides have made their first move (`runs(atPly:)`).
/// - The increment is added after each move made while the clock runs.
/// - A side whose time reaches zero has flagged; see `GameAdjudication.timeout`.
struct GameClock: Codable, Equatable, Sendable {
    static let lowTimeThreshold: TimeInterval = 10

    let timeControl: TimeControl
    private(set) var whiteRemaining: TimeInterval
    private(set) var blackRemaining: TimeInterval

    init(timeControl: TimeControl) {
        self.timeControl = timeControl
        whiteRemaining = TimeInterval(timeControl.initialSeconds)
        blackRemaining = TimeInterval(timeControl.initialSeconds)
    }

    var isTimed: Bool { timeControl.isTimed }

    func remaining(_ color: PieceColor) -> TimeInterval {
        color == .white ? whiteRemaining : blackRemaining
    }

    /// Whether the side to move is charged time when `plyCount` moves have been played.
    func runs(atPly plyCount: Int) -> Bool { isTimed && plyCount >= 2 }

    func isLow(_ color: PieceColor) -> Bool {
        isTimed && remaining(color) <= Self.lowTimeThreshold
    }

    func hasFlagged(_ color: PieceColor) -> Bool { isTimed && remaining(color) <= 0 }

    /// Charges `elapsed` seconds to `color`, never below zero. Returns true when it flags.
    @discardableResult
    mutating func consume(_ elapsed: TimeInterval, by color: PieceColor) -> Bool {
        guard isTimed else { return false }
        if color == .white { whiteRemaining = max(0, whiteRemaining - elapsed) }
        else { blackRemaining = max(0, blackRemaining - elapsed) }
        return hasFlagged(color)
    }

    /// Call after `color` moved; `plyBeforeMove` is the number of moves played before it.
    mutating func recordMove(by color: PieceColor, plyBeforeMove: Int) {
        guard runs(atPly: plyBeforeMove) else { return }
        let increment = TimeInterval(timeControl.incrementSeconds)
        if color == .white { whiteRemaining += increment } else { blackRemaining += increment }
    }
}
