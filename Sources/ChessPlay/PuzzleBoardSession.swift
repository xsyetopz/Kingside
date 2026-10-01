import ChessContent
import ChessCore
import Foundation
import Observation

// One puzzle on the board.
// - `load(_:)` shows a puzzle and, after the intro delay, plays the opponent's first move.
// - `apply(_:)` handles every `BoardInput` and the `.requestHint` and `.flipBoard` actions;
//   other `GameAction`s are ignored. The board scene reads `snapshot`.
// - `retry()`, `showSolution()`, `phase` and `canHint` / `canRetry` / `canShowSolution` drive
//   the puzzle buttons. `onOutcome` fires once per puzzle.
// - The rules live in `PuzzleSession`; this type adds timing and presentation. Feedback goes
//   to the injected `FeedbackSink`, delays come from `catalog.tuning.puzzleBoard` and the
//   injected `Clock`.

/// Drives one puzzle on the board: plays the opponent's moves after delays, marks the solver's
/// moves with a correct or incorrect badge, reports feedback, and handles hint, retry and solution.
@preconcurrency
@Observable
@MainActor
public final class PuzzleBoardSession {
  public private(set) var session: PuzzleSession?
  /// The displayed position; after a wrong move it shows that move until retry or solution.
  public private(set) var position = ChessPosition.initial
  /// Called once per puzzle, when the attempt is solved, failed or made unrated.
  @ObservationIgnored
  var onOutcome: ((PuzzleSession.RatedOutcome) -> Void)?

  private var input = MoveInput()
  private var badge: SquareBadge?

  private let tuning: PuzzleBoardTuning
  private let feedback: any FeedbackSink
  private let sleep: @Sendable (Duration) async throws -> Void
  @ObservationIgnored
  private var pendingTask: Task<Void, Never>?
  @ObservationIgnored
  private var reportedOutcome = false

  public init(
    catalog: ContentCatalog,
    feedback: any FeedbackSink = NullFeedbackSink(),
    clock: some Clock<Duration> = ContinuousClock()
  ) {
    tuning = catalog.tuning.puzzleBoard
    self.feedback = feedback
    sleep = { try await clock.sleep(for: $0) }
  }

  public var phase: PuzzleSession.Phase { session?.phase ?? .intro }
  public var solverColor: PieceColor { session?.solverColor ?? .white }
  public var canHint: Bool { phase == .solverToMove }
  public var canRetry: Bool { phase == .failed }
  public var canShowSolution: Bool { [.solverToMove, .opponentToMove, .failed].contains(phase) }

  public var snapshot: BoardSnapshot {
    input.snapshot(of: position, canMove: phase == .solverToMove, badge: badge)
  }

  // MARK: - Puzzle actions

  /// Shows `puzzle` from its FEN and plays the opponent's first move after the intro delay.
  /// A puzzle that cannot be played leaves the board empty of a session.
  public func load(_ puzzle: Puzzle) {
    pendingTask?.cancel()
    reportedOutcome = false
    badge = nil
    input = MoveInput()
    guard let session = try? PuzzleSession(puzzle: puzzle) else {
      self.session = nil
      position = .initial
      return
    }
    self.session = session
    position = session.position
    input.isFlipped = session.solverColor == .black
    input.resetFocus(for: session.solverColor)
    schedule(after: tuning.introDelay) { $0.playIntro() }
  }

  /// Takes back the wrong move so the solver can try again; the attempt stays decided.
  public func retry() {
    guard let session, canRetry else { return }
    session.retry()
    position = session.position
    input.lastMove = session.lastMove
    input.cancel()
    badge = nil
  }

  /// Plays the remaining listed moves, one per solution step delay, from the last correct position.
  public func showSolution() {
    guard let session, canShowSolution else { return }
    pendingTask?.cancel()
    input.cancel()
    badge = nil
    position = session.position
    input.lastMove = session.lastMove
    pendingTask = Task { [weak self, sleep, delay = tuning.solutionStepDelay] in
      while !Task.isCancelled {
        try? await sleep(delay)
        guard !Task.isCancelled, let self else { return }
        let before = session.position
        let move = session.revealNext()
        reportOutcomeIfDecided()
        guard let move else { return }
        showOpponentMove(move, from: before)
        if session.phase == .revealed { return }
      }
    }
  }

  // MARK: - Input and actions

  public func apply(_ boardInput: BoardInput) {
    switch boardInput {
    case .moveFocus(let direction): input.moveFocus(direction)
    case .focus(let square): input.focus(square)
    case .selectFocused: select(input.focusedSquare)
    case .select(let square): select(square)
    case .cancel: input.cancel()
    case .promote(let type): if let move = input.promote(type) { submit(move) }
    }
  }

  public func apply(_ action: GameAction) {
    switch action {
    case .requestHint: requestHint()
    case .flipBoard: input.isFlipped.toggle()
    case .takeback, .offerDraw, .acceptDraw, .declineDraw, .resign, .rematch, .dismissBotMessage:
      break
    }
  }

  private func select(_ square: Square) {
    guard let session, phase == .solverToMove, !input.isChoosingPromotion else { return }
    switch input.select(square, in: position, movableColor: session.solverColor, autoQueen: false) {
    case .none: break
    case .illegalTarget: feedback.receive(.illegalMove)
    case .play(let move): submit(move)
    }
  }

  /// Focuses and picks up the piece to move next; using a hint makes the attempt unrated.
  private func requestHint() {
    guard let session, let square = session.hint() else { return }
    input.cancel()
    input.focus(square)
    _ = input.select(square, in: position, movableColor: session.solverColor, autoQueen: false)
  }

  // MARK: - Moves

  private func submit(_ move: ChessMove) {
    guard let session else { return }
    let before = position
    let result = session.submit(move)
    switch result {
    case .ignored:
      input.cancel()
      feedback.receive(.illegalMove)
      return
    case .wrong:
      position = (try? before.applying(move)) ?? before
      input.complete(move)
      badge = SquareBadge(square: move.to, kind: .incorrect)
      feedback.receive(.puzzleWrong)
    case .correct, .solved:
      position = session.position
      input.complete(move)
      badge = SquareBadge(square: move.to, kind: .correct)
      feedback.receive(.puzzleCorrect)
    }
    reportOutcomeIfDecided()
    guard result == .correct else { return }
    schedule(after: tuning.replyDelay) { $0.playOpponentReply() }
  }

  /// After `delay`, plays the opponent move that `next` produces, unless another action replaced
  /// this one.
  private func schedule(
    after delay: Duration,
    _ next: @escaping @MainActor (PuzzleSession) -> ChessMove?
  ) {
    pendingTask?.cancel()
    pendingTask = Task { [weak self, sleep] in
      try? await sleep(delay)
      guard !Task.isCancelled, let self, let session else { return }
      let before = session.position
      guard let move = next(session) else { return }
      badge = nil
      showOpponentMove(move, from: before)
    }
  }

  private func showOpponentMove(_ move: ChessMove, from before: ChessPosition) {
    position = session?.position ?? position
    input.lastMove = move
    feedback.receive(.moved(MoveSound.effect(for: move, before: before, after: position)))
  }

  private func reportOutcomeIfDecided() {
    guard !reportedOutcome, let outcome = session?.ratedOutcome else { return }
    reportedOutcome = true
    onOutcome?(outcome)
  }
}
