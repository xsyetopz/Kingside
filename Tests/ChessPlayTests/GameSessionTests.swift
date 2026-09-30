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

  private func makeSession(_ launch: GameLaunch) throws -> GameSession {
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    return try GameSession(
      launch: launch,
      engine: engine,
      catalog: Shared.catalog,
      localization: Shared.english,
      settings: SettingsStore(defaults: defaults),
      store: store,
      feedback: sink,
      clock: clock
    )
  }

  private func passAndPlay(_ timeControl: TimeControl = .untimed) -> GameLaunch {
    .new(
      GameSetup(
        mode: .passAndPlay,
        white: PlayerInfo(name: "A"),
        black: PlayerInfo(name: "B"),
        timeControl: timeControl
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
    let game = ChessGame(position: try ChessPosition(fen: "4k3/1P5p/8/8/8/8/8/4K3 w - - 0 1"))
    let saved = SavedGame(
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
    let session = try makeSession(.saved(saved))
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
  func newGameCancelsBotSearch() async throws {
    let session = try makeSession(try botGame("orrin"))
    session.activate()
    try play(["e2e4"], in: session)
    let search = try #require(session.botTask)

    session.apply(.rematch)
    #expect(search.isCancelled)
    #expect(session.game.moves.isEmpty)
    session.deactivate()
    await search.value
    #expect(session.game.moves.isEmpty)
  }

  @Test
  func timedGameEndsOnTime() async throws {
    let session = try makeSession(passAndPlay(TimeControl(initialSeconds: 60, incrementSeconds: 0)))
    session.activate()
    try play(["e2e4", "e7e5"], in: session)
    await clock.waitForSleeper()

    clock.advance(by: .seconds(61))
    await sink.wait { $0.contains(.gameOver(.blackWon)) }
    #expect(session.result == .blackWon)
    #expect(session.termination == .timeout)
    #expect(session.clock.hasFlagged(.white))
    #expect(sink.events.contains(.lowTime))
    #expect(!session.snapshot.isInputEnabled)
  }

  @Test
  func finishedGameIsSaved() async throws {
    let session = try makeSession(passAndPlay())
    try play(["f2f3", "e7e5", "g2g4", "d8h4"], in: session)
    #expect(sink.events.last == .gameOver(.blackWon))
    await session.saveTask?.value

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
    await session.saveTask?.value
    #expect(session.showsSaveFailure)

    session.showsSaveFailure = false
    try play(["e7e5"], in: session)
    await session.saveTask?.value
    #expect(!session.showsSaveFailure)
  }
}
