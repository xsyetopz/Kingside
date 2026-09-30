import ChessContent
import Foundation
import Observation

/// One Puzzle Rush run on the board: loads escalating puzzles, counts score and strikes, runs
/// the clock of a timed mode, and saves the best score when the run ends.
///   let rush = PuzzleRushSession(mode: .threeMinutes, catalog: c, progress: p, board: b)
///   rush.start()      // also starts again after a result
///   rush.result       // set once the run is over
/// A puzzle that ends without a solution counts as a strike, including one where a hint was used.
/// The clock holds while the opponent plays the first move of a puzzle.
@Observable
@MainActor
public final class PuzzleRushSession {
    /// The finished run.
    public struct Result: Equatable, Sendable {
        public let mode: PuzzleRushMode
        public let score: Int
        public let isNewBest: Bool
        /// The best score of the mode, including this run.
        public let best: Int
    }

    public let board: PuzzleBoardSession
    public let mode: PuzzleRushMode
    public private(set) var run: PuzzleRushRun
    public private(set) var result: Result?

    private let puzzles: [Puzzle]
    private let selector: PuzzleSelector
    private let rushTuning: PuzzleRushTuning
    private let tickInterval: Duration
    private let progress: PuzzleProgressStore
    private let sleep: @Sendable (Duration) async throws -> Void
    private let uptime: @MainActor () -> Duration
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()
    @ObservationIgnored private var used: Set<String> = []
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    @ObservationIgnored private var nextTask: Task<Void, Never>?

    public init(
        mode: PuzzleRushMode,
        catalog: ContentCatalog,
        progress: PuzzleProgressStore,
        board: PuzzleBoardSession,
        clock: some Clock<Duration> = ContinuousClock()
    ) {
        self.mode = mode
        puzzles = catalog.puzzles
        selector = PuzzleSelector(tuning: catalog.tuning.puzzleSelection)
        rushTuning = catalog.tuning.puzzleRush
        tickInterval = catalog.tuning.clock.tickInterval
        self.progress = progress
        self.board = board
        run = PuzzleRushRun(mode: mode, tuning: catalog.tuning.puzzleRush)
        sleep = { try await clock.sleep(for: $0) }
        let origin = clock.now
        uptime = { origin.duration(to: clock.now) }
        board.onOutcome = { [weak self] in self?.record($0) }
    }

    public var isRunning: Bool { result == nil && !isStopped }
    @ObservationIgnored private var isStopped = true

    /// Starts a fresh run, dropping the previous one.
    public func start() {
        stop()
        isStopped = false
        run = PuzzleRushRun(mode: mode, tuning: rushTuning)
        result = nil
        used = []
        loadNext()
        if run.remaining != nil { startClock() }
    }

    /// Ends the run now and keeps its score.
    public func end() { finish() }

    /// Stops the run's timers without saving anything, for when the screen goes away.
    public func stop() {
        isStopped = true
        clockTask?.cancel()
        nextTask?.cancel()
    }

    /// Counts `elapsed` down on the clock unless the opponent is still making the first move.
    func tick(_ elapsed: Duration) {
        guard isRunning, board.phase != .intro else { return }
        run.tick(Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        if run.isOver { finish() }
    }

    private func startClock() {
        clockTask = Task { [weak self, sleep, tickInterval] in
            var last = self?.uptime()
            while !Task.isCancelled {
                try? await sleep(tickInterval)
                guard !Task.isCancelled, let self, let previous = last else { return }
                let now = uptime()
                last = now
                tick(now - previous)
            }
        }
    }

    private func record(_ outcome: PuzzleSession.RatedOutcome) {
        guard isRunning else { return }
        if outcome == .solved { run.recordSolved() } else { run.recordFailed() }
        nextTask?.cancel()
        nextTask = Task { [weak self, sleep, delay = rushTuning.nextPuzzleDelay] in
            try? await sleep(delay)
            guard !Task.isCancelled, let self, isRunning else { return }
            if run.isOver { finish() } else { loadNext() }
        }
    }

    private func loadNext() {
        guard let puzzle = selector.rush(from: puzzles, index: run.puzzlesPlayed, excluding: used, using: &generator) else {
            finish()
            return
        }
        used.insert(puzzle.id)
        board.load(puzzle)
    }

    private func finish() {
        guard isRunning else { return }
        stop()
        let isNewBest = progress.recordRush(mode: mode, score: run.score)
        result = Result(mode: mode, score: run.score, isNewBest: isNewBest, best: progress.rushBest(for: mode))
    }
}
