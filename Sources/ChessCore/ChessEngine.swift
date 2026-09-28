import Foundation

public enum EngineDifficulty: String, Codable, CaseIterable, Sendable {
    case beginner, easy, medium, hard, expert

    public var searchDepth: Int {
        switch self {
        case .beginner: 1
        case .easy: 2
        case .medium: 3
        case .hard: 4
        case .expert: 5
        }
    }

    public var thinkTime: Duration {
        switch self {
        case .beginner: .milliseconds(120)
        case .easy: .milliseconds(250)
        case .medium: .milliseconds(600)
        case .hard: .seconds(1)
        case .expert: .seconds(2)
        }
    }
}

public struct Evaluation: Codable, Equatable, Sendable {
    public let centipawns: Int
    public let mateIn: Int?
    public init(centipawns: Int, mateIn: Int? = nil) {
        self.centipawns = centipawns
        self.mateIn = mateIn
    }
}

public protocol ChessEngine: Sendable {
    func bestMove(position: ChessPosition, difficulty: EngineDifficulty) async throws -> ChessMove
    func evaluate(position: ChessPosition) async throws -> Evaluation
}

public enum ChessEngineError: Error, Equatable {
    case noLegalMove
    case cancelled
    case unavailable(String)
}

/// A deterministic, fully local fallback used when a separately licensed Stockfish build is not linked.
/// Search runs in an actor and yields cooperatively, so it never blocks the UI actor.
public actor NativeSearchEngine: ChessEngine {
    private enum SearchStop: Error { case deadline }

    public init() {}

    public func bestMove(position: ChessPosition, difficulty: EngineDifficulty) async throws -> ChessMove {
        let moves = position.legalMoves()
        guard !moves.isEmpty else { throw ChessEngineError.noLegalMove }
        var best = moves[0]
        var bestScore = Int.min
        let deadline = ContinuousClock.now.advanced(by: difficulty.thinkTime)
        for move in moves {
            try Task.checkCancellation()
            do {
                let next = try position.applying(move)
                let score = try -negamax(next, depth: difficulty.searchDepth - 1, alpha: -1_000_000, beta: 1_000_000, deadline: deadline)
                if score > bestScore || (score == bestScore && move.uci < best.uci) {
                    best = move
                    bestScore = score
                }
            } catch SearchStop.deadline {
                break
            }
            await Task.yield()
        }
        return best
    }

    public func evaluate(position: ChessPosition) async throws -> Evaluation {
        try Task.checkCancellation()
        return Evaluation(centipawns: staticEvaluation(position) * (position.sideToMove == .white ? 1 : -1))
    }

    private func negamax(_ position: ChessPosition, depth: Int, alpha: Int, beta: Int, deadline: ContinuousClock.Instant) throws -> Int {
        try Task.checkCancellation()
        if ContinuousClock.now >= deadline { throw SearchStop.deadline }
        switch position.outcome {
        case .checkmate: return -100_000 - depth
        case .stalemate, .drawFiftyMove: return 0
        case .ongoing: break
        }
        if depth <= 0 { return staticEvaluation(position) * (position.sideToMove == .white ? 1 : -1) }
        var alpha = alpha
        for move in ordered(position.legalMoves(), in: position) {
            guard let next = try? position.applying(move) else { continue }
            let score = try -negamax(next, depth: depth - 1, alpha: -beta, beta: -alpha, deadline: deadline)
            if score >= beta { return beta }
            alpha = max(alpha, score)
        }
        return alpha
    }

    private func ordered(_ moves: [ChessMove], in position: ChessPosition) -> [ChessMove] {
        moves.sorted {
            let leftCapture = position[$0.to] != nil ? 1 : 0
            let rightCapture = position[$1.to] != nil ? 1 : 0
            return leftCapture == rightCapture ? $0.uci < $1.uci : leftCapture > rightCapture
        }
    }

    private func staticEvaluation(_ position: ChessPosition) -> Int {
        let values: [PieceType: Int] = [.pawn: 100, .knight: 320, .bishop: 330, .rook: 500, .queen: 900, .king: 0]
        return position.board.reduce(into: 0) { score, entry in
            let value = values[entry.value.type, default: 0]
            score += entry.value.color == .white ? value : -value
        }
    }
}

/// Integration seam for a GPL-compatible embedded Stockfish library. A concrete bridge can be
/// injected without importing engine symbols into the domain or UI layers.
public protocol StockfishBridge: Sendable {
    func bestMove(fen: String, depth: Int, timeLimit: Duration) async throws -> String
    func evaluation(fen: String) async throws -> Evaluation
}

public actor StockfishEngine: ChessEngine {
    private let bridge: any StockfishBridge

    public init(bridge: any StockfishBridge) { self.bridge = bridge }

    public func bestMove(position: ChessPosition, difficulty: EngineDifficulty) async throws -> ChessMove {
        let uci = try await bridge.bestMove(fen: position.fen, depth: difficulty.searchDepth, timeLimit: difficulty.thinkTime)
        guard let move = ChessMove(uci: uci), position.legalMoves().contains(move) else {
            throw ChessEngineError.unavailable("Stockfish returned an invalid move")
        }
        return move
    }

    public func evaluate(position: ChessPosition) async throws -> Evaluation {
        try await bridge.evaluation(fen: position.fen)
    }
}
