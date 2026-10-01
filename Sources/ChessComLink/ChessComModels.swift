import Foundation

public struct ChessComProfile: Codable, Equatable, Sendable {
  public var username: String
  public var name: String?
  public var avatar: URL?
  /// Country resource URL; its last path component is the ISO country code.
  var country: URL?
  public var joined: Date
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
  public var rules: String
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
    public var result: String
  }
}

struct ChessComArchivesResponse: Decodable {
  var archives: [URL]
}

struct ChessComGamesResponse: Decodable {
  var games: [ChessComGame]
}
