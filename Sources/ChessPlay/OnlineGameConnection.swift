import ChessCore
import Foundation

// The port between `OnlineGameSession` and an online chess service. The server is the source
// of truth: the session plays what the events say and sends the player's actions.
// - Service-neutral: no service types appear here. An adapter maps a service's game stream
//   (Lichess for now) to `OnlineGameEvent`s and `OnlineAction`s to its API calls.
// - Moves are UCI strings (`e2e4`, `e7e8q`); castling is the king's two-square move.

/// One side of an online game as the server reports it.
public struct OnlinePlayer: Equatable, Sendable {
    public var name: String
    public var rating: Int?
    /// Title such as `GM` or `BOT`; nil for untitled players.
    public var title: String?

    public init(name: String, rating: Int? = nil, title: String? = nil) {
        self.name = name
        self.rating = rating
        self.title = title
    }
}

/// The full game, sent first and again after every reconnect.
public struct OnlineGameStart: Equatable, Sendable {
    public var gameID: String
    /// Start position; nil means the standard initial position.
    public var initialFEN: String?
    public var white: OnlinePlayer
    public var black: OnlinePlayer
    /// The side the signed-in player plays.
    public var myColor: PieceColor
    /// nil for correspondence and unlimited games.
    public var timeControl: TimeControl?
    public var rated: Bool
    public var state: OnlineGameState

    public init(
        gameID: String, initialFEN: String? = nil, white: OnlinePlayer, black: OnlinePlayer, myColor: PieceColor,
        timeControl: TimeControl?, rated: Bool, state: OnlineGameState
    ) {
        self.gameID = gameID
        self.initialFEN = initialFEN
        self.white = white
        self.black = black
        self.myColor = myColor
        self.timeControl = timeControl
        self.rated = rated
        self.state = state
    }
}

/// The moves, clocks and status after a change on the server.
public struct OnlineGameState: Equatable, Sendable {
    /// Every move from the start position, in UCI.
    public var uciMoves: [String]
    /// Remaining time when the server sent the state; nil in untimed games.
    public var whiteTime: Duration?
    public var blackTime: Duration?
    public var status: OnlineGameStatus
    /// The winner of a finished game; nil for a draw or while the game goes on.
    public var winner: PieceColor?
    public var whiteOffersDraw: Bool
    public var blackOffersDraw: Bool

    public init(
        uciMoves: [String] = [], whiteTime: Duration? = nil, blackTime: Duration? = nil, status: OnlineGameStatus = .started,
        winner: PieceColor? = nil, whiteOffersDraw: Bool = false, blackOffersDraw: Bool = false
    ) {
        self.uciMoves = uciMoves
        self.whiteTime = whiteTime
        self.blackTime = blackTime
        self.status = status
        self.winner = winner
        self.whiteOffersDraw = whiteOffersDraw
        self.blackOffersDraw = blackOffersDraw
    }
}

/// Game status as the server names it. Every case but `created` and `started` is final.
public enum OnlineGameStatus: Equatable, Sendable {
    case created, started, aborted, mate, resign, stalemate
    /// The opponent left and the other side claimed the win.
    case timeout
    case draw
    /// A side's clock ran out.
    case outoftime
    case cheat, noStart, unknownFinish, variantEnd
    /// A status this app does not know; treated as finished.
    case other(String)

    public var isFinished: Bool { self != .created && self != .started }
}

public enum OnlineGameEvent: Equatable, Sendable {
    case started(OnlineGameStart)
    case state(OnlineGameState)
    case chat(OnlineChatLine)
    /// The opponent left; the player may claim the win after `claimWinIn` (nil: not yet known).
    case opponentGone(claimWinIn: Duration?)
    case opponentBack
}

public struct OnlineChatLine: Equatable, Sendable, Identifiable {
    public var id: UUID
    public var username: String
    public var text: String

    public init(id: UUID = UUID(), username: String, text: String) {
        self.id = id
        self.username = username
        self.text = text
    }
}

/// What the player asks the server to do.
public enum OnlineAction: Equatable, Sendable {
    /// A move in UCI.
    case move(String)
    case resign, abort, offerDraw, acceptDraw, declineDraw, claimVictory, claimDraw
    case chat(String)
}

/// One game on one online service.
public protocol OnlineGameConnection: Sendable {
    /// Service id, such as `lichess`; stored in `GameMode.online`.
    var service: String { get }
    /// A new stream of the game's events. It starts with `.started`; calling it again reconnects.
    func events() -> AsyncThrowingStream<OnlineGameEvent, Error>
    func send(_ action: OnlineAction) async throws
}
