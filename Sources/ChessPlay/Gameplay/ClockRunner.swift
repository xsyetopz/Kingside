import ChessContent
import ChessCore
import Observation

/// Runs a game's `GameClock` on an injected `Clock`: charges the side to move for the time
/// since the last tick, reports `.lowTime` once per side, and applies the flag policy.
@Observable
@MainActor
final class ClockRunner {
  /// What a flag means for the game.
  enum FlagPolicy {
    /// A local game: `tick` returns the flagged side so the session can end the game.
    case endsGame
    /// An online game: the server decides, so the clock only shows zero.
    case showsZero
  }

  private(set) var clock: GameClock

  @ObservationIgnored
  private let policy: FlagPolicy
  @ObservationIgnored
  private let tuning: ClockTuning
  @ObservationIgnored
  private let feedback: any FeedbackSink
  /// Time since the runner was created, on the injected clock.
  @ObservationIgnored
  private let now: @Sendable () -> Duration
  @ObservationIgnored
  private let sleep: @Sendable (Duration) async throws -> Void
  @ObservationIgnored
  private var lastTick: Duration = .zero
  @ObservationIgnored
  private var lowTimeWarned: Set<PieceColor> = []
  @ObservationIgnored
  private var task: Task<Void, Never>?

  /// `tuning` is `ContentCatalog.tuning.clock`; `time` measures elapsed time and paces ticks.
  init(
    _ clock: GameClock,
    policy: FlagPolicy,
    tuning: ClockTuning,
    feedback: any FeedbackSink,
    time: some Clock<Duration>
  ) {
    self.clock = clock
    self.policy = policy
    self.tuning = tuning
    self.feedback = feedback
    let origin = time.now
    now = { origin.duration(to: time.now) }
    sleep = { try await time.sleep(for: $0) }
  }

  /// True when `color`'s clock is at or below the low-time threshold.
  func isLow(_ color: PieceColor) -> Bool { clock.isLow(color, tuning: tuning) }

  /// Starts a new game's clock; each side may be warned of low time again.
  func reset(to clock: GameClock) {
    self.clock = clock
    lowTimeWarned = []
  }

  /// Takes remaining times from an outside source, such as a server; time is charged from now.
  func resync(to clock: GameClock) {
    self.clock = clock
    lastTick = now()
  }

  /// Call after `color` moved; `plyBeforeMove` is the number of moves played before it.
  func recordMove(by color: PieceColor, plyBeforeMove: Int) {
    clock.recordMove(by: color, plyBeforeMove: plyBeforeMove)
  }

  /// Charges `sideToMove` for the time since the last tick when the clock runs at `plyCount`.
  /// `sideToMove` is nil while the game does not run. Returns the side whose flag fell under
  /// `.endsGame`; always nil under `.showsZero`.
  @discardableResult
  func tick(sideToMove: PieceColor?, plyCount: Int) -> PieceColor? {
    let current = now()
    let elapsed = current - lastTick
    lastTick = current
    guard let side = sideToMove, clock.runs(atPly: plyCount) else { return nil }
    let flagged = clock.consume(GamePresentation.seconds(elapsed), by: side)
    if isLow(side), !lowTimeWarned.contains(side) {
      lowTimeWarned.insert(side)
      feedback.receive(.lowTime)
    }
    switch policy {
    case .endsGame: return flagged ? side : nil
    case .showsZero: return nil
    }
  }

  /// Calls `onTick` every `tuning.tickInterval` until `stop()`; time is charged from now.
  func start(onTick: @escaping @MainActor () -> Void) {
    stop()
    lastTick = now()
    let interval = tuning.tickInterval
    task = Task { [weak self, sleep] in
      while !Task.isCancelled {
        try? await sleep(interval)
        guard self != nil, !Task.isCancelled else { return }
        onTick()
      }
    }
  }

  func stop() {
    task?.cancel()
    task = nil
  }
}
