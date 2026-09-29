import SwiftUI
import ChessCore

// Bot character model. The roster itself is in BotRoster.swift.
// `Bot.rating` drives the engine through `strength`; `line(for:)` picks a chat line.

enum BotGroup: String, CaseIterable, Identifiable, Sendable {
    case beginner, intermediate, advanced, master
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Moments a bot comments on during a game.
enum BotChatEvent: CaseIterable, Sendable {
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

struct Bot: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let rating: Int
    let group: BotGroup
    /// SF Symbol for the avatar; nil shows the name's initials.
    let symbol: String?
    let color: Color
    let bio: String
    let lines: [BotChatEvent: [String]]

    var strength: EngineStrength { EngineStrength(elo: rating) }

    var playerInfo: PlayerInfo { PlayerInfo(name: name, rating: rating, botID: id) }

    func line(for event: BotChatEvent) -> String {
        lines[event]?.randomElement() ?? ""
    }

    func avatar(size: CGFloat) -> AvatarView {
        AvatarView(name: name, systemImage: symbol, color: color, size: size)
    }

    static func == (lhs: Bot, rhs: Bot) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
