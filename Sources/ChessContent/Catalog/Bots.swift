import Foundation
import ChessCore

/// `bots.json`: the bot characters and the groups the roster is split into, weakest first.
public struct BotCatalog: Codable, Sendable {
    public let groups: [BotGroup]
    public let bots: [Bot]

    public func bot(id: String) -> Bot? { bots.first { $0.id == id } }

    public func bots(in group: BotGroup) -> [Bot] { bots.filter { $0.groupID == group.id } }
}

public struct BotGroup: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let nameKey: String
}

/// A bot character. Every text field is a localisation key.
public struct Bot: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let nameKey: String
    public let bioKey: String
    public let elo: Int
    public let groupID: String
    public let avatar: BotAvatar
    /// Chat-line keys for each moment; one is picked at random when it happens.
    public let chat: [BotChatEvent: [String]]

    public var strength: EngineStrength { EngineStrength(elo: elo) }
}

public struct BotAvatar: Codable, Hashable, Sendable {
    /// SF Symbol name; nil shows the name's initials.
    public let symbol: String?
    public let color: HexColor
}

/// Moments a bot comments on during a game.
public enum BotChatEvent: String, Codable, CodingKeyRepresentable, CaseIterable, Sendable {
    case greeting
    case playerCaptures
    case botCaptures
    case playerBlunder
    case check
    case botWins
    case botLoses
    case draw
    case drawDeclined
    case takeback
}
