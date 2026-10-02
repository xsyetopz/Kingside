import ChessCore
import Foundation
import Testing

@testable import ChessPlay

/// A new game starts with fresh per-game state, and the opponent's presence moves through its
/// states as the server reports it.
@MainActor
@Suite(.timeLimit(.minutes(1)))
final class SessionStateTests {
  private let suiteName = "SessionStateTests.\(UUID().uuidString)"
  private let directory = FileManager.default.temporaryDirectory
    .appending(component: "SessionStateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  private let clock = TestClock()
  private let connection = FakeOnlineConnection()
  private let store: GamePersistenceStore

  init() {
    store = GamePersistenceStore(
      fileURL: directory.appending(components: "Kingside", GamePersistenceStore.fileName)
    )
  }

  deinit {
    UserDefaults.standard.removePersistentDomain(forName: suiteName)
    try? FileManager.default.removeItem(at: directory)
  }

  private func passAndPlay() throws -> GameSession {
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    return try GameSession(
      launch: .new(
        GameSetup(
          mode: .passAndPlay,
          white: PlayerInfo(name: "A"),
          black: PlayerInfo(name: "B"),
          timeControl: .untimed,
          autoFlip: false
        )
      ),
      engine: ChessEngine(),
      catalog: Shared.catalog,
      localization: Shared.english,
      settings: SettingsStore(defaults: defaults),
      store: store,
      clock: clock
    )
  }

  private func online() throws -> OnlineGameSession {
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let session = try OnlineGameSession(
      connection: connection,
      catalog: Shared.catalog,
      localization: Shared.english,
      settings: SettingsStore(defaults: defaults),
      store: store,
      clock: clock
    )
    session.activate()
    connection.push(started("abcd1234", OnlineGameState(uciMoves: ["e2e4", "e7e5"])))
    return session
  }

  private func started(_ gameID: String, _ state: OnlineGameState) -> OnlineGameEvent {
    .started(
      OnlineGameStart(
        gameID: gameID,
        white: OnlinePlayer(name: "Alice", rating: 1500),
        black: OnlinePlayer(name: "Bob", rating: 1600),
        myColor: .white,
        timeControl: nil,
        state: state
      )
    )
  }

  /// A regular file where the store's directory should be makes every write fail.
  private func makeSavesFail() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data().write(to: directory.appending(component: "Kingside"))
  }

  /// Yields until `condition` holds; the suite's time limit cancels a wait that never does.
  private func until(_ condition: () -> Bool) async throws {
    while !condition() {
      try Task.checkCancellation()
      await Task.yield()
    }
  }

  private func play(_ uci: String, in session: GameSession) throws {
    let move = try #require(ChessMove(uci: uci))
    session.apply(.select(move.from))
    session.apply(.select(move.to))
  }

  @Test
  func rematchClearsASaveFailure() async throws {
    try makeSavesFail()
    let session = try passAndPlay()
    try play("e2e4", in: session)
    await session.flushPendingSave()
    #expect(session.showsSaveFailure)

    session.apply(.rematch)
    #expect(!session.showsSaveFailure)
  }

  @Test
  func rematchReportsANewSaveFailureAgain() async throws {
    try makeSavesFail()
    let session = try passAndPlay()
    try play("e2e4", in: session)
    await session.flushPendingSave()
    session.showsSaveFailure = false

    session.apply(.rematch)
    try play("e2e4", in: session)
    await session.flushPendingSave()
    #expect(session.showsSaveFailure)
  }

  @Test
  func saveFailingAfterARematchIsNotReportedForTheNewGame() async throws {
    try makeSavesFail()
    let session = try passAndPlay()
    try play("e2e4", in: session)
    // The save task runs on the main actor, so it cannot start before the rematch.
    session.apply(.rematch)
    await session.flushPendingSave()
    #expect(!session.showsSaveFailure)
  }

  @Test
  func opponentGoesGoneThenClaimableThenPresent() async throws {
    let session = try online()
    try await until { session.start != nil }
    #expect(session.opponentPresence == .present)

    connection.push(.opponentGone(claimWinIn: .seconds(10)))
    try await until { session.opponentPresence != .present }
    #expect(session.opponentPresence == .gone)

    // The clock ticker and the claim timer both sleep.
    try await until { clock.sleeperCount == 2 }
    clock.advance(by: .seconds(10))
    try await until { session.opponentPresence == .claimable }

    connection.push(.opponentBack)
    try await until { session.opponentPresence == .present }
    #expect(!session.canClaimVictory)
  }

  @Test
  func opponentGoneWithoutAClaimIsNeverClaimable() async throws {
    let session = try online()
    try await until { session.start != nil }
    connection.push(.opponentGone(claimWinIn: nil))
    try await until { session.opponentPresence == .gone }
    #expect(!session.canClaimVictory)
  }

  @Test
  func reconnectToTheSameGameKeepsAReportedSaveFailure() async throws {
    try makeSavesFail()
    let session = try online()
    connection.push(.state(OnlineGameState(uciMoves: ["e2e4", "e7e5"], status: .resign)))
    try await until { session.isGameOver }
    await session.flushPendingSave()
    #expect(session.showsSaveFailure)

    connection.push(started("abcd1234", OnlineGameState(uciMoves: ["e2e4"], status: .resign)))
    try await until { session.game.moves.count == 1 }
    #expect(session.showsSaveFailure)
  }

  @Test
  func newGameReportsASaveFailureAgain() async throws {
    try makeSavesFail()
    let session = try online()
    connection.push(.state(OnlineGameState(uciMoves: ["e2e4", "e7e5"], status: .resign)))
    try await until { session.isGameOver }
    await session.flushPendingSave()
    session.showsSaveFailure = false

    connection.push(started("efgh5678", OnlineGameState(uciMoves: ["e2e4"], status: .resign)))
    try await until { session.start?.gameID == "efgh5678" }
    await session.flushPendingSave()
    #expect(session.showsSaveFailure)
  }

  @Test
  func gameStartedAgainAfterAnotherReportsASaveFailureAgain() async throws {
    try makeSavesFail()
    let session = try online()
    connection.push(.state(OnlineGameState(uciMoves: ["e2e4", "e7e5"], status: .resign)))
    try await until { session.isGameOver }
    await session.flushPendingSave()
    session.showsSaveFailure = false

    connection.push(started("efgh5678", OnlineGameState(uciMoves: ["e2e4"], status: .resign)))
    try await until { session.start?.gameID == "efgh5678" }
    await session.flushPendingSave()
    session.showsSaveFailure = false

    connection.push(started("abcd1234", OnlineGameState(uciMoves: ["e2e4"], status: .resign)))
    try await until { session.start?.gameID == "abcd1234" }
    await session.flushPendingSave()
    #expect(session.showsSaveFailure)
  }

  @Test
  func saveFailingAfterTheNextGameStartedIsNotReportedForIt() async throws {
    try makeSavesFail()
    let session = try online()
    try await until { session.start != nil }
    // Pushed together so that the next game starts while the finished game's save still runs.
    connection.push(.state(OnlineGameState(uciMoves: ["e2e4", "e7e5"], status: .resign)))
    connection.push(started("efgh5678", OnlineGameState(uciMoves: ["e2e4"])))
    try await until { session.start?.gameID == "efgh5678" }
    await session.flushPendingSave()
    #expect(!session.showsSaveFailure)
  }
}
