import ChessContent
import ChessCore
import Testing

@testable import ChessPlay

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ClockRunnerTests {
  private let time = TestClock()
  private let sink = RecordingFeedbackSink()
  /// One minute each, no increment.
  private let oneMinute = GameClock(
    timeControl: TimeControl(initialSeconds: 60, incrementSeconds: 0)
  )

  private func makeRunner(_ policy: ClockRunner.FlagPolicy) throws -> ClockRunner {
    ClockRunner(
      oneMinute,
      policy: policy,
      tuning: try Shared.catalog.tuning.clock,
      feedback: sink,
      time: time
    )
  }

  @Test
  func tickChargesTheSideToMoveForTheElapsedTime() throws {
    let runner = try makeRunner(.endsGame)
    time.advance(by: .seconds(5))
    runner.tick(sideToMove: .white, plyCount: 2)
    #expect(runner.clock.remaining(.white) == 55)
    #expect(runner.clock.remaining(.black) == 60)
  }

  @Test
  func tickChargesNothingBeforeBothSidesMoved() throws {
    let runner = try makeRunner(.endsGame)
    time.advance(by: .seconds(5))
    runner.tick(sideToMove: .black, plyCount: 1)
    #expect(runner.clock.remaining(.black) == 60)
  }

  @Test
  func tickChargesNothingWhileTheGameDoesNotRun() throws {
    let runner = try makeRunner(.endsGame)
    time.advance(by: .seconds(5))
    runner.tick(sideToMove: nil, plyCount: 2)
    // The stopped time is not charged later either.
    runner.tick(sideToMove: .white, plyCount: 2)
    #expect(runner.clock.remaining(.white) == 60)
  }

  @Test
  func lowTimeIsReportedOncePerSide() throws {
    let runner = try makeRunner(.endsGame)
    time.advance(by: .seconds(51))
    runner.tick(sideToMove: .white, plyCount: 2)
    time.advance(by: .seconds(1))
    runner.tick(sideToMove: .white, plyCount: 2)
    #expect(sink.events == [.lowTime])
  }

  @Test
  func resetAllowsANewLowTimeWarning() throws {
    let runner = try makeRunner(.endsGame)
    time.advance(by: .seconds(51))
    runner.tick(sideToMove: .white, plyCount: 2)
    runner.reset(to: oneMinute)
    #expect(runner.clock.remaining(.white) == 60)
    time.advance(by: .seconds(51))
    runner.tick(sideToMove: .white, plyCount: 2)
    #expect(sink.events == [.lowTime, .lowTime])
  }

  @Test
  func localFlagIsReportedForTheSessionToEndTheGame() throws {
    let runner = try makeRunner(.endsGame)
    time.advance(by: .seconds(61))
    #expect(runner.tick(sideToMove: .white, plyCount: 2) == .white)
    #expect(runner.clock.hasFlagged(.white))
  }

  @Test
  func onlineFlagOnlyShowsZero() throws {
    let runner = try makeRunner(.showsZero)
    time.advance(by: .seconds(61))
    #expect(runner.tick(sideToMove: .white, plyCount: 2) == nil)
    #expect(runner.clock.remaining(.white) == 0)
  }

  @Test
  func resyncChargesOnlyTimeAfterTheNewTimes() throws {
    let runner = try makeRunner(.showsZero)
    time.advance(by: .seconds(5))
    runner.resync(
      to: GameClock(timeControl: oneMinute.timeControl, whiteRemaining: 50, blackRemaining: 40)
    )
    time.advance(by: .seconds(1))
    runner.tick(sideToMove: .white, plyCount: 2)
    #expect(runner.clock.remaining(.white) == 49)
    #expect(runner.clock.remaining(.black) == 40)
  }

  @Test
  func startTicksOncePerInterval() async throws {
    let runner = try makeRunner(.endsGame)
    var ticks = 0
    runner.start { ticks += 1 }
    let interval = try Shared.catalog.tuning.clock.tickInterval
    await time.waitForSleeper()
    time.advance(by: interval - .milliseconds(1))
    #expect(ticks == 0)
    time.advance(by: .milliseconds(1))
    // The loop sleeps again only after it ticked.
    await time.waitForSleeper()
    #expect(ticks == 1)
    runner.stop()
  }

  @Test
  func stopEndsTheTickLoop() async throws {
    let runner = try makeRunner(.endsGame)
    runner.start {}
    await time.waitForSleeper()
    runner.stop()
    #expect(time.sleeperCount == 0)
  }
}
