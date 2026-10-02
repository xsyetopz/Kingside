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

  /// A store holding `game` as imports used to save it: pass-and-play, neither side marked.
  private func makeStoreWithOldCopy(of game: ChessComGame) async throws -> GamePersistenceStore {
    let store = makeStore()
    _ = await ChessComImporting.importGames([game], username: "ann", into: store)
    var old = try #require(try await store.allGames().first)
    old.mode = .passAndPlay
    old.white = PlayerInfo(name: old.white.name, rating: old.white.rating)
    try await store.save(old)
    return store
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
    #expect(one.humanColor == .white)
    #expect(one.mode == .online(service: "chessCom", gameID: "1"))
    #expect(one.result == .whiteWon && one.termination == .resignation && one.isFinished)
    #expect(one.game.moves.count == 3)
    #expect(one.timeControl == TimeControl(initialSeconds: 180, incrementSeconds: 2))
  }

  @Test
  func reimportUpgradesACopySavedWithoutTheUsersSide() async throws {
    let store = makeStore()
    let game = try decodeGame(gameJSON(id: 1))
    _ = await ChessComImporting.importGames([game], username: "ann", into: store)
    let current = try #require(try await store.allGames().first)
    // Imports used to be saved as pass-and-play with neither side marked.
    var old = current
    old.mode = .passAndPlay
    old.white = PlayerInfo(name: current.white.name, rating: current.white.rating)
    try await store.save(old)

    let summary = await ChessComImporting.importGames([game], username: "ann", into: store)
    #expect(summary == ChessComImportSummary(imported: 0, updated: 1, duplicates: 0, skipped: 0))
    let upgraded = try await store.allGames()
    #expect(upgraded.count == 1)
    #expect(upgraded.first?.mode == .online(service: "chessCom", gameID: "1"))
    #expect(upgraded.first?.humanColor == .white)

    let again = await ChessComImporting.importGames([game], username: "ann", into: store)
    #expect(again == ChessComImportSummary(imported: 0, duplicates: 1, skipped: 0))
  }

  @Test
  func reimportKeepsAPassAndPlayGameWithAnotherID() async throws {
    let game = try decodeGame(gameJSON(id: 1))
    let scratch = makeStore()
    _ = await ChessComImporting.importGames([game], username: "ann", into: scratch)
    let played = try #require(try await scratch.allGames().first)
    // The same game played on this device: pass-and-play with a random id.
    let local = SavedGame(
      id: UUID(),
      createdAt: played.createdAt,
      updatedAt: played.updatedAt,
      mode: .passAndPlay,
      white: PlayerInfo(name: "Ann"),
      black: PlayerInfo(name: "Bob"),
      timeControl: played.timeControl,
      autoFlip: false,
      game: played.game,
      result: played.result,
      termination: played.termination,
      clock: played.clock
    )
    let store = makeStore()
    try await store.save(local)

    _ = await ChessComImporting.importGames([game], username: "ann", into: store)
    let saved = try await store.allGames()
    #expect(saved.count == 2)
    #expect(saved.first { $0.id == local.id }?.mode == .passAndPlay)
  }

  @Test
  func importUpdatesOldCopiesFromTheirMonthWithoutImportingItsOtherGames() async throws {
    let game = try decodeGame(gameJSON(id: 1))
    let store = try await makeStoreWithOldCopy(of: game)
    let other = try decodeGame(gameJSON(id: 2))
    let requested = Requests()

    let summary = await ChessComImporting.importGames([], username: "Ann", into: store) {
      await requested.append($0, $1)
      return [other, game]
    }
    #expect(summary == ChessComImportSummary(imported: 0, updated: 1, duplicates: 0, skipped: 0))
    // The game ended 2026-01-15 12:00 UTC: January in every time zone.
    #expect(await requested.months == ["2026-1"])
    let saved = try await store.allGames()
    #expect(saved.count == 1)
    #expect(saved.first?.mode == .online(service: "chessCom", gameID: "1"))
    #expect(saved.first?.humanColor == .white)

    let again = await ChessComImporting.importGames([], username: "ann", into: store) {
      await requested.append($0, $1)
      return [game]
    }
    #expect(again == ChessComImportSummary())
    #expect(await requested.months == ["2026-1"])
  }

  @Test
  func oldCopyOfAMonthThatFailsToLoadIsKeptForTheNextImport() async throws {
    struct Offline: Error {}
    let game = try decodeGame(gameJSON(id: 1))
    let store = try await makeStoreWithOldCopy(of: game)

    let failed = await ChessComImporting.importGames([], username: "ann", into: store) { _, _ in
      throw Offline()
    }
    #expect(failed == ChessComImportSummary())
    #expect(try await store.allGames().first?.mode == .passAndPlay)

    let retried = await ChessComImporting.importGames([], username: "ann", into: store) { _, _ in
      [game]
    }
    #expect(retried.updated == 1)
  }

  @Test
  func onlyPassAndPlayGamesOfTheUserAreLookedUp() async throws {
    let game = try decodeGame(gameJSON(id: 1))
    let store = try await makeStoreWithOldCopy(of: game)
    let requested = Requests()
    // An old copy of Ann's game, but Carol is linked now.
    let summary = await ChessComImporting.importGames([], username: "carol", into: store) {
      await requested.append($0, $1)
      return [game]
    }
    #expect(summary == ChessComImportSummary())
    #expect(await requested.months.isEmpty)

    var copy = try #require(try await store.allGames().first)
    #expect(ChessComImporting.isOldCopy(copy, of: "ANN"))
    #expect(ChessComImporting.isOldCopy(copy, of: "bob"))
    copy.mode = .online(service: "chessCom", gameID: "1")
    #expect(!ChessComImporting.isOldCopy(copy, of: "ann"))
  }

  @Test
  func gamesNearAMonthEndAreLookedUpInBothMonths() throws {
    let game = try decodeGame(gameJSON(id: 1))
    guard case .imported(let imported) = try ChessComGameImporter().importGame(game) else {
      Issue.record("game did not import")
      return
    }
    var saved = ChessComImporting.savedGame(imported, id: UUID(), username: "ann")
    // 2026-02-01 05:00 UTC is still January west of UTC−5.
    saved.createdAt = Date(timeIntervalSince1970: 1_769_922_000)
    let months = ChessComImporting.archiveMonths(of: [saved]).map { "\($0.year)-\($0.month)" }
    #expect(months == ["2026-1", "2026-2"])
    // 2025-12-31 20:00 UTC is already January east of UTC+4.
    saved.createdAt = Date(timeIntervalSince1970: 1_767_211_200)
    let yearEnd = ChessComImporting.archiveMonths(of: [saved]).map { "\($0.year)-\($0.month)" }
    #expect(yearEnd == ["2025-12", "2026-1"])
  }
}

/// The archive months an import asked for, in order.
private actor Requests {
  private(set) var months: [String] = []
  func append(_ year: Int, _ month: Int) { months.append("\(year)-\(month)") }
}
