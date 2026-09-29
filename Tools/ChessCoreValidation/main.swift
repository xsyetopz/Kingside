import ChessCore
import Foundation

enum ValidationFailure: Error { case failed(String) }

func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw ValidationFailure.failed(message) }
}

/// Fixed-depth searches with a fresh engine per position; prints nodes per second.
func runBench() async throws {
    let positions: [(name: String, fen: String, depth: Int)] = [
        ("start", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 12),
        ("kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 10),
        ("middlegame", "r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R1BQKB1R w KQ - 0 7", 10),
        ("endgame", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 16),
    ]
    var totalNodes = 0
    var totalSeconds = 0.0
    for entry in positions {
        let position = try ChessPosition(fen: entry.fen)
        let clock = ContinuousClock()
        var analysis: EngineAnalysis?
        let elapsed = try await clock.measure {
            analysis = try await ChessEngine().analyze(position: position, limit: .depth(entry.depth))
        }
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let nodes = analysis?.nodes ?? 0
        totalNodes += nodes
        totalSeconds += seconds
        let best = analysis?.bestMove?.uci ?? "-"
        print("\(entry.name): depth \(entry.depth) nodes \(nodes) time \(String(format: "%.2f", seconds)) s "
            + "nps \(Int(Double(nodes) / max(seconds, 1e-9))) best \(best) score \(analysis?.evaluation.centipawns ?? 0)")
    }
    print("total: nodes \(totalNodes) time \(String(format: "%.2f", totalSeconds)) s nps \(Int(Double(totalNodes) / max(totalSeconds, 1e-9)))")
}

if CommandLine.arguments.dropFirst().first == "bench" {
    do {
        try await runBench()
        exit(0)
    } catch {
        fputs("bench failed: \(error)\n", stderr)
        exit(1)
    }
}

do {
    try require(ChessPosition.initial.legalMoves().count == 20, "initial move count")

    var game = ChessGame()
    for uci in ["f2f3", "e7e5", "g2g4", "d8h4"] {
        try game.makeMove(ChessMove(uci: uci)!)
    }
    try require(game.position.outcome == .checkmate(winner: .black), "checkmate")

    let stalemate = try ChessPosition(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
    try require(stalemate.outcome == .stalemate, "stalemate")

    let castle = try ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        .applying(ChessMove(uci: "e1g1")!)
    try require(castle[Square(algebraic: "f1")!]?.type == .rook, "castling")

    let enPassant = try ChessPosition(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2")
        .applying(ChessMove(uci: "e5d6")!)
    try require(enPassant[Square(algebraic: "d5")!] == nil, "en passant")

    let promotion = try ChessPosition(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        .applying(ChessMove(uci: "a7a8q")!)
    try require(promotion[Square(algebraic: "a8")!]?.type == .queen, "promotion")

    let pinned = try ChessPosition(fen: "4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1")
    try require(!pinned.legalMoves().contains(ChessMove(uci: "e2d2")!), "pin")

    let pgn = try PGNParser().parse("[Event \"Validation\"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *")
    let replayed = try PGNParser().chessGame(from: pgn)
    try require(replayed.moves.count == 6, "PGN replay")
    try require(PGNExporter().export(game: replayed).contains("1. e4 e5"), "PGN export")

    let engineMove = try await ChessEngine().bestMove(game: ChessGame(), strength: EngineStrength(elo: 250))
    try require(ChessPosition.initial.legalMoves().contains(engineMove), "engine move")

    print("ChessCore validation passed")
} catch {
    fputs("ChessCore validation failed: \(error)\n", stderr)
    exit(1)
}
