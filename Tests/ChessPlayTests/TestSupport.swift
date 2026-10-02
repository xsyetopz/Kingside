import Foundation
import Testing

import ChessContent

@testable import ChessPlay

/// Values shared by every ChessPlay test.
enum Shared {
  /// The bundled catalog, decoded once.
  static let loadedCatalog = Result { try ContentCatalog.load() }

  static var catalog: ContentCatalog {
    get throws { try loadedCatalog.get() }
  }

  /// Source English, independent of the machine's language settings.
  static let english = Localization(preferredLanguages: ["en-US"])
}

/// Runs `body` with an empty `UserDefaults` suite that is removed afterwards.
func withTemporaryDefaults<Value>(_ body: (UserDefaults) throws -> Value) throws -> Value {
  let suite = "ChessPlayTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  return try body(defaults)
}

/// Runs `body` with a new empty directory that is removed afterwards.
func withTemporaryDirectory<Value>(_ body: (URL) async throws -> Value) async throws -> Value {
  let directory = FileManager.default.temporaryDirectory
    .appending(component: "ChessPlayTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  return try await body(directory)
}

/// URL of a file in this target's `Fixtures` directory.
func fixtureURL(_ name: String) throws -> URL {
  let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
  return try #require(url, "Missing fixture \(name)")
}

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

/// A connection whose events the test pushes; records every action sent.
final class FakeOnlineConnection: OnlineGameConnection, @unchecked Sendable {
  let service = "lichess"
  private let lock = NSLock()
  private var continuation: AsyncThrowingStream<OnlineGameEvent, Error>.Continuation?
  private var sentActions: [OnlineAction] = []
  private var failsSends = false
  private var streamCount = 0

  var sent: [OnlineAction] { lock.withLock { sentActions } }
  var streams: Int { lock.withLock { streamCount } }

  func setFailsSends(_ fails: Bool) { lock.withLock { failsSends = fails } }

  func events() -> AsyncThrowingStream<OnlineGameEvent, Error> {
    let (stream, continuation) = AsyncThrowingStream<OnlineGameEvent, Error>.makeStream()
    lock.withLock {
      self.continuation = continuation
      streamCount += 1
    }
    return stream
  }

  /// Ends the newest stream with an error.
  func fail() {
    let continuation = lock.withLock { self.continuation }
    continuation?.finish(throwing: URLError(.networkConnectionLost))
  }

  /// Sends `event` on the newest stream.
  func push(_ event: OnlineGameEvent) {
    let continuation = lock.withLock { self.continuation }
    continuation?.yield(event)
  }

  func send(_ action: OnlineAction) throws {
    let fails = lock.withLock {
      sentActions.append(action)
      return failsSends
    }
    if fails { throw URLError(.notConnectedToInternet) }
  }
}
