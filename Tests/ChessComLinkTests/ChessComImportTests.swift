import ChessCore
import Foundation
import Testing
@testable import ChessComLink

@Suite struct ChessComImportTests {
    private func loadGame(_ name: String) async throws -> ChessComGame {
        let body = try fixture(name)
        let (client, _) = makeClient { _ in (200, [:], body) }
        return try #require(await client.games(username: "hikaru", year: 2014, month: 1).first)
    }

    @Test func importsStandardGame() async throws {
        let source = try await loadGame("games")
        guard case .imported(let imported) = try ChessComGameImporter().importGame(source) else {
            Issue.record("expected an imported game")
            return
        }
        #expect(imported.game.moves.map(\.san) == ["e4", "e5", "Nc3", "Nc6", "g3", "g6"])
        #expect(imported.pgn.tags["White"] == "Hikaru")
        #expect(imported.pgn.result == "1-0")
        #expect(imported.source.url == source.url)
    }

    @Test func skipsVariants() async throws {
        let source = try await loadGame("games-variant")
        #expect(source.rules == "chess960")
        #expect(try ChessComGameImporter().importGame(source) == .skipped(source))
    }

    @Test func badPGNOfStandardGameThrows() async throws {
        var source = try await loadGame("games")
        source.pgn = "1. e4 e4 *"
        #expect(throws: PGNError.self) { try ChessComGameImporter().importGame(source) }
    }
}
