import ChessContent
import Foundation

/// A chat line as the chat panel shows it.
public struct OnlineChatMessage: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// A line from the service itself.
        case system
        /// A line the player sent.
        case own
        case opponent
    }

    public var id: UUID
    public var username: String
    /// The text to show; an opponent's line has the word filter applied.
    public var text: String
    public var kind: Kind
}

/// What the in-game chat shows and accepts.
/// Lichess moderates chat on its side; the filter, mute and report link here only add local controls.
public enum OnlineChat {
    /// The longest message to send. This is the limit Lichess is believed to enforce; it is not verified.
    public static let maxLength = 140
    /// The sender of the service's own lines.
    public static let systemUsername = "lichess"

    /// The lines to show. Nothing shows while `isEnabled` is false. A muted opponent's lines are dropped,
    /// while system lines and the player's own lines stay. Other lines pass through `filter`.
    public static func visibleMessages(
        _ lines: [OnlineChatLine], myName: String?, isEnabled: Bool, opponentMuted: Bool, filter: ChatFilter
    ) -> [OnlineChatMessage] {
        guard isEnabled else { return [] }
        return lines.compactMap { line in
            if line.username.caseInsensitiveCompare(systemUsername) == .orderedSame {
                return OnlineChatMessage(id: line.id, username: line.username, text: line.text, kind: .system)
            }
            if let myName, line.username.caseInsensitiveCompare(myName) == .orderedSame {
                return OnlineChatMessage(id: line.id, username: line.username, text: line.text, kind: .own)
            }
            if opponentMuted { return nil }
            return OnlineChatMessage(id: line.id, username: line.username, text: filter.masked(line.text), kind: .opponent)
        }
    }
}
