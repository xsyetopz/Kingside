import Foundation

struct Player: Codable, Equatable, Sendable, Identifiable {
    let username: String
    let name: String?
    let avatar: URL?
    let country: URL?
    let joined: Date?
    var id: String { username.lowercased() }

    enum CodingKeys: String, CodingKey { case username, name, avatar, country, joined }

    init(username: String, name: String? = nil, avatar: URL? = nil, country: URL? = nil, joined: Date? = nil) {
        self.username = username
        self.name = name
        self.avatar = avatar
        self.country = country
        self.joined = joined
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        username = try c.decode(String.self, forKey: .username)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        avatar = try c.decodeIfPresent(URL.self, forKey: .avatar)
        country = try c.decodeIfPresent(URL.self, forKey: .country)
        if let timestamp = try c.decodeIfPresent(TimeInterval.self, forKey: .joined) { joined = Date(timeIntervalSince1970: timestamp) }
        else { joined = nil }
    }
}

struct OnlineGame: Codable, Equatable, Sendable, Identifiable {
    let url: URL?
    let pgn: String
    let endTime: TimeInterval?
    var id: String { url?.absoluteString ?? String(pgn.hashValue) }
    enum CodingKeys: String, CodingKey { case url, pgn; case endTime = "end_time" }
}

struct Tournament: Codable, Equatable, Sendable, Identifiable {
    let url: URL
    let name: String
    var id: URL { url }
}

protocol ChessAPI: Sendable {
    func getPlayer(username: String) async throws -> Player
    func getGames(username: String) async throws -> [OnlineGame]
    func getTournaments() async throws -> [Tournament]
}
