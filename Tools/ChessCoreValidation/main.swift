import ChessCore
import Foundation

enum ValidationFailure: Error { case failed(String) }

func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
    guard try condition() else { throw ValidationFailure.failed(message) }
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

    let engineMove = try await NativeSearchEngine().bestMove(position: .initial, difficulty: .beginner)
    try require(ChessPosition.initial.legalMoves().contains(engineMove), "native engine move")

    print("ChessCore validation passed")
} catch {
    fputs("ChessCore validation failed: \(error)\n", stderr)
    exit(1)
}
