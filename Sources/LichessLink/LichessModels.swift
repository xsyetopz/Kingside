import Foundation

public enum LichessColor: String, Decodable, Sendable, Equatable {
    case white, black
}

public enum LichessChallengeColor: String, Decodable, Sendable, Equatable {
    case white, black, random
}

public struct LichessPerf: Decodable, Sendable, Equatable {
    public var games: Int?
    public var rating: Int?
}

/// `GET /api/account`.
public struct LichessAccount: Decodable, Sendable, Equatable {
    public var id: String
    public var username: String
    /// Keyed by perf name, for example `blitz`.
    public var perfs: [String: LichessPerf]?
}

/// The other side in `gameStart`, `gameFinish`, and `/api/account/playing`.
public struct LichessOpponent: Decodable, Sendable, Equatable {
    /// `nil` for an AI or anonymous opponent.
    public var id: String?
    public var username: String
    public var rating: Int?
    /// Stockfish level, when the opponent is the AI.
    public var ai: Int?
}

public struct LichessGameEventInfo: Decodable, Sendable, Equatable {
    public var gameId: String
    public var color: LichessColor?
    public var fen: String?
    public var opponent: LichessOpponent?
    public var isMyTurn: Bool?
    public var rated: Bool?
    public var speed: String?
    public var secondsLeft: Int?
    public var winner: LichessColor?
}

/// An element of `GET /api/account/playing`'s `nowPlaying`.
public struct LichessOngoingGame: Decodable, Sendable, Equatable {
    public var gameId: String
    public var color: LichessColor
    public var fen: String
    public var opponent: LichessOpponent
    public var isMyTurn: Bool
    public var secondsLeft: Int?
}

struct LichessOngoingGamesResponse: Decodable {
    var nowPlaying: [LichessOngoingGame]
}

public struct LichessChallengeUser: Decodable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var rating: Int?
    public var title: String?
}

public struct LichessTimeControl: Decodable, Sendable, Equatable {
    /// `clock`, `correspondence`, or `unlimited`.
    public var type: String
    /// Seconds; `clock` only.
    public var limit: Int?
    /// Seconds; `clock` only.
    public var increment: Int?
    public var daysPerTurn: Int?
}

public struct LichessChallenge: Decodable, Sendable, Equatable {
    public var id: String
    public var status: String
    public var challenger: LichessChallengeUser
    public var destUser: LichessChallengeUser?
    public var rated: Bool
    public var speed: String
    public var timeControl: LichessTimeControl
    public var color: LichessChallengeColor
    /// `in` or `out`; present on challenge events.
    public var direction: String?
}

/// An element of `GET /api/stream/event`. Unknown event types are dropped by `parse(line:)`.
public enum LichessEvent: Sendable, Equatable {
    case gameStart(LichessGameEventInfo)
    case gameFinish(LichessGameEventInfo)
    case challenge(LichessChallenge)
    case challengeCanceled(LichessChallenge)
    case challengeDeclined(LichessChallenge)

    /// Returns `nil` for a blank keep-alive line and for an unknown event type.
    public static func parse(line: String) throws -> LichessEvent? {
        struct Game: Decodable { var game: LichessGameEventInfo }
        struct Challenge: Decodable { var challenge: LichessChallenge }
        return try LichessNDJSON.parse(line: line) { (type, data, decoder) -> Self? in
            switch type {
            case "gameStart": .gameStart(try decoder.decode(Game.self, from: data).game)
            case "gameFinish": .gameFinish(try decoder.decode(Game.self, from: data).game)
            case "challenge": .challenge(try decoder.decode(Challenge.self, from: data).challenge)
            case "challengeCanceled": .challengeCanceled(try decoder.decode(Challenge.self, from: data).challenge)
            case "challengeDeclined": .challengeDeclined(try decoder.decode(Challenge.self, from: data).challenge)
            default: nil
            }
        }
    }
}

public struct LichessGamePlayer: Decodable, Sendable, Equatable {
    public var id: String?
    public var name: String?
    /// Stockfish level, when this side is the AI.
    public var aiLevel: Int?
    public var rating: Int?
    public var title: String?
}

public struct LichessGameClock: Decodable, Sendable, Equatable {
    /// Milliseconds.
    public var initial: Int
    /// Milliseconds.
    public var increment: Int
}

public struct LichessGameState: Decodable, Sendable, Equatable {
    /// Space-separated UCI moves.
    public var moves: String
    /// Milliseconds.
    public var wtime: Int
    public var btime: Int
    public var winc: Int
    public var binc: Int
    /// Lichess status name, for example `started`, `mate`, `resign`.
    public var status: String
    public var winner: LichessColor?
    public var wdraw: Bool?
    public var bdraw: Bool?
    public var wtakeback: Bool?
    public var btakeback: Bool?
}

public struct LichessGameFull: Decodable, Sendable, Equatable {
    public var id: String
    public var white: LichessGamePlayer
    public var black: LichessGamePlayer
    /// `startpos` or a FEN.
    public var initialFen: String
    /// `nil` for correspondence games.
    public var clock: LichessGameClock?
    public var rated: Bool
    public var speed: String
    public var state: LichessGameState

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        white = try c.decode(LichessGamePlayer.self, forKey: .white)
        black = try c.decode(LichessGamePlayer.self, forKey: .black)
        initialFen = try c.decodeIfPresent(String.self, forKey: .initialFen) ?? "startpos"
        clock = try c.decodeIfPresent(LichessGameClock.self, forKey: .clock)
        rated = try c.decode(Bool.self, forKey: .rated)
        speed = try c.decode(String.self, forKey: .speed)
        state = try c.decode(LichessGameState.self, forKey: .state)
    }

    private enum CodingKeys: String, CodingKey {
        case id, white, black, initialFen, clock, rated, speed, state
    }
}

/// An element of `GET /api/board/game/stream/{id}`. Unknown event types are dropped by `parse(line:)`.
public enum LichessGameEvent: Sendable, Equatable {
    case gameFull(LichessGameFull)
    case gameState(LichessGameState)
    case chatLine(username: String, text: String, room: String)
    case opponentGone(gone: Bool, claimWinInSeconds: Int?)

    /// Returns `nil` for a blank keep-alive line and for an unknown event type.
    public static func parse(line: String) throws -> LichessGameEvent? {
        struct Chat: Decodable { var username: String, text: String, room: String }
        struct Gone: Decodable { var gone: Bool, claimWinInSeconds: Int? }
        return try LichessNDJSON.parse(line: line) { (type, data, decoder) -> Self? in
            switch type {
            case "gameFull": return .gameFull(try decoder.decode(LichessGameFull.self, from: data))
            case "gameState": return .gameState(try decoder.decode(LichessGameState.self, from: data))
            case "chatLine":
                let chat = try decoder.decode(Chat.self, from: data)
                return .chatLine(username: chat.username, text: chat.text, room: chat.room)
            case "opponentGone":
                let gone = try decoder.decode(Gone.self, from: data)
                return .opponentGone(gone: gone.gone, claimWinInSeconds: gone.claimWinInSeconds)
            default: return nil
            }
        }
    }
}
