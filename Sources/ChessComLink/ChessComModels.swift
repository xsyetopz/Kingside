import Foundation

public struct ChessComProfile: Codable, Equatable, Sendable {
  public var username: String
  public var name: String?
  public var avatar: URL?
  /// Country resource URL; its last path component is the ISO country code.
  var country: URL?
  public var joined: Date
  // Decoded so the model matches the API payload; nothing reads it yet.
  // swiftlint:disable:next unused_declaration
  var lastOnline: Date

  enum CodingKeys: String, CodingKey {
    case username, name, avatar, country, joined
    case lastOnline = "last_online"
  }
}

public struct ChessComStats: Codable, Equatable, Sendable {
  public var rapid: ModeStats?
  public var blitz: ModeStats?
  public var bullet: ModeStats?
  public var daily: ModeStats?

  enum CodingKeys: String, CodingKey {
    case rapid = "chess_rapid"
    case blitz = "chess_blitz"
    case bullet = "chess_bullet"
    case daily = "chess_daily"
  }

  public struct ModeStats: Codable, Equatable, Sendable {
    public var last: Rating?
    public var best: Rating?
    public var record: Record?
  }

  public struct Rating: Codable, Equatable, Sendable {
    public var rating: Int
    public var date: Date?
  }

  public struct Record: Codable, Equatable, Sendable {
    public var win: Int
    public var loss: Int
    public var draw: Int
  }
}

public struct ChessComGame: Codable, Equatable, Sendable, Identifiable {
  public var url: URL
  public var pgn: String
  public var timeClass: String
  public var timeControl: String
  var rules: ChessComRules
  public var rated: Bool
  public var endTime: Date
  public var white: Player
  public var black: Player

  public var id: URL { url }

  enum CodingKeys: String, CodingKey {
    case url, pgn, rules, rated, white, black
    case timeClass = "time_class"
    case timeControl = "time_control"
    case endTime = "end_time"
  }

  public struct Player: Codable, Equatable, Sendable {
    public var username: String
    public var rating: Int
    public var result: ChessComPlayerResult
  }
}

/// Chess.com adds variants over time, so a name this enum does not list decodes to `other`.
/// Names match case-insensitively; `other` keeps the name as sent.
enum ChessComRules: Sendable, Equatable {
  case chess, chess960
  case other(String)
}

extension ChessComRules: RawRepresentable, Codable {
  init(rawValue: String) {
    switch rawValue.lowercased() {
    case "chess": self = .chess
    case "chess960": self = .chess960
    default: self = .other(rawValue)
    }
  }

  var rawValue: String {
    switch self {
    case .chess: "chess"
    case .chess960: "chess960"
    case .other(let name): name
    }
  }
}

/// One side's result code. Chess.com adds codes over time, so a code this enum does not list
/// decodes to `other`.
public enum ChessComPlayerResult: Sendable, Equatable {
  case win, checkmated, timeout, resigned, stalemate, repetition, insufficient, agreed
  case fiftyMove, timeVsInsufficient
  case other(String)
}

extension ChessComPlayerResult: RawRepresentable, Codable {
  public init(rawValue: String) {
    switch rawValue {
    case "win": self = .win
    case "checkmated": self = .checkmated
    case "timeout": self = .timeout
    case "resigned": self = .resigned
    case "stalemate": self = .stalemate
    case "repetition": self = .repetition
    case "insufficient": self = .insufficient
    case "agreed": self = .agreed
    case "50move": self = .fiftyMove
    case "timevsinsufficient": self = .timeVsInsufficient
    default: self = .other(rawValue)
    }
  }

  public var rawValue: String {
    switch self {
    case .win: "win"
    case .checkmated: "checkmated"
    case .timeout: "timeout"
    case .resigned: "resigned"
    case .stalemate: "stalemate"
    case .repetition: "repetition"
    case .insufficient: "insufficient"
    case .agreed: "agreed"
    case .fiftyMove: "50move"
    case .timeVsInsufficient: "timevsinsufficient"
    case .other(let code): code
    }
  }
}

struct ChessComArchivesResponse: Decodable {
  var archives: [URL]
}

struct ChessComGamesResponse: Decodable {
  var games: [ChessComGame]
}
