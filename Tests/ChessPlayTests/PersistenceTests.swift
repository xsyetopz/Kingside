import ChessContent
import ChessCore
import Foundation
import Testing

@testable import ChessPlay

@Suite
struct PersistenceTests {
  private func makeStore(in directory: URL) -> GamePersistenceStore {
    GamePersistenceStore(
      fileURL: directory.appending(components: "Kingside", GamePersistenceStore.fileName)
    )
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
      let restored = try await store.unfinishedGame()
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
  func delete() async throws {
    try await withTemporaryDirectory { directory in
      let store = makeStore(in: directory)
      let game = try makeGame(result: .draw)
      try await store.save(game)
      try await store.delete(id: game.id)
      let all = try await store.allGames()
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
  func legacyArchiveFileLoads() async throws {
    try await withTemporaryDirectory { directory in
      let fileURL = directory.appending(component: GamePersistenceStore.fileName)
      try FileManager.default.copyItem(at: fixtureURL("saved-games-v2.json"), to: fileURL)
      let store = GamePersistenceStore(fileURL: fileURL)

      let all = try await store.allGames()
      #expect(all.count == 2)
      // Newest first.
      #expect(
        all.map(\.id.uuidString) == [
          "5B1C3F0E-3333-4A2B-9C3D-000000000003", "5B1C3F0E-1111-4A2B-9C3D-000000000001",
        ]
      )

      let passAndPlay = try #require(all.first { $0.mode == .passAndPlay })
      #expect(passAndPlay.humanColor == nil)
      #expect(passAndPlay.white.name == "Anna")
      #expect(passAndPlay.black.name == "Ben")
      #expect(passAndPlay.result == .draw)
      #expect(passAndPlay.termination == .agreement)
      #expect(passAndPlay.timeControl == TimeControl(initialSeconds: 180, incrementSeconds: 2))
      #expect(passAndPlay.clock.remaining(.white) == 170.5)
      #expect(passAndPlay.clock.remaining(.black) == 95)
      #expect(passAndPlay.game.moves.map(\.san) == ["Ra8+"])

      let botGame = try #require(all.first { $0.mode == .bot(id: "martin") })
      #expect(botGame.humanColor == .black)
      #expect(botGame.white.rating == 250)
      #expect(botGame.result == .ongoing)
      #expect(botGame.termination == nil)

      let unfinished = try await store.unfinishedGame()
      #expect(unfinished?.id == botGame.id)
    }
  }

  // MARK: Settings

  @Test
  func legacySettingsDecode() throws {
    let catalog = try Shared.catalog
    let settings = try JSONDecoder().decode(
      AppSettings.self,
      from: Data(contentsOf: fixtureURL("settings-v1.json"))
    )
    #expect(settings.boardTheme == "green")
    #expect(settings.pieceSet == "cburnett")
    #expect(settings.orientation == .black)
    #expect(!settings.soundEffects)
    #expect(!settings.showCoordinates)
    #expect(settings.autoPromoteToQueen)
    #expect(settings.playBotsBotID == nil)
    #expect(settings.playBotsColor == .white)
    // "green" is an old theme name with no catalog entry, so it resolves to the default.
    #expect(catalog.boardTheme(id: "green") == nil)
    #expect(settings.boardTheme(in: catalog)?.id == catalog.defaults.boardThemeID)
  }

  @MainActor
  @Test
  func settingsRoundTrip() throws {
    try withTemporaryDefaults { defaults in
      let first = SettingsStore(defaults: defaults)
      first.value.showCoordinates = false
      first.soundEnabled = false
      first.value.playBotsColor = .random
      let second = SettingsStore(defaults: defaults)
      #expect(!second.value.showCoordinates)
      #expect(!second.soundEnabled)
      #expect(!second.value.soundEffects)
      #expect(second.value.playBotsColor == .random)
      #expect(second.value == first.value)
    }
  }
}
