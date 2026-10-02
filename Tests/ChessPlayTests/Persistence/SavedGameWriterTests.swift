import ChessCore
import Foundation
import Testing

@testable import ChessPlay

/// Saves run one after another, `onSave` follows each successful write, and each failed write is
/// forwarded with the game that failed.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SavedGameWriterTests {
  private let firstGameID = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
  private let secondGameID = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
  private let store = ControlledWrites()
  private let callbacks = CallbackLog()

  private func writer() -> SavedGameWriter {
    SavedGameWriter(
      write: { [store] in try await store.write($0) },
      onSave: { [callbacks] in callbacks.saveCount += 1 },
      onFailure: { [callbacks] in callbacks.failedGameIDs.append($0) }
    )
  }

  private func save(_ gameID: UUID, result: GameResult, with writer: SavedGameWriter) {
    writer.save(
      id: gameID,
      createdAt: Date(timeIntervalSince1970: 0),
      mode: .passAndPlay,
      white: PlayerInfo(name: "A"),
      black: PlayerInfo(name: "B"),
      timeControl: .untimed,
      autoFlip: false,
      game: ChessGame(),
      result: result,
      termination: result == .ongoing ? nil : .agreement,
      clock: GameClock(timeControl: .untimed)
    )
  }

  /// Round trips to the store until a second write starts, at most `limit` times. Nothing in the
  /// writer marks the moment a chained second save is parked, so no wait can prove that an
  /// unchained one would never start; each trip queues behind any write already sent to the store.
  private func untilASecondWriteStarts(limit: Int = 1000) async {
    for _ in 0..<limit where await store.startedResults.count < 2 {
      await Task.yield()
    }
  }

  @Test
  func aSecondSaveDoesNotStartWhileTheFirstIsWritten() async {
    let writer = writer()
    await store.holdNextWrite()
    save(firstGameID, result: .ongoing, with: writer)
    await store.untilWritesStarted(1)
    save(firstGameID, result: .draw, with: writer)
    await untilASecondWriteStarts()

    #expect(await store.startedResults == [.ongoing])
    await store.releaseHeldWrite()
    await writer.flush()
    #expect(await store.written.map(\.result) == [.ongoing, .draw])
  }

  @Test
  func eachFailureIsForwardedWithTheGameThatFailed() async {
    let writer = writer()
    await store.fail(firstGameID)
    await store.fail(secondGameID)
    save(firstGameID, result: .ongoing, with: writer)
    save(secondGameID, result: .ongoing, with: writer)
    save(firstGameID, result: .draw, with: writer)
    await writer.flush()

    #expect(callbacks.failedGameIDs == [firstGameID, secondGameID, firstGameID])
  }

  @Test
  func aFailureNamesTheGameThatFailedNotTheLatestOne() async {
    let writer = writer()
    await store.fail(firstGameID)
    await store.holdNextWrite()
    save(firstGameID, result: .ongoing, with: writer)
    await store.untilWritesStarted(1)
    save(secondGameID, result: .ongoing, with: writer)
    await store.releaseHeldWrite()
    await writer.flush()

    #expect(callbacks.failedGameIDs == [firstGameID])
  }

  @Test
  func onSaveRunsOnceTheWriteFinished() async {
    let writer = writer()
    await store.holdNextWrite()
    save(firstGameID, result: .ongoing, with: writer)
    await store.untilWritesStarted(1)
    #expect(callbacks.saveCount == 0)

    await store.releaseHeldWrite()
    await writer.flush()
    #expect(callbacks.saveCount == 1)
  }

  @Test
  func aFailedWriteDoesNotRunOnSave() async {
    let writer = writer()
    await store.fail(firstGameID)
    save(firstGameID, result: .ongoing, with: writer)
    await writer.flush()

    #expect(callbacks.saveCount == 0)
  }
}

@MainActor
private final class CallbackLog {
  var saveCount = 0
  var failedGameIDs: [UUID] = []
}

/// A store that records each write as it starts, can hold the next write until the test releases
/// it, and fails writes for chosen games.
private actor ControlledWrites {
  struct Failure: Error {}

  private(set) var startedResults: [GameResult] = []
  private(set) var written: [SavedGame] = []
  private var failingGameIDs: Set<UUID> = []
  private var holdsNextWrite = false
  private var startWaiter: (count: Int, continuation: CheckedContinuation<Void, Never>)?
  private var heldWrite: CheckedContinuation<Void, Never>?

  func fail(_ gameID: UUID) { failingGameIDs.insert(gameID) }

  func holdNextWrite() { holdsNextWrite = true }

  func untilWritesStarted(_ count: Int) async {
    guard startedResults.count < count else { return }
    await withCheckedContinuation { startWaiter = (count, $0) }
  }

  func releaseHeldWrite() {
    heldWrite?.resume()
    heldWrite = nil
  }

  func write(_ game: SavedGame) async throws {
    startedResults.append(game.result)
    if let waiter = startWaiter, waiter.count <= startedResults.count {
      waiter.continuation.resume()
      startWaiter = nil
    }
    if holdsNextWrite {
      holdsNextWrite = false
      await withCheckedContinuation { heldWrite = $0 }
    }
    guard !failingGameIDs.contains(game.id) else { throw Failure() }
    written.append(game)
  }
}
