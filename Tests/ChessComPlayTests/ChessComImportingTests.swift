import ChessComLink
import ChessPlay
import Foundation
import Testing
@testable import ChessComPlay

private let standardPGN =
  "[Event \\\"Live\\\"]\\n[White \\\"Ann\\\"]\\n[Black \\\"Bob\\\"]\\n"
  + "[Result \\\"1-0\\\"]\\n\\n1. e4 e5 2. Nf3 1-0\\n"

private func gameJSON(id: Int, rules: String = "chess") -> String {
  """
  {"url":"https://www.chess.com/game/live/\(id)","pgn":"\(standardPGN)","time_control":"180+2","end_time":1768478400,
  "rated":true,"time_class":"blitz","rules":"\(rules)",
  "white":{"rating":1500,"result":"win","username":"Ann"},
  "black":{"rating":1400,"result":"resigned","username":"Bob"}}
  """
}

private func decodeGame(_ json: String) throws -> ChessComGame {
  let decoder = JSONDecoder()
  decoder.dateDecodingStrategy = .secondsSince1970
  return try decoder.decode(ChessComGame.self, from: Data(json.utf8))
}

struct ChessComImportingTests {
  private func makeStore() -> GamePersistenceStore {
    GamePersistenceStore(
      fileURL: FileManager.default.temporaryDirectory.appending(
        path: "ChessComImportingTests-\(UUID().uuidString)/games.json"
      )
    )
  }

  @Test
  func timeControlsResultsAndTerminationsMap() {
    #expect(
      ChessComImporting.timeControl("180+2")
        == TimeControl(initialSeconds: 180, incrementSeconds: 2)
    )
    #expect(
      ChessComImporting.timeControl("600") == TimeControl(initialSeconds: 600, incrementSeconds: 0)
    )
    #expect(ChessComImporting.timeControl("1/86400") == .untimed)
    #expect(ChessComImporting.result(white: .win, black: .checkmated) == .whiteWon)
    #expect(ChessComImporting.result(white: .timeout, black: .win) == .blackWon)
    #expect(ChessComImporting.result(white: .agreed, black: .agreed) == .draw)
    #expect(ChessComImporting.termination(white: .win, black: .checkmated) == .checkmate)
    #expect(ChessComImporting.termination(white: .resigned, black: .win) == .resignation)
    #expect(ChessComImporting.termination(white: .fiftyMove, black: .fiftyMove) == .fiftyMoveRule)
    #expect(ChessComImporting.termination(white: .win, black: .other("abandoned")) == nil)
  }

  @Test
  func gameIDsAreStablePerURL() throws {
    let one = try #require(URL(string: "https://www.chess.com/game/live/1"))
    let two = try #require(URL(string: "https://www.chess.com/game/live/2"))
    let first = ChessComImporting.savedGameID(for: one)
    let second = ChessComImporting.savedGameID(for: one)
    #expect(first == second)
    #expect(first != ChessComImporting.savedGameID(for: two))
  }

  @Test
  func importIntoUnreadableArchiveSkipsEveryGame() async throws {
    let fileURL = FileManager.default.temporaryDirectory
      .appending(path: "ChessComImportingTests-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: fileURL) }
    let damaged = Data("not json".utf8)
    try damaged.write(to: fileURL)
    let games = [try decodeGame(gameJSON(id: 1)), try decodeGame(gameJSON(id: 2))]

    let summary = await ChessComImporting.importGames(
      games,
      username: "ann",
      into: GamePersistenceStore(fileURL: fileURL)
    )
    #expect(summary == ChessComImportSummary(imported: 0, duplicates: 0, skipped: 2))
    #expect(try Data(contentsOf: fileURL) == damaged)
  }

  @Test
  func importSkipsDuplicatesAndVariants() async throws {
    let store = makeStore()
    let games = [
      try decodeGame(gameJSON(id: 1)), try decodeGame(gameJSON(id: 2)),
      try decodeGame(gameJSON(id: 3, rules: "chess960")),
    ]

    let first = await ChessComImporting.importGames(games, username: "ann", into: store)
    #expect(first == ChessComImportSummary(imported: 2, duplicates: 0, skipped: 1))
    let second = await ChessComImporting.importGames(games, username: "ann", into: store)
    #expect(second == ChessComImportSummary(imported: 0, duplicates: 2, skipped: 1))

    let saved = try await store.allGames()
    #expect(saved.count == 2)
    let one = try #require(
      saved.first { $0.id == ChessComImporting.savedGameID(for: games[0].url) }
    )
    #expect(one.white.name == "Ann" && one.black.name == "Bob")
    #expect(one.result == .whiteWon && one.termination == .resignation && one.isFinished)
    #expect(one.game.moves.count == 3)
    #expect(one.timeControl == TimeControl(initialSeconds: 180, incrementSeconds: 2))
  }
}
