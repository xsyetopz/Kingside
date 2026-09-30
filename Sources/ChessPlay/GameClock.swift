import ChessContent
import ChessCore
import Foundation

/// Remaining time of both sides under a `TimeControl`. A pure value: the game session drives
/// it with elapsed times from its injected `Clock`.
/// Rules (chess.com style):
/// - The clock runs only after both sides have made their first move (`runs(atPly:)`).
/// - The increment is added after each move made while the clock runs.
/// - A side whose time reaches zero has flagged; see `GameAdjudication.timeout`.
public struct GameClock: Codable, Equatable, Sendable {
    public let timeControl: TimeControl
    public private(set) var whiteRemaining: TimeInterval
    public private(set) var blackRemaining: TimeInterval

    public init(timeControl: TimeControl) {
        self.timeControl = timeControl
        whiteRemaining = TimeInterval(timeControl.initialSeconds)
        blackRemaining = TimeInterval(timeControl.initialSeconds)
    }

    public var isTimed: Bool { timeControl.isTimed }

    public func remaining(_ color: PieceColor) -> TimeInterval {
        color == .white ? whiteRemaining : blackRemaining
    }

    /// Whether the side to move is charged time when `plyCount` moves have been played.
    public func runs(atPly plyCount: Int) -> Bool { isTimed && plyCount >= 2 }

    /// `tuning` is `ContentCatalog.tuning.clock`.
    public func isLow(_ color: PieceColor, tuning: ClockTuning) -> Bool {
        isTimed && remaining(color) <= tuning.lowTimeSeconds
    }

    public func hasFlagged(_ color: PieceColor) -> Bool { isTimed && remaining(color) <= 0 }

    /// Charges `elapsed` seconds to `color`, never below zero. Returns true when it flags.
    @discardableResult
    public mutating func consume(_ elapsed: TimeInterval, by color: PieceColor) -> Bool {
        guard isTimed else { return false }
        if color == .white { whiteRemaining = max(0, whiteRemaining - elapsed) }
        else { blackRemaining = max(0, blackRemaining - elapsed) }
        return hasFlagged(color)
    }

    /// Call after `color` moved; `plyBeforeMove` is the number of moves played before it.
    public mutating func recordMove(by color: PieceColor, plyBeforeMove: Int) {
        guard runs(atPly: plyBeforeMove) else { return }
        let increment = TimeInterval(timeControl.incrementSeconds)
        if color == .white { whiteRemaining += increment } else { blackRemaining += increment }
    }
}
