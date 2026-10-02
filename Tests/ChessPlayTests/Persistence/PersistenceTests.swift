import ChessContent
import ChessCore
import Foundation
import Testing

@testable import ChessPlay

@Suite
struct PersistenceTests {
  private func archiveURL(in directory: URL) -> URL {
    directory.appending(components: "Kingside", GamePersistenceStore.fileName)
  }

  /// A second store on the same directory reads the file, as the next launch does, not the
  /// memory of the first.
  private func makeStore(in directory: URL) -> GamePersistenceStore {
    GamePersistenceStore(fileURL: archiveURL(in: directory))
  }

  private func defaultBot() throws -> PlayerInfo {
    let catalog = try Shared.catalog
    let bot = try #require(catalog.bots.bot(id: catalog.defaults.botID))
    return PlayerInfo(bot: bot, localization: Shared.english)
  }

  private func makeGame(
    result: GameResult = .ongoing,
    // Whole seconds: the store encodes dates as ISO 8601, which drops fractions.
    updatedAt: Date = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down)),
    moves: [String] = ["e2e4"]
  ) throws -> SavedGame {
    var game = ChessGame()
    for uci in moves { _ = try game.makeMove(#require(ChessMove(uci: uci))) }
    var clock = GameClock(timeControl: TimeControl(initialSeconds: 180, incrementSeconds: 2))
    _ = clock.consume(12.5, by: .white)
    let bot = try defaultBot()
    return SavedGame(
      id: UUID(),
      createdAt: updatedAt,
      updatedAt: updatedAt,
      mode: .bot(id: try #require(bot.botID)),
      white: PlayerInfo(name: "You"),
      black: bot,
      timeControl: clock.timeControl,
      autoFlip: false,
      game: game,
      result: result,
      termination: result == .ongoing ? nil : .resignation,
      clock: clock
    )
  }

  // MARK: Game store

  @Test
  func unfinishedGameRoundTrip() async throws {
    try await withTemporaryDirectory { directory in
      let store = makeStore(in: directory)
      let saved = try makeGame()
      try await store.save(saved)
      let restored = try await makeStore(in: directory).unfinishedGame()
      #expect(restored == saved)
      #expect(restored?.clock.remaining(.white) == 167.5)
      #expect(restored?.humanColor == .white)
    }
  }

  @Test
  func savingOngoingGameReplacesOtherOngoingGame() async throws {
    try await withTemporaryDirectory { directory in
      let store = makeStore(in: directory)
      let first = try makeGame(updatedAt: Date(timeIntervalSince1970: 100))
      let second = try makeGame(updatedAt: Date(timeIntervalSince1970: 200))
      try await store.save(first)
      try await store.save(second)
      let all = try await store.allGames()
      #expect(all.map(\.id) == [second.id])
    }
  }

  @Test
  func finishedGamesAreKeptAndNotOfferedForResume() async throws {
    try await withTemporaryDirectory { directory in
      let store = makeStore(in: directory)
      var game = try makeGame()
      try await store.save(game)
      game.result = .blackWon
      game.termination = .resignation
      try await store.save(game)
      let unfinished = try await store.unfinishedGame()
      let all = try await store.allGames()
      #expect(unfinished == nil)
      #expect(all.map(\.result) == [.blackWon])
    }
  }

  @Test
  func archiveKeepsOnlyTheNewest200FinishedGames() async throws {
    try await withTemporaryDirectory { directory in
      let store = makeStore(in: directory)
      for second in 1...201 {
        let game = try makeGame(
          result: .draw,
          updatedAt: Date(timeIntervalSince1970: TimeInterval(second))
        )
        try await store.save(game)
      }
      let all = try await makeStore(in: directory).allGames()
      #expect(all.count == 200)
      #expect(all.first?.updatedAt == Date(timeIntervalSince1970: 201))
      #expect(all.last?.updatedAt == Date(timeIntervalSince1970: 2))
    }
  }

  @Test
  func unfinishedGameDoesNotCountAgainstTheArchiveLimit() async throws {
    try await withTemporaryDirectory { directory in
      let store = makeStore(in: directory)
      let unfinished = try makeGame(updatedAt: Date(timeIntervalSince1970: 1))
      try await store.save(unfinished)
      for second in 2...202 {
        let game = try makeGame(
          result: .draw,
          updatedAt: Date(timeIntervalSince1970: TimeInterval(second))
        )
        try await store.save(game)
      }
      let reread = makeStore(in: directory)
      let all = try await reread.allGames()
      #expect(all.count == 201)
      #expect(try await reread.unfinishedGame()?.id == unfinished.id)
    }
  }

  @Test
  func delete() async throws {
    try await withTemporaryDirectory { directory in
      let store = makeStore(in: directory)
      let game = try makeGame(result: .draw)
      try await store.save(game)
      try await store.delete(id: game.id)
      let all = try await makeStore(in: directory).allGames()
      #expect(all.isEmpty)
    }
  }

  @Test
  func pgnHasTagsAndResult() throws {
    let pgn = try makeGame(result: .blackWon).pgn
    let botName = try defaultBot().name
    #expect(pgn.contains("[White \"You\"]"))
    #expect(pgn.contains("[TimeControl \"180+2\"]"))
    #expect(pgn.contains("[Termination \"\(botName) won by resignation\"]"))
    #expect(pgn.contains("1. e4"))
    #expect(pgn.hasSuffix("0-1") || pgn.contains("0-1\n"))
  }

  @Test
  func unreadableArchiveIsNotOverwritten() async throws {
    try await withTemporaryDirectory { directory in
      let fileURL = directory.appending(component: GamePersistenceStore.fileName)
      let damaged = Data("[{\"id\": \"truncated".utf8)
      try damaged.write(to: fileURL)
      let store = GamePersistenceStore(fileURL: fileURL)

      await #expect(throws: DecodingError.self) { try await store.save(try makeGame()) }
      await #expect(throws: DecodingError.self) { try await store.delete(id: UUID()) }
      #expect(try Data(contentsOf: fileURL) == damaged)
    }
  }

  @Test
  func fileChangedBehindTheStoreIsNotReadAgain() async throws {
    try await withTemporaryDirectory { directory in
      let store = makeStore(in: directory)
      let first = try makeGame(result: .draw, updatedAt: Date(timeIntervalSince1970: 100))
      let second = try makeGame(result: .draw, updatedAt: Date(timeIntervalSince1970: 200))
      try await store.save(first)
      try Data("[]".utf8).write(to: archiveURL(in: directory))

      #expect(try await store.allGames().map(\.id) == [first.id])
      try await store.save(second)
      #expect(try await store.allGames().map(\.id) == [second.id, first.id])
      #expect(try await makeStore(in: directory).allGames().map(\.id) == [second.id, first.id])
    }
  }

  @Test
  func unreadableArchiveIsReadAgainOnEachAccess() async throws {
    try await withTemporaryDirectory { directory in
      let fileURL = archiveURL(in: directory)
      try FileManager.default.createDirectory(
        at: fileURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try Data("[{\"id\": \"truncated".utf8).write(to: fileURL)
      let store = makeStore(in: directory)
      await #expect(throws: DecodingError.self) { try await store.allGames() }

      try FileManager.default.removeItem(at: fileURL)
      let game = try makeGame(result: .draw)
      try await makeStore(in: directory).save(game)
      #expect(try await store.allGames().map(\.id) == [game.id])
    }
  }

  @Test
  func failedSaveLeavesTheArchiveAsTheFileHasIt() async throws {
    try await withTemporaryDirectory { directory in
      let store = makeStore(in: directory)
      let first = try makeGame(result: .draw, updatedAt: Date(timeIntervalSince1970: 100))
      let second = try makeGame(result: .draw, updatedAt: Date(timeIntervalSince1970: 200))
      let third = try makeGame(result: .draw, updatedAt: Date(timeIntervalSince1970: 300))
      try await store.save(first)
      // A directory in place of the file makes the next write fail.
      let fileURL = archiveURL(in: directory)
      try FileManager.default.removeItem(at: fileURL)
      try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)

      await #expect(throws: (any Error).self) { try await store.save(second) }
      #expect(try await store.allGames().map(\.id) == [first.id])

      try FileManager.default.removeItem(at: fileURL)
      try await store.save(third)
      #expect(try await store.allGames().map(\.id) == [third.id, first.id])
      #expect(try await makeStore(in: directory).allGames().map(\.id) == [third.id, first.id])
    }
  }

  // MARK: Stored format

  private func storedFormatCoders() -> (JSONEncoder, JSONDecoder) {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (encoder, decoder)
  }

  @Test
  func storedFormatFixtureLoads() async throws {
    try await withTemporaryDirectory { directory in
      let fileURL = directory.appending(component: GamePersistenceStore.fileName)
      try FileManager.default.copyItem(at: fixtureURL("saved-games.json"), to: fileURL)
      let store = GamePersistenceStore(fileURL: fileURL)

      let all = try await store.allGames()
      // Newest first.
      #expect(
        all.map(\.id.uuidString) == [
          "5B1C3F0E-6666-4A2B-9C3D-000000000006", "5B1C3F0E-3333-4A2B-9C3D-000000000003",
          "5B1C3F0E-1111-4A2B-9C3D-000000000001",
        ]
      )

      let passAndPlay = try #require(all.first { $0.mode == .passAndPlay })
      #expect(passAndPlay.humanColor == nil)
      #expect(passAndPlay.white.name == "Anna")
      #expect(passAndPlay.black.name == "Ben")
      #expect(passAndPlay.autoFlip)
      #expect(passAndPlay.result == .draw)
      #expect(passAndPlay.termination == .agreement)
      #expect(passAndPlay.timeControl == TimeControl(initialSeconds: 180, incrementSeconds: 2))
      #expect(passAndPlay.clock.remaining(.white) == 170.5)
      #expect(passAndPlay.clock.remaining(.black) == 95)
      #expect(passAndPlay.game.moves.map(\.move.uci) == ["a7a8q"])
      #expect(passAndPlay.game.moves.map(\.san) == ["a8=Q+"])
      #expect(passAndPlay.game.position.fen == "Q3k3/8/8/8/8/8/8/4K3 b - - 0 50")

      let online = try #require(
        all.first { $0.mode == .online(service: "lichess", gameID: "abcd1234") }
      )
      #expect(online.humanColor == .black)
      #expect(!online.white.isLocalUser && online.black.isLocalUser)
      #expect(online.white.rating == 1720)
      #expect(online.result == .blackWon)
      #expect(online.termination == .timeout)
      #expect(online.clock.remaining(.black) == 41.25)
      #expect(online.game.moves.map(\.san) == ["d5", "exd6"])
      #expect(online.game.moves[1].positionBefore.fen == "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 31")
      #expect(online.game.position.fen == "4k3/8/3P4/8/8/8/8/4K3 b - - 0 31")

      let botGame = try #require(all.first { $0.mode == .bot(id: "martin") })
      #expect(botGame.humanColor == .white)
      #expect(botGame.black.botID == "martin")
      #expect(botGame.black.rating == 250)
      #expect(botGame.result == .ongoing)
      #expect(botGame.termination == nil)
      #expect(botGame.game.initialPosition == .initial)

      let unfinished = try await store.unfinishedGame()
      #expect(unfinished?.id == botGame.id)
    }
  }

  /// The fixture's positions and SAN are the ones the rules produce for its moves.
  @Test
  func storedFormatFixtureReplays() throws {
    let (_, decoder) = storedFormatCoders()
    let games = try decoder.decode(
      [SavedGame].self,
      from: Data(contentsOf: fixtureURL("saved-games.json"))
    )
    for saved in games {
      var replayed = ChessGame(position: saved.game.initialPosition)
      for played in saved.game.moves {
        #expect(replayed.position.fen == played.positionBefore.fen)
        #expect(try replayed.makeMove(played.move).san == played.san)
      }
      #expect(replayed.position.fen == saved.game.position.fen)
    }
  }

  @Test
  func storedFormatFixtureRoundTrips() throws {
    let (encoder, decoder) = storedFormatCoders()
    let fixture = try Data(contentsOf: fixtureURL("saved-games.json"))
    let games = try decoder.decode([SavedGame].self, from: fixture)
    let encoded = try encoder.encode(games)
    #expect(try decoder.decode([SavedGame].self, from: encoded) == games)
    // Same keys and values as the hand-written file, so the format is defined once.
    func canonical(_ data: Data) throws -> Data {
      try JSONSerialization.data(
        withJSONObject: JSONSerialization.jsonObject(with: data),
        options: .sortedKeys
      )
    }
    #expect(try canonical(encoded) == canonical(fixture))
  }

  // MARK: Settings

  @Test
  func storedSettingsDecodeAndRoundTrip() throws {
    let catalog = try Shared.catalog
    let settings = try JSONDecoder().decode(
      AppSettings.self,
      from: Data(contentsOf: fixtureURL("settings-v1.json"))
    )
    #expect(
      try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings)) == settings
    )
    #expect(settings.boardTheme == "green")
    #expect(settings.pieceSet == "cburnett")
    #expect(settings.orientation == .black)
    #expect(!settings.soundEffects)
    #expect(!settings.showCoordinates)
    #expect(settings.autoPromoteToQueen)
    #expect(settings.playBotsBotID == nil)
    #expect(settings.playBotsColor == .white)
    // "green" has no catalog entry, so it resolves to the default.
    #expect(catalog.boardTheme(id: "green") == nil)
    #expect(settings.boardTheme(in: catalog)?.id == catalog.defaults.boardThemeID)
  }

  @MainActor
  @Test
  func settingsRoundTrip() throws {
    try withTemporaryDefaults { defaults in
      let first = SettingsStore(defaults: defaults)
      first.value.showCoordinates = false
      first.soundEffects = false
      first.value.playBotsColor = .random
      let second = SettingsStore(defaults: defaults)
      #expect(!second.value.showCoordinates)
      #expect(!second.soundEffects)
      #expect(!second.value.soundEffects)
      #expect(second.value.playBotsColor == .random)
      #expect(second.value == first.value)
    }
  }
}
