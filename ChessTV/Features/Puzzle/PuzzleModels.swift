import Foundation
import ChessCore

struct ChessPuzzle: Identifiable, Codable, Sendable {
    let id: String
    let title: String
    let fen: String
    let line: [String]
}

protocol PuzzleProviding: Sendable {
    func puzzles() async throws -> [ChessPuzzle]
}

struct BundledPuzzleProvider: PuzzleProviding {
    func puzzles() async throws -> [ChessPuzzle] {
        [
            ChessPuzzle(id: "mate-001", title: "A protected finish", fen: "7k/5Q2/6K1/8/8/8/8/8 w - - 0 1", line: ["f7g7"]),
            ChessPuzzle(id: "mate-002", title: "Back-rank strike", fen: "6k1/5ppp/8/8/8/8/6PP/3R2K1 w - - 0 1", line: ["d1d8"])
        ]
    }
}

@MainActor
final class PuzzleViewModel: ObservableObject {
    @Published private(set) var puzzles: [ChessPuzzle] = []
    @Published private(set) var index = 0
    @Published private(set) var position = ChessPosition.initial
    @Published private(set) var feedback = "Find the best move"
    @Published private(set) var isSolved = false
    let board = BoardInteractionController()

    private let provider: any PuzzleProviding
    private var lineIndex = 0
    private var startPosition = ChessPosition.initial

    init(provider: any PuzzleProviding = BundledPuzzleProvider()) { self.provider = provider }

    var title: String { puzzles.indices.contains(index) ? puzzles[index].title : "Puzzle" }
    var sideToMove: String { position.sideToMove.rawValue.capitalized }

    func load() {
        Task {
            puzzles = (try? await provider.puzzles()) ?? []
            openPuzzle(at: 0)
        }
    }

    func select() {
        guard !isSolved, puzzles.indices.contains(index) else { return }
        let playerColor = startPosition.sideToMove
        switch board.selectFocused(in: position, movableColor: playerColor) {
        case .move(let move): handle(move)
        case .promotion(let moves):
            if let queen = moves.first(where: { $0.promotion == .queen }) { handle(queen) }
        case .none: break
        }
    }

    func retry() { openPuzzle(at: index) }
    func next() { openPuzzle(at: (index + 1) % max(1, puzzles.count)) }

    private func handle(_ move: ChessMove) {
        guard puzzles[index].line.indices.contains(lineIndex) else {
            feedback = "Puzzle data is invalid."
            return
        }
        let expected = puzzles[index].line[lineIndex]
        guard move.uci == expected else {
            feedback = "Not quite. Try another move."
            board.cancelSelection()
            return
        }
        apply(move)
        lineIndex += 1
        playReplies()
    }

    private func playReplies() {
        guard lineIndex < puzzles[index].line.count else {
            isSolved = true
            feedback = "Solved — excellent find."
            return
        }
        guard let reply = ChessMove(uci: puzzles[index].line[lineIndex]), position.legalMoves().contains(reply) else {
            feedback = "Puzzle data is invalid."
            return
        }
        apply(reply)
        lineIndex += 1
        if lineIndex >= puzzles[index].line.count {
            isSolved = true
            feedback = "Solved — excellent find."
        } else {
            feedback = "Good. Keep going."
        }
    }

    private func apply(_ move: ChessMove) {
        if let next = try? position.applying(move) {
            position = next
            board.complete(move)
        }
    }

    private func openPuzzle(at newIndex: Int) {
        guard puzzles.indices.contains(newIndex), let loaded = try? ChessPosition(fen: puzzles[newIndex].fen) else { return }
        index = newIndex
        startPosition = loaded
        position = loaded
        lineIndex = 0
        isSolved = false
        feedback = "Find the best move"
        board.cancelSelection()
        board.lastMove = nil
        board.isFlipped = loaded.sideToMove == .black
        board.resetFocus(for: loaded.sideToMove)
    }
}
