import ChessContent
import Observation

/// The Daily Puzzle of one day. It is unrated: playing it to the end, with hints and retries
/// but not by showing the solution, marks the day as solved.
@preconcurrency
@Observable
@MainActor
public final class DailyPuzzleSession {
  public let board: PuzzleBoardSession
  public let day: PuzzleDay
  public private(set) var puzzle: Puzzle?

  private let puzzles: [Puzzle]
  private let selector: PuzzleSelector
  private let progress: PuzzleProgressStore

  public init(
    day: PuzzleDay,
    catalog: ContentCatalog,
    progress: PuzzleProgressStore,
    board: PuzzleBoardSession
  ) {
    self.day = day
    puzzles = catalog.puzzles
    selector = PuzzleSelector(tuning: catalog.tuning.puzzleSelection)
    self.progress = progress
    self.board = board
  }

  public var isSolved: Bool { progress.isDailySolved(day) }

  /// Loads the day's puzzle; later calls keep the current attempt.
  public func start() {
    if puzzle == nil { startOver() }
  }

  /// Loads the day's puzzle again from the start.
  public func startOver() {
    guard let puzzle = selector.daily(from: puzzles, day: day) else { return }
    self.puzzle = puzzle
    board.load(puzzle)
  }

  /// Call when the board's phase changes.
  public func boardPhaseChanged() {
    if board.phase == .solved { progress.markDailySolved(day) }
  }
}
