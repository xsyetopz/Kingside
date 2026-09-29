import SwiftUI
import ChessCore

/// Drives one puzzle on the board: plays the opponent's moves with delays, marks solver moves
/// with a green check or red X badge, plays sounds, and handles hint, retry and solution.
/// The rules live in `PuzzleSession`; this type adds timing and presentation.
/// `onOutcome` fires once per puzzle, when the attempt is solved, failed or made unrated.
@MainActor
final class PuzzleBoardModel: ObservableObject {
    @Published private(set) var session: PuzzleSession?
    /// Displayed position; after a wrong move it shows that move until Retry or Solution.
    @Published private(set) var position = ChessPosition.initial
    @Published private(set) var badges: [BoardBadge] = []
    @Published private(set) var pendingPromotion: [ChessMove] = []
    let board = BoardInteractionController()
    var onOutcome: ((PuzzleSession.RatedOutcome) -> Void)?

    static let introDelay: Duration = .milliseconds(700)
    static let replyDelay: Duration = .milliseconds(500)
    static let solutionStepDelay: Duration = .milliseconds(800)

    private var pendingTask: Task<Void, Never>?
    private var reportedOutcome = false

    var phase: PuzzleSession.Phase { session?.phase ?? .intro }
    var solverColor: PieceColor { session?.solverColor ?? .white }
    var canHint: Bool { phase == .solverToMove }
    var canRetry: Bool { phase == .failed }
    var canShowSolution: Bool { [.solverToMove, .opponentToMove, .failed].contains(phase) }

    /// Shows `puzzle` from its FEN and auto-plays the opponent's first move.
    func load(_ puzzle: Puzzle) {
        pendingTask?.cancel()
        reportedOutcome = false
        pendingPromotion = []
        badges = []
        guard let session = try? PuzzleSession(puzzle: puzzle) else {
            self.session = nil
            return
        }
        self.session = session
        position = session.position
        board.isFlipped = session.solverColor == .black
        board.lastMove = nil
        board.cancelSelection()
        board.resetFocus(for: session.solverColor)
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: Self.introDelay)
            guard !Task.isCancelled, let self, var session = self.session else { return }
            let before = session.position
            guard let move = session.playIntro() else { return }
            self.session = session
            self.showOpponentMove(move, from: before)
        }
    }

    /// Select on the board: pick up a piece or play the move under the cursor.
    func select() {
        guard phase == .solverToMove, pendingPromotion.isEmpty else { return }
        switch board.selectFocused(in: position, movableColor: solverColor) {
        case .none: break
        case .move(let move): submit(move)
        case .promotion(let moves): pendingPromotion = moves
        }
    }

    /// Back on the board. Returns false when there was nothing to cancel.
    func cancelSelection() -> Bool {
        if !pendingPromotion.isEmpty {
            pendingPromotion = []
            board.cancelSelection()
            return true
        }
        guard board.selectedSquare != nil else { return false }
        board.cancelSelection()
        return true
    }

    func choosePromotion(_ type: PieceType) {
        let move = pendingPromotion.first { $0.promotion == type }
        pendingPromotion = []
        if let move { submit(move) } else { board.cancelSelection() }
    }

    func hint() {
        guard var session, let square = session.hint() else { return }
        self.session = session
        board.cancelSelection()
        board.focusedSquare = square
        badges = [BoardBadge(square: square, content: .symbol("lightbulb.fill"), color: BoardArrow.hint)]
    }

    /// Takes back the wrong move so the solver can try again (the attempt stays decided).
    func retry() {
        guard var session, session.phase == .failed else { return }
        session.retry()
        self.session = session
        position = session.position
        board.lastMove = session.lastMove
        board.cancelSelection()
        badges = []
    }

    /// Animates the remaining listed moves from the last correct position.
    func showSolution() {
        guard canShowSolution else { return }
        pendingTask?.cancel()
        pendingPromotion = []
        board.cancelSelection()
        badges = []
        if let session {
            position = session.position
            board.lastMove = session.lastMove
        }
        pendingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.solutionStepDelay)
                guard !Task.isCancelled, let self, var session = self.session else { return }
                let before = session.position
                let move = session.revealNext()
                self.session = session
                self.reportOutcomeIfDecided()
                guard let move else { return }
                self.showOpponentMove(move, from: before)
                if session.phase == .revealed { return }
            }
        }
    }

    private func submit(_ move: ChessMove) {
        guard var session else { return }
        let before = position
        let result = session.submit(move)
        switch result {
        case .ignored:
            board.cancelSelection()
            return
        case .wrong:
            position = (try? before.applying(move)) ?? before
            board.complete(move)
            badges = [BoardBadge(square: move.to, content: .symbol("xmark"), color: ChessTheme.loss)]
            SoundEffects.shared.play(.puzzleWrong)
        case .correct, .solved:
            position = session.position
            board.complete(move)
            badges = [BoardBadge(square: move.to, content: .symbol("checkmark"), color: ChessTheme.win)]
            SoundEffects.shared.play(.puzzleCorrect)
        }
        self.session = session
        reportOutcomeIfDecided()
        guard result == .correct else { return }
        pendingTask = Task { [weak self] in
            try? await Task.sleep(for: Self.replyDelay)
            guard !Task.isCancelled, let self, var session = self.session else { return }
            let before = session.position
            guard let reply = session.playOpponentReply() else { return }
            self.session = session
            self.badges = []
            self.showOpponentMove(reply, from: before)
        }
    }

    private func showOpponentMove(_ move: ChessMove, from before: ChessPosition) {
        position = session?.position ?? position
        board.lastMove = move
        SoundEffects.shared.play(before[move.to] == nil ? .move : .capture)
    }

    private func reportOutcomeIfDecided() {
        guard !reportedOutcome, let outcome = session?.ratedOutcome else { return }
        reportedOutcome = true
        onOutcome?(outcome)
    }
}
