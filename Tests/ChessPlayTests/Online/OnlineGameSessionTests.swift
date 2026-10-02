import ChessContent
import ChessCore
import Foundation
import Testing

@testable import ChessPlay

@MainActor
@Suite(.timeLimit(.minutes(1)))
final class OnlineGameSessionTests {
  private let suiteName = "OnlineGameSessionTests.\(UUID().uuidString)"
  private let directory = FileManager.default.temporaryDirectory
    .appending(
      component: "OnlineGameSessionTests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
  private let sink = RecordingFeedbackSink()
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

  private func makeSession() throws -> OnlineGameSession {
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let session = try OnlineGameSession(
      connection: connection,
      catalog: Shared.catalog,
      localization: Shared.english,
      settings: SettingsStore(defaults: defaults),
      store: store,
      feedback: sink,
      clock: clock
    )
    session.activate()
    return session
  }

  private func start(
    _ moves: [String] = [],
    myColor: PieceColor = .white,
    timeControl: TimeControl? = nil,
    status: OnlineGameStatus = .started
  ) -> OnlineGameStart {
    OnlineGameStart(
      gameID: "abcd1234",
      white: OnlinePlayer(name: "Alice", rating: 1500),
      black: OnlinePlayer(name: "Bob", rating: 1600),
      myColor: myColor,
      timeControl: timeControl,
      state: OnlineGameState(uciMoves: moves, status: status)
    )
  }

  /// Yields until `condition` holds; the suite's time limit cancels a wait that never does.
  private func until(_ condition: () -> Bool) async throws {
    while !condition() {
      try Task.checkCancellation()
      await Task.yield()
    }
  }

  private func play(_ uci: String, in session: OnlineGameSession) throws {
    let move = try #require(ChessMove(uci: uci))
    session.apply(.select(move.from))
    session.apply(.select(move.to))
  }

  private var moveSounds: Int {
    sink.events.filter { if case .moved = $0 { true } else { false } }.count
  }

  // MARK: Start and reconnect

  @Test
  func startedReplaysMovesWithoutMoveFeedback() async throws {
    let session = try makeSession()
    connection.push(.started(start(["e2e4", "e7e5"])))
    try await until { session.start != nil }

    #expect(session.game.moves.map(\.move.uci) == ["e2e4", "e7e5"])
    #expect(moveSounds == 0)
    #expect(!sink.events.contains(.gameStarted))
    #expect(session.canMove)
    #expect(session.humanColor == .white)
    #expect(session.white.isLocalUser && !session.black.isLocalUser)
    #expect(session.snapshot.lastMove == ChessMove(uci: "e7e5"))
  }

  @Test
  func newGameWithoutMovesAnnouncesStart() async throws {
    let session = try makeSession()
    connection.push(.started(start()))
    try await until { session.start != nil }
    #expect(sink.events == [.gameStarted])
  }

  @Test
  func reconnectReplacesStateWithoutReplayFeedback() async throws {
    let session = try makeSession()
    connection.push(.started(start(["e2e4"], myColor: .black)))
    try await until { session.start != nil }
    session.deactivate()
    session.activate()
    #expect(connection.streams == 2)

    connection.push(.started(start(["e2e4", "e7e5", "g1f3"], myColor: .black)))
    try await until { session.game.moves.count == 3 }
    #expect(moveSounds == 0)
    #expect(session.canMove)
  }

  // MARK: Moves

  @Test
  func playerMoveIsSentAsUCIAndConfirmed() async throws {
    let session = try makeSession()
    connection.push(.started(start()))
    try await until { session.start != nil }

    try play("e2e4", in: session)
    #expect(session.pendingMove == "e2e4")
    #expect(!session.canMove)
    try await until { connection.sent == [.move("e2e4")] }

    connection.push(.state(OnlineGameState(uciMoves: ["e2e4"])))
    try await until { session.pendingMove == nil }
    #expect(session.game.moves.map(\.move.uci) == ["e2e4"])

    connection.push(.state(OnlineGameState(uciMoves: ["e2e4", "c7c5"])))
    try await until { session.game.moves.count == 2 }
    #expect(session.canMove)
    #expect(moveSounds == 2)
  }

  @Test
  func stateWithoutPendingMoveKeepsIt() async throws {
    let session = try makeSession()
    connection.push(.started(start()))
    try await until { session.start != nil }
    try play("e2e4", in: session)

    // A state sent before the server saw the move, such as a draw-offer change.
    connection.push(.state(OnlineGameState(uciMoves: [], blackOffersDraw: true)))
    try await until { session.pendingDrawOffer == .black }
    #expect(session.pendingMove == "e2e4")
    #expect(session.game.moves.count == 1)
  }

  @Test
  func failedSendRollsBackToServerState() async throws {
    let session = try makeSession()
    connection.push(.started(start(["e2e4", "e7e5"])))
    try await until { session.start != nil }
    connection.setFailsSends(true)

    try play("g1f3", in: session)
    try await until { session.pendingMove == nil }
    #expect(session.game.moves.map(\.move.uci) == ["e2e4", "e7e5"])
    #expect(sink.events.last == .illegalMove)
    #expect(session.canMove)
  }

  @Test
  func inputIsIgnoredOnOpponentsTurn() async throws {
    let session = try makeSession()
    connection.push(.started(start(myColor: .black)))
    try await until { session.start != nil }
    #expect(!session.canMove)
    try play("e2e4", in: session)
    #expect(session.game.moves.isEmpty)
    #expect(connection.sent.isEmpty)
  }

  // MARK: Clock

  @Test
  func clockFollowsServerAndCountsDownLocally() async throws {
    let session = try makeSession()
    let control = TimeControl(initialSeconds: 180, incrementSeconds: 2)
    connection.push(.started(start(timeControl: control)))
    try await until { session.start != nil }

    connection.push(
      .state(
        OnlineGameState(
          uciMoves: ["e2e4", "e7e5"],
          whiteTime: .seconds(170),
          blackTime: .seconds(175)
        )
      )
    )
    try await until { session.game.moves.count == 2 }
    #expect(session.clock.remaining(.white) == 170)
    #expect(session.clock.remaining(.black) == 175)
    #expect(session.activeClockColor == .white)

    let tick = try Shared.catalog.tuning.clock.tickInterval
    await clock.waitForSleeper()
    clock.advance(by: tick)
    try await until { session.clock.remaining(.white) < 170 }
    #expect(session.clock.remaining(.white) == 169.9)
    #expect(session.clock.remaining(.black) == 175)
  }

  // MARK: Endings

  @Test(arguments: [
    (
      ["f2f3", "e7e5", "g2g4", "d8h4"], OnlineGameStatus.mate, PieceColor.black,
      GameResult.blackWon, GameTermination.checkmate
    ),
    (["e2e4"], .resign, .white, .whiteWon, .resignation),
    (["e2e4", "e7e5"], .outoftime, .black, .blackWon, .timeout),
  ])
  func finishedGameIsAnnouncedAndSavedOnce(
    moves: [String],
    status: OnlineGameStatus,
    winner: PieceColor,
    result: GameResult,
    termination: GameTermination
  ) async throws {
    let session = try makeSession()
    connection.push(.started(start()))
    try await until { session.start != nil }

    let final = OnlineGameState(uciMoves: moves, status: status, winner: winner)
    connection.push(.state(final))
    try await until { session.isGameOver }
    connection.push(.state(final))
    try await until { session.game.moves.count == moves.count }
    await session.flushPendingSave()

    #expect(session.result == result)
    #expect(session.termination == termination)
    #expect(session.activeClockColor == nil)
    #expect(!session.canMove)
    #expect(sink.events.filter { $0 == .gameOver(result) }.count == 1)

    let saved = try await store.allGames()
    #expect(saved.count == 1)
    let game = try #require(saved.first)
    #expect(game.id == OnlineGameSession.savedGameID(service: "lichess", gameID: "abcd1234"))
    #expect(game.mode == .online(service: "lichess", gameID: "abcd1234"))
    #expect(game.result == result)
    #expect(game.humanColor == .white)
    #expect(game.game.moves.map(\.move.uci) == moves)
  }

  @Test
  func abortedGameEndsWithoutSaving() async throws {
    let session = try makeSession()
    connection.push(.started(start()))
    try await until { session.start != nil }
    #expect(session.canAbort)
    session.abort()
    try await until { connection.sent == [.abort] }

    connection.push(.state(OnlineGameState(status: .aborted)))
    try await until { session.isGameOver }
    await session.flushPendingSave()
    #expect(session.result == .ongoing)
    #expect(!session.canAbort)
    #expect(try await store.allGames().isEmpty)
  }

  @Test
  func finishedGameOnConnectIsSavedButNotAnnounced() async throws {
    let session = try makeSession()
    connection.push(.started(start(["e2e4"], status: .resign)))
    try await until { session.start != nil }
    await session.flushPendingSave()
    #expect(sink.events.isEmpty)
    #expect(try await store.allGames().count == 1)
  }

  // MARK: Draws and leaving

  @Test
  func opponentDrawOfferCanBeAccepted() async throws {
    let session = try makeSession()
    connection.push(.started(start(["e2e4", "e7e5"])))
    try await until { session.start != nil }

    connection.push(.state(OnlineGameState(uciMoves: ["e2e4", "e7e5"], blackOffersDraw: true)))
    try await until { session.pendingDrawOffer == .black }
    session.apply(.acceptDraw)
    #expect(session.pendingDrawOffer == nil)
    try await until { connection.sent == [.acceptDraw] }

    connection.push(.state(OnlineGameState(uciMoves: ["e2e4", "e7e5"], status: .draw)))
    try await until { session.isGameOver }
    #expect(session.result == .draw)
    #expect(session.termination == .agreement)
  }

  @Test
  func opponentDeclineClearsOurDrawOffer() async throws {
    let session = try makeSession()
    connection.push(.started(start(["e2e4", "e7e5"])))
    try await until { session.start != nil }

    session.apply(.offerDraw)
    #expect(session.myDrawOfferPending)
    try await until { connection.sent == [.offerDraw] }
    connection.push(.state(OnlineGameState(uciMoves: ["e2e4", "e7e5"], whiteOffersDraw: true)))
    // Events arrive in order, so the chat line proves the offer state was handled.
    connection.push(.chat(OnlineChatLine(username: "lichess", text: "Draw offer sent")))
    try await until { !session.chat.isEmpty }
    #expect(session.myDrawOfferPending)

    connection.push(.state(OnlineGameState(uciMoves: ["e2e4", "e7e5"])))
    try await until { !session.myDrawOfferPending }
    #expect(!session.isGameOver)
    #expect(session.pendingDrawOffer == nil)
  }

  @Test
  func failedDrawOfferIsReverted() async throws {
    let session = try makeSession()
    connection.push(.started(start(["e2e4", "e7e5"])))
    try await until { session.start != nil }
    connection.setFailsSends(true)

    session.apply(.offerDraw)
    #expect(session.myDrawOfferPending)
    try await until { !session.myDrawOfferPending }
    #expect(connection.sent == [.offerDraw])
  }

  @Test
  func claimVictoryAfterOpponentLeaves() async throws {
    let session = try makeSession()
    connection.push(.started(start(["e2e4", "e7e5"])))
    try await until { session.start != nil }

    connection.push(.opponentGone(claimWinIn: .seconds(10)))
    try await until { session.opponentGone }
    #expect(!session.canClaimVictory)
    try await until { clock.sleeperCount == 2 }
    clock.advance(by: .seconds(10))
    try await until { session.canClaimVictory }
    session.claimVictory()
    try await until { connection.sent == [.claimVictory] }

  }

  @Test
  func opponentBackWithdrawsTheClaim() async throws {
    let session = try makeSession()
    connection.push(.started(start(["e2e4", "e7e5"])))
    try await until { session.start != nil }
    connection.push(.opponentGone(claimWinIn: .zero))
    try await until { session.canClaimVictory }

    connection.push(.opponentBack)
    try await until { !session.opponentGone }
    #expect(!session.canClaimVictory)
  }

  // MARK: Chat

  private func pushChat(_ lines: [(String, String)], to session: OnlineGameSession) async throws {
    let before = session.chat.count
    for (name, text) in lines {
      connection.push(.chat(OnlineChatLine(username: name, text: text)))
    }
    try await until { session.chat.count == before + lines.count }
  }

  @Test
  func unreadChatCountsLinesFromOthersOnly() async throws {
    let session = try makeSession()
    connection.push(.started(start()))
    try await until { session.start != nil }

    try await pushChat(
      [("Bob", "hi"), ("Alice", "hello"), ("lichess", "Draw offer sent")],
      to: session
    )
    #expect(session.unreadChatCount == 2)
  }

  @Test
  func markChatReadCountsOnlyLaterLines() async throws {
    let session = try makeSession()
    connection.push(.started(start()))
    try await until { session.start != nil }
    try await pushChat([("Bob", "hi"), ("Bob", "there")], to: session)

    session.markChatRead()
    #expect(session.unreadChatCount == 0)
    try await pushChat([("Bob", "again")], to: session)
    #expect(session.unreadChatCount == 1)
  }

  @Test
  func mutingHidesOpponentLinesAndTheirUnreadCount() async throws {
    let session = try makeSession()
    connection.push(.started(start()))
    try await until { session.start != nil }
    try await pushChat([("Bob", "hi"), ("Alice", "hello")], to: session)

    session.setOpponentMuted(true)
    #expect(session.chatMessages.map(\.text) == ["hello"])
    #expect(session.unreadChatCount == 0)
    session.setOpponentMuted(false)
    #expect(session.chatMessages.map(\.text) == ["hi", "hello"])
    #expect(session.unreadChatCount == 1)
  }

  // MARK: Connection errors

  @Test
  func failedStreamSetsConnectionError() async throws {
    let session = try makeSession()
    connection.push(.started(start()))
    try await until { session.start != nil }
    #expect(!session.connectionError)

    connection.fail()
    try await until { session.connectionError }
  }

  @Test
  func reactivatingAfterAnErrorClearsConnectionError() async throws {
    let session = try makeSession()
    connection.fail()
    try await until { session.connectionError }

    session.activate()
    #expect(!session.connectionError)
    #expect(connection.streams == 2)
  }

  @Test
  func startWithUnreadableFENSetsConnectionError() async throws {
    let session = try makeSession()
    let broken = OnlineGameStart(
      gameID: "abcd1234",
      initialFEN: "not a fen",
      white: OnlinePlayer(name: "Alice", rating: 1500),
      black: OnlinePlayer(name: "Bob", rating: 1600),
      myColor: .white,
      timeControl: nil,
      state: OnlineGameState()
    )
    connection.push(.started(broken))
    try await until { session.connectionError }
    #expect(session.start == nil)
  }

  // MARK: Persistence types

  @Test
  func onlineModeAndLocalUserRoundTrip() throws {
    let mode = GameMode.online(service: "lichess", gameID: "abcd1234")
    #expect(try JSONDecoder().decode(GameMode.self, from: JSONEncoder().encode(mode)) == mode)

    let me = PlayerInfo(name: "Bob", rating: 1600, isLocalUser: true)
    let decoded = try JSONDecoder().decode(PlayerInfo.self, from: JSONEncoder().encode(me))
    #expect(decoded.isLocalUser)
    #expect(mode.humanColor(white: PlayerInfo(name: "Alice"), black: decoded) == .black)
    #expect(
      mode.humanColor(white: PlayerInfo(name: "Alice"), black: PlayerInfo(name: "Bob")) == nil
    )
  }

  @Test
  func savedGameIDIsStable() {
    let first = OnlineGameSession.savedGameID(service: "lichess", gameID: "abcd1234")
    #expect(first.uuidString == "2D1C127E-7629-8DBA-89F0-B5A88C81CE29")
    #expect(first != OnlineGameSession.savedGameID(service: "lichess", gameID: "abcd1235"))
  }
}
