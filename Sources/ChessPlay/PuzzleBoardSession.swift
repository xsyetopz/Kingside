import ChessContent
import ChessCore
import Foundation
import Observation

// One puzzle on the board.
// - `load(_:)` shows a puzzle and, after the intro delay, plays the opponent's first move.
// - `apply(_:)` handles the board input intents, `.requestHint` and `.flipBoard`; game-only
//   intents are ignored. The board scene reads `snapshot`.
// - `retry()`, `showSolution()`, `phase` and `canHint` / `canRetry` / `canShowSolution` drive
//   the puzzle buttons. `onOutcome` fires once per puzzle.
// - The rules live in `PuzzleSession`; this type adds timing and presentation. Feedback goes
//   to the injected `FeedbackSink`, delays come from `catalog.tuning.puzzleBoard` and the
//   injected `Clock`.

/// Drives one puzzle on the board: plays the opponent's moves after delays, marks the solver's
/// moves with a correct or incorrect badge, reports feedback, and handles hint, retry and solution.
@Observable
@MainActor
public final class PuzzleBoardSession {
    public private(set) var session: PuzzleSession?
    /// The displayed position; after a wrong move it shows that move until retry or solution.
    public private(set) var position = ChessPosition.initial
    /// Called once per puzzle, when the attempt is solved, failed or made unrated.
    @ObservationIgnored public var onOutcome: ((PuzzleSession.RatedOutcome) -> Void)?

    private var board = BoardInteraction()
    private var badge: SquareBadge?
    /// Promotion moves waiting for `.promote`; empty when no picker is shown.
    private var pendingPromotion: [ChessMove] = []

    private let tuning: PuzzleBoardTuning
    private let feedback: any FeedbackSink
    private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var pendingTask: Task<Void, Never>?
    @ObservationIgnored private var reportedOutcome = false

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
        let side = position.sideToMove
        let king = Piece(type: .king, color: side)
        return BoardSnapshot(
            pieces: position.board,
            orientation: board.isFlipped ? .black : .white,
            focusedSquare: board.focusedSquare,
            selectedSquare: board.selectedSquare,
            legalTargets: board.legalTargets,
            lastMove: board.lastMove,
            checkSquare: position.isInCheck(side) ? position.board.first { $0.value == king }?.key : nil,
            hint: nil,
            pendingPromotion: pendingPromotion.first.map { move in
                PendingPromotion(from: move.from, to: move.to, color: side, choices: pendingPromotion.compactMap(\.promotion))
            },
            isInputEnabled: phase == .solverToMove && pendingPromotion.isEmpty,
            badge: badge
        )
    }

    // MARK: - Puzzle actions

    /// Shows `puzzle` from its FEN and plays the opponent's first move after the intro delay.
    /// A puzzle that cannot be played leaves the board empty of a session.
    public func load(_ puzzle: Puzzle) {
        pendingTask?.cancel()
        reportedOutcome = false
        pendingPromotion = []
        badge = nil
        board = BoardInteraction()
        guard let session = try? PuzzleSession(puzzle: puzzle) else {
            self.session = nil
            position = .initial
            return
        }
        self.session = session
        position = session.position
        board.isFlipped = session.solverColor == .black
        board.resetFocus(for: session.solverColor)
        schedule(after: tuning.introDelay) { $0.playIntro() }
    }

    /// Takes back the wrong move so the solver can try again; the attempt stays decided.
    public func retry() {
        guard let session, canRetry else { return }
        session.retry()
        position = session.position
        board.lastMove = session.lastMove
        board.cancelSelection()
        badge = nil
    }

    /// Plays the remaining listed moves, one per solution step delay, from the last correct position.
    public func showSolution() {
        guard let session, canShowSolution else { return }
        pendingTask?.cancel()
        pendingPromotion = []
        board.cancelSelection()
        badge = nil
        position = session.position
        board.lastMove = session.lastMove
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

    // MARK: - Intents

    public func apply(_ intent: BoardIntent) {
        switch intent {
        case .moveFocus(let direction): board.moveFocus(direction)
        case .focus(let square): board.focusedSquare = square
        case .selectFocused: select(board.focusedSquare)
        case .select(let square): select(square)
        case .cancel:
            pendingPromotion = []
            board.cancelSelection()
        case .promote(let type): choosePromotion(type)
        case .requestHint: requestHint()
        case .flipBoard: board.isFlipped.toggle()
        case .takeback, .offerDraw, .acceptDraw, .declineDraw, .resign, .rematch, .dismissBotMessage: break
        }
    }

    private func select(_ square: Square) {
        guard let session, phase == .solverToMove, pendingPromotion.isEmpty else { return }
        switch board.select(square, in: position, movableColor: session.solverColor) {
        case .none: break
        case .illegalTarget: feedback.receive(.illegalMove)
        case .move(let move): submit(move)
        case .promotion(let moves): pendingPromotion = moves
        }
    }

    private func choosePromotion(_ type: PieceType) {
        guard let move = pendingPromotion.first(where: { $0.promotion == type }) else { return }
        pendingPromotion = []
        submit(move)
    }

    /// Focuses and picks up the piece to move next; using a hint makes the attempt unrated.
    private func requestHint() {
        guard let session, let square = session.hint() else { return }
        pendingPromotion = []
        board.cancelSelection()
        board.focusedSquare = square
        _ = board.select(square, in: position, movableColor: session.solverColor)
    }

    // MARK: - Moves

    private func submit(_ move: ChessMove) {
        guard let session else { return }
        let before = position
        let result = session.submit(move)
        switch result {
        case .ignored:
            board.cancelSelection()
            feedback.receive(.illegalMove)
            return
        case .wrong:
            position = (try? before.applying(move)) ?? before
            board.complete(move)
            badge = SquareBadge(square: move.to, kind: .incorrect)
            feedback.receive(.puzzleWrong)
        case .correct, .solved:
            position = session.position
            board.complete(move)
            badge = SquareBadge(square: move.to, kind: .correct)
            feedback.receive(.puzzleCorrect)
        }
        reportOutcomeIfDecided()
        guard result == .correct else { return }
        schedule(after: tuning.replyDelay) { $0.playOpponentReply() }
    }

    /// After `delay`, plays the opponent move that `next` produces, unless another action replaced this one.
    private func schedule(after delay: Duration, _ next: @escaping @MainActor (PuzzleSession) -> ChessMove?) {
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
        board.lastMove = move
        feedback.receive(.moved(MoveSound.effect(for: move, before: before, after: position)))
    }

    private func reportOutcomeIfDecided() {
        guard !reportedOutcome, let outcome = session?.ratedOutcome else { return }
        reportedOutcome = true
        onOutcome?(outcome)
    }
}
