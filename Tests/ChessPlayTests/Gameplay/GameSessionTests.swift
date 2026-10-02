import ChessContent
import ChessCore
import Foundation
import Testing

@testable import ChessPlay

/// A clock that only moves when a test calls `advance(by:)`.
final class TestClock: Clock, @unchecked Sendable {
  struct Instant: InstantProtocol {
    var offset: Duration
    func advanced(by duration: Duration) -> Self { Self(offset: offset + duration) }
    func duration(to other: Self) -> Duration { other.offset - offset }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.offset < rhs.offset }
  }

  private struct Sleeper {
    let deadline: Instant
    let continuation: CheckedContinuation<Void, any Error>
  }

  private let lock = NSLock()
  private var current = Instant(offset: .zero)
  private var sleepers: [UUID: Sleeper] = [:]
  private var cancelled: Set<UUID> = []

  var now: Instant { lock.withLock { current } }
  var minimumResolution: Duration { .zero }
  var hasSleepers: Bool { lock.withLock { !sleepers.isEmpty } }
  var sleeperCount: Int { lock.withLock { sleepers.count } }

  func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
    let id = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation {
        (continuation: CheckedContinuation<Void, any Error>) in
        let result: Result<Void, any Error>? = lock.withLock {
          if cancelled.remove(id) != nil { return .failure(CancellationError()) }
          if deadline <= current { return .success(()) }
          sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
          return nil
        }
        if let result { continuation.resume(with: result) }
      }
    } onCancel: {
      let sleeper = lock.withLock {
        let sleeper = sleepers.removeValue(forKey: id)
        if sleeper == nil { cancelled.insert(id) }
        return sleeper
      }
      sleeper?.continuation.resume(throwing: CancellationError())
    }
  }

  /// Moves time forward and wakes every sleeper whose deadline has passed.
  func advance(by duration: Duration) {
    let due = lock.withLock {
      current = current.advanced(by: duration)
      let due = sleepers.filter { $0.value.deadline <= current }
      for id in due.keys { sleepers[id] = nil }
      return due.values.map(\.continuation)
    }
    for continuation in due { continuation.resume() }
  }

  /// Returns once some task sleeps on this clock.
  func waitForSleeper() async {
    while !hasSleepers { await Task.yield() }
  }
}

/// Records every feedback event and lets a test await one.
@MainActor
final class RecordingFeedbackSink: FeedbackSink {
  private(set) var events: [FeedbackEvent] = []
  private var waiters:
    [(matches: ([FeedbackEvent]) -> Bool, continuation: CheckedContinuation<Void, Never>)] = []

  func receive(_ event: FeedbackEvent) {
    events.append(event)
    let ready = waiters.filter { $0.matches(events) }
    waiters.removeAll { $0.matches(events) }
    for waiter in ready { waiter.continuation.resume() }
  }

  /// Returns once the recorded events satisfy `condition`.
  func wait(until condition: @escaping ([FeedbackEvent]) -> Bool) async {
    if condition(events) { return }
    await withCheckedContinuation { waiters.append((condition, $0)) }
  }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
final class GameSessionTests {
  private let suiteName = "GameSessionTests.\(UUID().uuidString)"
  private let directory = FileManager.default.temporaryDirectory
    .appending(component: "GameSessionTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  private let engine = ChessEngine()
  private let sink = RecordingFeedbackSink()
  private let clock = TestClock()
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

  private func makeSession(
    _ launch: GameLaunch,
    autoPromoteToQueen: Bool = false
  ) throws -> GameSession {
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    let settings = SettingsStore(defaults: defaults)
    settings.value.autoPromoteToQueen = autoPromoteToQueen
    return try GameSession(
      launch: launch,
      engine: engine,
      catalog: Shared.catalog,
      localization: Shared.english,
      settings: settings,
      store: store,
      feedback: sink,
      clock: clock
    )
  }

  private func passAndPlay(
    _ timeControl: TimeControl = .untimed,
    autoFlip: Bool = false
  ) -> GameLaunch {
    .new(
      GameSetup(
        mode: .passAndPlay,
        white: PlayerInfo(name: "A"),
        black: PlayerInfo(name: "B"),
        timeControl: timeControl,
        autoFlip: autoFlip
      )
    )
  }

  /// An ongoing pass-and-play game that starts from `fen`.
  private func savedPassAndPlay(fen: String, moves: [String] = []) throws -> GameLaunch {
    var game = ChessGame(position: try ChessPosition(fen: fen))
    for uci in moves { _ = try game.makeMove(#require(ChessMove(uci: uci))) }
    return .saved(
      SavedGame(
        id: UUID(),
        createdAt: Date(),
        updatedAt: Date(),
        mode: .passAndPlay,
        white: PlayerInfo(name: "A"),
        black: PlayerInfo(name: "B"),
        timeControl: .untimed,
        autoFlip: false,
        game: game,
        result: .ongoing,
        termination: nil,
        clock: GameClock(timeControl: .untimed)
      )
    )
  }

  /// The human plays White against `botID`.
  private func botGame(_ botID: String) throws -> GameLaunch {
    let bot = try #require(try Shared.catalog.bots.bot(id: botID))
    return .new(
      GameSetup(
        mode: .bot(id: botID),
        white: PlayerInfo(name: "You"),
        black: PlayerInfo(bot: bot, localization: Shared.english),
        timeControl: .untimed
      )
    )
  }

  /// The human plays Black against `botID`; the bot has White.
  private func botGameAsBlack(_ botID: String) throws -> GameLaunch {
    let bot = try #require(try Shared.catalog.bots.bot(id: botID))
    return .new(
      GameSetup(
        mode: .bot(id: botID),
        white: PlayerInfo(bot: bot, localization: Shared.english),
        black: PlayerInfo(name: "You"),
        timeControl: .untimed
      )
    )
  }

  /// An ongoing game against `botID` that starts from `fen`; the human plays White.
  private func savedBotGame(_ botID: String, fen: String) throws -> GameLaunch {
    let bot = try #require(try Shared.catalog.bots.bot(id: botID))
    return .saved(
      SavedGame(
        id: UUID(),
        createdAt: Date(),
        updatedAt: Date(),
        mode: .bot(id: botID),
        white: PlayerInfo(name: "You"),
        black: PlayerInfo(bot: bot, localization: Shared.english),
        timeControl: .untimed,
        autoFlip: false,
        game: ChessGame(position: try ChessPosition(fen: fen)),
        result: .ongoing,
        termination: nil,
        clock: GameClock(timeControl: .untimed)
      )
    )
  }

  private static let promotionFEN = "4k3/1P5p/8/8/8/8/8/4K3 w - - 0 1"

  private func square(_ name: String) throws -> Square { try #require(Square(algebraic: name)) }

  private func play(_ moves: [String], in session: GameSession) throws {
    for uci in moves {
      let move = try #require(ChessMove(uci: uci))
      session.apply(.select(move.from))
      session.apply(.select(move.to))
    }
  }

  @Test
  func selectThenMoveUpdatesSnapshot() throws {
    let session = try makeSession(passAndPlay())
    let e2 = try square("e2"), e4 = try square("e4")

    session.apply(.select(e2))
    #expect(session.snapshot.selectedSquare == e2)
    #expect(session.snapshot.legalTargets == [try square("e3"), e4])

    session.apply(.select(e4))
    let snapshot = session.snapshot
    #expect(snapshot.lastMove == ChessMove(from: e2, to: e4))
    #expect(snapshot.selectedSquare == nil)
    #expect(snapshot.legalTargets.isEmpty)
    #expect(snapshot.pieces[e4] == Piece(type: .pawn, color: .white))
    #expect(session.game.position.sideToMove == .black)
    #expect(sink.events == [.moved(.move)])
  }

  @Test
  func illegalTargetReportsAndKeepsPosition() throws {
    let session = try makeSession(passAndPlay())
    session.apply(.select(try square("e2")))
    session.apply(.select(try square("e5")))

    #expect(sink.events == [.illegalMove])
    #expect(session.game.position == .initial)
    #expect(session.game.moves.isEmpty)
    #expect(session.snapshot.selectedSquare == nil)
  }

  @Test
  func promotionWaitsForChoice() throws {
    let session = try makeSession(try savedPassAndPlay(fen: Self.promotionFEN))
    let b7 = try square("b7"), b8 = try square("b8")

    session.apply(.select(b7))
    session.apply(.select(b8))
    let pending = try #require(session.snapshot.pendingPromotion)
    #expect(pending.from == b7 && pending.to == b8 && pending.color == .white)
    #expect(Set(pending.choices) == [.queen, .rook, .bishop, .knight])
    #expect(!session.snapshot.isInputEnabled)
    #expect(session.game.moves.isEmpty)

    session.apply(.promote(.knight))
    #expect(session.snapshot.pendingPromotion == nil)
    #expect(session.game.position[b8] == Piece(type: .knight, color: .white))
    #expect(sink.events == [.moved(.promote)])
  }

  @Test
  func botRepliesToHumanMove() async throws {
    let session = try makeSession(try botGame("pip"))
    session.activate()
    try play(["e2e4"], in: session)
    #expect(session.isBotThinking)
    #expect(!session.snapshot.isInputEnabled)
    // Past the bot's minimum think time, so it replies as soon as the engine has a move.
    clock.advance(by: .seconds(60))

    await sink.wait { $0.filter { if case .moved = $0 { true } else { false } }.count == 2 }
    #expect(session.game.moves.count == 2)
    #expect(session.game.position.sideToMove == .white)
    #expect(!session.isBotThinking)
    #expect(session.snapshot.isInputEnabled)
    session.deactivate()
  }

  @Test
  func rematchRestartsTheBotOnTheNewGame() async throws {
    let session = try makeSession(try botGame("pip"))
    session.activate()
    try play(["e2e4"], in: session)
    #expect(session.isBotThinking)

    session.apply(.rematch)
    #expect(session.game.moves.isEmpty)
    #expect(session.humanColor == .black)
    #expect(session.isBotThinking)
    // The new search replies as White, not to the abandoned game.
    clock.advance(by: .seconds(60))
    await sink.wait { $0.filter { if case .moved = $0 { true } else { false } }.count == 2 }
    session.deactivate()
    await session.flushPendingSave()
    let saved = try #require(try await store.allGames().first)
    #expect(saved.id == session.id)
    #expect(saved.game.moves.count == 1)
  }

  @Test
  func rematchCancelsTheAbandonedBotReply() async throws {
    let session = try makeSession(try botGame("pip"))
    session.activate()
    try play(["e2e4"], in: session)
    await clock.waitForSleeper()

    session.apply(.rematch)
    // The new game's bot task has not run yet, so any sleeper left is the old reply.
    #expect(clock.sleeperCount == 0)
  }

  /// A one-minute pass-and-play game in which White's flag falls.
  private func whiteRunsOutOfTime() async throws -> GameSession {
    let session = try makeSession(passAndPlay(TimeControl(initialSeconds: 60, incrementSeconds: 0)))
    session.activate()
    try play(["e2e4", "e7e5"], in: session)
    await clock.waitForSleeper()

    clock.advance(by: .seconds(61))
    await sink.wait { $0.contains(.gameOver(.blackWon)) }
    return session
  }

  @Test
  func whiteLosesWhenTheirTimeRunsOut() async throws {
    let session = try await whiteRunsOutOfTime()
    #expect(session.result == .blackWon)
    #expect(session.termination == .timeout)
  }

  @Test
  func flaggedPlayerIsMarkedOnTheClock() async throws {
    let session = try await whiteRunsOutOfTime()
    #expect(session.clock.hasFlagged(.white))
    #expect(!session.clock.hasFlagged(.black))
  }

  @Test
  func lowTimeIsReportedBeforeTheFlagFalls() async throws {
    _ = try await whiteRunsOutOfTime()
    #expect(sink.events.contains(.lowTime))
  }

  @Test
  func inputIsDisabledAfterTheFlagFalls() async throws {
    let session = try await whiteRunsOutOfTime()
    #expect(!session.snapshot.isInputEnabled)
  }

  @Test
  func finishedGameIsSaved() async throws {
    let session = try makeSession(passAndPlay())
    try play(["f2f3", "e7e5", "g2g4", "d8h4"], in: session)
    #expect(sink.events.last == .gameOver(.blackWon))
    await session.flushPendingSave()

    let saved = try await store.allGames()
    #expect(saved.count == 1)
    let game = try #require(saved.first)
    #expect(game.id == session.id)
    #expect(game.result == .blackWon)
    #expect(game.termination == .checkmate)
    #expect(game.game.moves.count == 4)
  }

  @Test
  func failedSaveIsReportedOnce() async throws {
    // A regular file where the store's directory should be makes every write fail.
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data().write(to: directory.appending(component: "Kingside"))
    let session = try makeSession(passAndPlay())
    #expect(!session.showsSaveFailure)

    try play(["e2e4"], in: session)
    await session.flushPendingSave()
    #expect(session.showsSaveFailure)

    session.showsSaveFailure = false
    try play(["e7e5"], in: session)
    await session.flushPendingSave()
    #expect(!session.showsSaveFailure)
  }

  // MARK: Takeback

  @Test
  func takebackInPassAndPlayUndoesOnePly() throws {
    let session = try makeSession(passAndPlay())
    try play(["e2e4", "e7e5"], in: session)

    session.apply(.takeback)
    #expect(session.game.moves.map(\.san) == ["e4"])
    #expect(session.game.position.sideToMove == .black)
    #expect(session.snapshot.lastMove == ChessMove(uci: "e2e4"))
  }

  @Test
  func takebackIsUnavailableBeforeTheFirstMove() throws {
    let session = try makeSession(passAndPlay())
    #expect(!session.canTakeback)

    session.apply(.takeback)
    #expect(session.game.moves.isEmpty)
  }

  @Test
  func takebackWhileBotThinkingStopsTheSearch() throws {
    let session = try makeSession(try botGame("orrin"))
    session.activate()
    try play(["e2e4"], in: session)
    #expect(session.isBotThinking)

    session.apply(.takeback)
    #expect(!session.isBotThinking)
    #expect(session.game.moves.isEmpty)
    #expect(session.snapshot.isInputEnabled)
    session.deactivate()
  }

  @Test
  func botRepliesToTheMovePlayedAfterATakeback() throws {
    let session = try makeSession(try botGame("pip"))
    session.activate()
    try play(["e2e4"], in: session)
    session.apply(.takeback)

    try play(["d2d4"], in: session)
    #expect(session.isBotThinking)
    session.deactivate()
  }

  @Test
  func clockKeepsRunningAfterATakeback() async throws {
    let session = try makeSession(passAndPlay(TimeControl(initialSeconds: 60, incrementSeconds: 0)))
    session.activate()
    try play(["e2e4", "e7e5", "g1f3"], in: session)
    session.apply(.takeback)

    await clock.waitForSleeper()
    clock.advance(by: .seconds(61))
    await sink.wait { $0.contains(.gameOver(.blackWon)) }
    #expect(session.termination == .timeout)
  }

  @Test
  func takebackAfterBotReplyUndoesBothMoves() async throws {
    let session = try makeSession(try botGame("pip"))
    session.activate()
    try play(["e2e4"], in: session)
    clock.advance(by: .seconds(60))
    await sink.wait { $0.filter { if case .moved = $0 { true } else { false } }.count == 2 }
    #expect(session.game.moves.count == 2)

    session.apply(.takeback)
    #expect(session.game.moves.isEmpty)
    #expect(session.game.position.sideToMove == .white)
    session.deactivate()
  }

  @Test
  func takebackCancelsTheBotsPendingDrawDecision() async throws {
    // After Rxa4 only two rooks are left, so the bot would accept; with the knight still on
    // the board it declines.
    let session = try makeSession(try savedBotGame("pip", fen: "4k2r/8/8/8/n7/8/8/R3K3 w - - 0 1"))
    try play(["a1a4"], in: session)
    session.apply(.offerDraw)
    session.apply(.takeback)
    session.apply(.dismissBotMessage)

    session.apply(.offerDraw)
    while session.botMessage == nil && !session.isGameOver { await Task.yield() }
    #expect(session.result == .ongoing)
    #expect(session.game.moves.isEmpty)
  }

  // MARK: Draw and resignation

  @Test
  func drawOfferInPassAndPlayWaitsForTheOtherSide() throws {
    let session = try makeSession(passAndPlay())
    try play(["e2e4"], in: session)

    session.apply(.offerDraw)
    #expect(session.pendingDrawOffer == .black)
    #expect(!session.canMove)
    #expect(session.result == .ongoing)
  }

  @Test
  func acceptedDrawEndsTheGameByAgreement() throws {
    let session = try makeSession(passAndPlay())
    try play(["e2e4"], in: session)
    session.apply(.offerDraw)

    session.apply(.acceptDraw)
    #expect(session.result == .draw)
    #expect(session.termination == .agreement)
    #expect(session.pendingDrawOffer == nil)
    #expect(sink.events.last == .gameOver(.draw))
  }

  @Test
  func declinedDrawLetsTheGameContinue() throws {
    let session = try makeSession(passAndPlay())
    try play(["e2e4"], in: session)
    session.apply(.offerDraw)

    session.apply(.declineDraw)
    #expect(session.pendingDrawOffer == nil)
    #expect(session.result == .ongoing)
    #expect(session.canMove)
  }

  @Test
  func acceptWithoutOfferChangesNothing() throws {
    let session = try makeSession(passAndPlay())
    try play(["e2e4"], in: session)

    session.apply(.acceptDraw)
    #expect(session.result == .ongoing)
  }

  @Test
  func resigningInPassAndPlayLosesForTheSideToMove() throws {
    let session = try makeSession(passAndPlay())
    try play(["e2e4"], in: session)

    session.apply(.resign)
    #expect(session.result == .whiteWon)
    #expect(session.termination == .resignation)
    #expect(sink.events.last == .gameOver(.whiteWon))
  }

  @Test
  func resigningAgainstABotLosesForTheHuman() throws {
    let session = try makeSession(try botGame("pip"))

    session.apply(.resign)
    #expect(session.result == .blackWon)
    #expect(session.termination == .resignation)
    #expect(session.resultTitle == "You Lost")
  }

  // MARK: Board orientation and promotion

  @Test
  func autoFlipTurnsTheBoardToTheSideToMove() throws {
    let session = try makeSession(passAndPlay(autoFlip: true))
    #expect(session.snapshot.orientation == .white)

    try play(["e2e4"], in: session)
    #expect(session.snapshot.orientation == .black)
    try play(["e7e5"], in: session)
    #expect(session.snapshot.orientation == .white)
  }

  @Test
  func withoutAutoFlipTheBoardStaysPut() throws {
    let session = try makeSession(passAndPlay())

    try play(["e2e4"], in: session)
    #expect(session.snapshot.orientation == .white)
  }

  @Test
  func autoFlipSwapsThePlayerBars() throws {
    let session = try makeSession(passAndPlay(autoFlip: true))
    #expect(session.bottomPlayer == PlayerSlot(color: .white, info: PlayerInfo(name: "A")))

    try play(["e2e4"], in: session)
    #expect(session.bottomPlayer == PlayerSlot(color: .black, info: PlayerInfo(name: "B")))
    #expect(session.topPlayer == PlayerSlot(color: .white, info: PlayerInfo(name: "A")))
  }

  @Test
  func autoPromoteToQueenSkipsThePicker() throws {
    let session = try makeSession(
      try savedPassAndPlay(fen: Self.promotionFEN),
      autoPromoteToQueen: true
    )

    session.apply(.select(try square("b7")))
    session.apply(.select(try square("b8")))
    #expect(session.snapshot.pendingPromotion == nil)
    #expect(session.game.position[try square("b8")] == Piece(type: .queen, color: .white))
  }

  // MARK: Hint

  @Test
  func hintShowsALegalMoveOfTheSideToMove() async throws {
    let session = try makeSession(passAndPlay())

    session.apply(.requestHint)
    #expect(session.isLoadingHint)
    while session.isLoadingHint { await Task.yield() }
    let hint = try #require(session.snapshot.hint)
    let legal = session.game.position.legalMoves()
    #expect(legal.contains { $0.from == hint.from && $0.to == hint.to })
  }

  @Test
  func playingAMoveClearsTheHint() async throws {
    let session = try makeSession(passAndPlay())
    session.apply(.requestHint)
    while session.isLoadingHint { await Task.yield() }
    #expect(session.snapshot.hint != nil)

    try play(["e2e4"], in: session)
    #expect(session.snapshot.hint == nil)
  }

  // MARK: Rematch

  @Test
  func rematchSwapsColors() throws {
    let session = try makeSession(passAndPlay())
    try play(["e2e4"], in: session)

    session.apply(.rematch)
    #expect(session.white.name == "B")
    #expect(session.black.name == "A")
    #expect(session.game.moves.isEmpty)
    #expect(session.result == .ongoing)
  }

  @Test
  func rematchAgainstABotSwapsWhoIsHuman() throws {
    let session = try makeSession(try botGame("pip"))
    #expect(session.humanColor == .white)

    session.apply(.rematch)
    #expect(session.humanColor == .black)
  }

  @Test
  func rematchStartsANewSavedGame() async throws {
    let session = try makeSession(passAndPlay())
    try play(["e2e4"], in: session)
    let first = session.id

    session.apply(.rematch)
    try play(["d2d4"], in: session)
    await session.flushPendingSave()
    let saved = try await store.allGames()
    #expect(session.id != first)
    // The store keeps one unfinished game, so the first game is replaced.
    #expect(saved.map(\.id) == [session.id])
  }

  // MARK: Lifecycle

  @Test
  func deactivateSavesTheElapsedClock() async throws {
    let session = try makeSession(passAndPlay(TimeControl(initialSeconds: 60, incrementSeconds: 0)))
    session.activate()
    try play(["e2e4", "e7e5"], in: session)

    clock.advance(by: .seconds(10))
    session.deactivate()
    await session.flushPendingSave()
    let saved = try #require(try await store.allGames().first)
    #expect(saved.clock.remaining(.white) == 50)
    #expect(saved.clock.remaining(.black) == 60)
  }

  @Test
  func newGameReportsGameStartedOnce() throws {
    let session = try makeSession(passAndPlay())
    session.activate()
    session.deactivate()
    session.activate()

    #expect(sink.events == [.gameStarted])
    session.deactivate()
  }

  @Test
  func resumedGameDoesNotReportGameStarted() throws {
    let session = try makeSession(
      try savedPassAndPlay(fen: Self.promotionFEN, moves: ["e1d1"])
    )
    session.activate()

    #expect(sink.events.isEmpty)
    session.deactivate()
  }

  // MARK: Clock increment

  @Test
  func incrementIsNotAddedBeforeBothSidesHaveMoved() throws {
    let session = try makeSession(passAndPlay(TimeControl(initialSeconds: 60, incrementSeconds: 2)))

    try play(["e2e4", "e7e5"], in: session)
    #expect(session.clock.remaining(.white) == 60)
    #expect(session.clock.remaining(.black) == 60)
  }

  @Test
  func incrementIsAddedAfterLaterMoves() throws {
    let session = try makeSession(passAndPlay(TimeControl(initialSeconds: 60, incrementSeconds: 2)))

    try play(["e2e4", "e7e5", "d2d4"], in: session)
    #expect(session.clock.remaining(.white) == 62)
    #expect(session.clock.remaining(.black) == 60)
  }

  // MARK: Status text

  @Test
  func statusTextNamesTheSideToMove() throws {
    let session = try makeSession(passAndPlay())
    #expect(session.statusText == "White to move")

    try play(["e2e4"], in: session)
    #expect(session.statusText == "Black to move")
  }

  @Test
  func statusTextAppendsCheck() throws {
    let session = try makeSession(passAndPlay())

    try play(["e2e4", "f7f6", "d1h5"], in: session)
    #expect(session.statusText == "Black to move · Check")
  }

  @Test
  func statusTextAgainstABotSaysWhoseTurnItIs() throws {
    let session = try makeSession(try botGame("pip"))
    #expect(session.statusText == "Your move")
  }

  @Test
  func statusTextWhileTheBotThinks() throws {
    let session = try makeSession(try botGame("orrin"))
    session.activate()
    try play(["e2e4"], in: session)

    #expect(session.statusText == "Archmage Orrin is thinking…")
    session.deactivate()
  }

  @Test
  func statusTextAfterCheckmate() throws {
    let session = try makeSession(passAndPlay())

    try play(["f2f3", "e7e5", "g2g4", "d8h4"], in: session)
    #expect(session.statusText == "Black Won by checkmate")
  }

  // MARK: Player bars

  @Test
  func playerBarsShowBlackOnTopByDefault() throws {
    let session = try makeSession(passAndPlay())
    #expect(session.topPlayer == PlayerSlot(color: .black, info: PlayerInfo(name: "B")))
    #expect(session.bottomPlayer == PlayerSlot(color: .white, info: PlayerInfo(name: "A")))
  }

  @Test
  func flippingTheBoardSwapsThePlayerBars() throws {
    let session = try makeSession(passAndPlay())

    session.apply(.flipBoard)
    #expect(session.topPlayer.color == .white)
    #expect(session.bottomPlayer.color == .black)
    #expect(session.snapshot.orientation == .black)
  }

  @Test
  func humanPlaysFromTheBottomWhenBlack() throws {
    let session = try makeSession(try botGameAsBlack("pip"))
    #expect(session.snapshot.orientation == .black)
    #expect(session.bottomPlayer.color == .black)
    #expect(session.bottomPlayer.info == PlayerInfo(name: "You"))
    #expect(session.topPlayer.color == .white)
  }
}
