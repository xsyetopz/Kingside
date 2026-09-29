import Foundation
import ChessCore

/// Pure solving rules for one puzzle, independent of UI and timing.
///   var session = try PuzzleSession(puzzle: p)
///   session.playIntro()            // opponent's first move
///   session.submit(move)           // .correct / .solved / .wrong / .ignored
///   session.playOpponentReply()    // after a .correct result
/// A move matching the listed solution, or any move that checkmates, is correct.
/// `ratedOutcome` is fixed by the first decisive event: solving, a wrong move, or asking for
/// the solution. Using a hint first makes the attempt `.unrated`.
struct PuzzleSession: Sendable {
    enum Phase: Equatable, Sendable {
        case intro, solverToMove, opponentToMove, solved, failed, revealing, revealed
    }

    enum MoveResult: Equatable, Sendable {
        /// Correct, the opponent replies next.
        case correct
        /// Correct and the puzzle is complete.
        case solved
        /// Not the solution. The position stays before the move.
        case wrong
        /// Not the solver's turn, or an illegal move.
        case ignored
    }

    enum RatedOutcome: Equatable, Sendable { case solved, failed, unrated }

    let puzzle: Puzzle
    let solverColor: PieceColor
    private(set) var position: ChessPosition
    /// Index into `puzzle.moves` of the next move to play.
    private(set) var ply = 0
    private(set) var phase: Phase = .intro
    private(set) var usedHint = false
    private(set) var ratedOutcome: RatedOutcome?
    /// The move played last (by either side), for last-move highlighting.
    private(set) var lastMove: ChessMove?

    struct InvalidPuzzle: Error {}

    init(puzzle: Puzzle) throws {
        guard puzzle.moves.count >= 2, let position = puzzle.initialPosition else { throw InvalidPuzzle() }
        self.puzzle = puzzle
        self.position = position
        solverColor = position.sideToMove.opponent
    }

    /// The listed move expected next, or nil when the line is finished.
    var expectedMove: ChessMove? { ply < puzzle.moves.count ? puzzle.moves[ply] : nil }

    var isFinished: Bool { phase == .solved || phase == .revealed }

    /// Plays the opponent's first move. Returns nil if the intro was already played.
    @discardableResult
    mutating func playIntro() -> ChessMove? {
        guard phase == .intro, let move = expectedMove, advance(with: move) else { return nil }
        phase = .solverToMove
        return move
    }

    mutating func submit(_ move: ChessMove) -> MoveResult {
        guard phase == .solverToMove, let expected = expectedMove,
              let next = try? position.applying(move) else { return .ignored }
        let deliversMate: Bool
        if case .checkmate = next.outcome { deliversMate = true } else { deliversMate = false }
        guard move == expected || deliversMate else {
            phase = .failed
            decide(.failed)
            return .wrong
        }
        position = next
        lastMove = move
        ply += 1
        if deliversMate || ply >= puzzle.moves.count {
            phase = .solved
            decide(.solved)
            return .solved
        }
        phase = .opponentToMove
        return .correct
    }

    /// Plays the opponent's listed reply after a correct move.
    @discardableResult
    mutating func playOpponentReply() -> ChessMove? {
        guard phase == .opponentToMove, let move = expectedMove, advance(with: move) else { return nil }
        phase = ply >= puzzle.moves.count ? .solved : .solverToMove
        return move
    }

    /// Square of the piece the solver should move next; marks the attempt as hinted.
    mutating func hint() -> Square? {
        guard phase == .solverToMove, let move = expectedMove else { return nil }
        usedHint = true
        return move.from
    }

    /// Takes back a wrong move so the solver can try again from the same position.
    mutating func retry() {
        guard phase == .failed else { return }
        phase = .solverToMove
    }

    /// Plays the next listed move of the solution (either side). Returns nil when done.
    @discardableResult
    mutating func revealNext() -> ChessMove? {
        guard phase != .intro, !isFinished else { return nil }
        decide(.failed)
        phase = .revealing
        guard let move = expectedMove, advance(with: move) else {
            phase = .revealed
            return nil
        }
        if ply >= puzzle.moves.count { phase = .revealed }
        return move
    }

    private mutating func advance(with move: ChessMove) -> Bool {
        guard let next = try? position.applying(move) else { return false }
        position = next
        lastMove = move
        ply += 1
        return true
    }

    private mutating func decide(_ outcome: RatedOutcome) {
        guard ratedOutcome == nil else { return }
        ratedOutcome = usedHint ? .unrated : outcome
    }
}
