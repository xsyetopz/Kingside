import ChessContent
import Foundation
import Testing

@testable import ChessPlay

@Suite struct OnlineChatTests {
    private let filter = ChatFilter(note: "Test list.", words: ["damn"])
    private let lines = [
        OnlineChatLine(username: "lichess", text: "Takeback sent"),
        OnlineChatLine(username: "Bob", text: "Damn, nice move"),
        OnlineChatLine(username: "alice", text: "thanks"),
    ]

    private func visible(enabled: Bool = true, muted: Bool = false) -> [OnlineChatMessage] {
        OnlineChat.visibleMessages(lines, myName: "Alice", isEnabled: enabled, opponentMuted: muted, filter: filter)
    }

    @Test func classifiesSystemOwnAndOpponentLines() {
        #expect(visible().map(\.kind) == [.system, .opponent, .own])
        #expect(visible().map(\.username) == ["lichess", "Bob", "alice"])
    }

    @Test func filtersOpponentLinesOnly() {
        #expect(visible().map(\.text) == ["Takeback sent", "••••, nice move", "thanks"])
        let own = OnlineChat.visibleMessages(
            [OnlineChatLine(username: "Alice", text: "damn")], myName: "Alice", isEnabled: true, opponentMuted: false, filter: filter)
        #expect(own.map(\.text) == ["damn"])
    }

    @Test func mutingKeepsSystemAndOwnLines() {
        #expect(visible(muted: true).map(\.kind) == [.system, .own])
    }

    @Test func chatOffShowsNothing() {
        #expect(visible(enabled: false).isEmpty)
        #expect(visible(enabled: false, muted: true).isEmpty)
    }

    @Test func beforeTheGameStartsNoLineIsOwn() {
        let shown = OnlineChat.visibleMessages(lines, myName: nil, isEnabled: true, opponentMuted: false, filter: filter)
        #expect(shown.map(\.kind) == [.system, .opponent, .opponent])
    }

    @Test func chatIsOnByDefaultAndOldSettingsKeepIt() throws {
        #expect(AppSettings().chatEnabled)
        let old = Data(#"{"soundEffects": false, "orientation": "black"}"#.utf8)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: old)
        #expect(decoded.chatEnabled && !decoded.soundEffects)
        let off = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"chatEnabled": false}"#.utf8))
        #expect(!off.chatEnabled)
        var settings = AppSettings()
        settings.chatEnabled = false
        let again = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))
        #expect(!again.chatEnabled)
    }
}
