import ChessCore
import Foundation
import Testing
@testable import ChessComLink

@Suite
struct ChessComImportTests {
  private func loadGame(_ name: String) async throws -> ChessComGame {
    let body = try fixture(name)
    let (client, _) = makeClient { _ in (200, [:], body) }
    return try #require(await client.games(username: "hikaru", year: 2014, month: 1).first)
  }

  @Test
  func importsStandardGame() async throws {
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

  @Test
  func skipsVariants() async throws {
    let source = try await loadGame("games-variant")
    #expect(source.rules == .chess960)
    #expect(try ChessComGameImporter().importGame(source) == .skipped(source))
  }

  private func player(result: String) throws -> ChessComGame.Player {
    let json = #"{"username":"hikaru","rating":2800,"result":"\#(result)"}"#
    return try JSONDecoder().decode(ChessComGame.Player.self, from: Data(json.utf8))
  }

  @Test(arguments: [
    ("win", ChessComPlayerResult.win), ("checkmated", .checkmated), ("timeout", .timeout),
    ("resigned", .resigned), ("stalemate", .stalemate), ("repetition", .repetition),
    ("insufficient", .insufficient), ("agreed", .agreed), ("50move", .fiftyMove),
    ("timevsinsufficient", .timeVsInsufficient),
  ])
  func knownResultCodeDecodesToItsCase(code: String, result: ChessComPlayerResult) throws {
    #expect(try player(result: code).result == result)
  }

  @Test
  func unknownResultCodeDecodesToOther() throws {
    #expect(try player(result: "abandoned").result == .other("abandoned"))
  }

  private func rules(_ name: String) throws -> ChessComRules {
    try JSONDecoder().decode(ChessComRules.self, from: Data(#""\#(name)""#.utf8))
  }

  @Test(arguments: [
    ("chess", ChessComRules.chess), ("Chess", .chess), ("chess960", .chess960),
  ])
  func knownRulesDecodeToTheirCase(name: String, expected: ChessComRules) throws {
    #expect(try rules(name) == expected)
  }

  @Test
  func unknownRulesDecodeToOtherWithTheNameAsSent() throws {
    #expect(try rules("Bughouse") == .other("Bughouse"))
  }

  @Test
  func badPGNOfStandardGameThrows() async throws {
    var source = try await loadGame("games")
    source.pgn = "1. e4 e4 *"
    #expect(throws: PGNError.self) { try ChessComGameImporter().importGame(source) }
  }
}
