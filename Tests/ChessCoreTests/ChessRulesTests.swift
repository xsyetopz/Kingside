import XCTest
@testable import ChessCore

final class ChessRulesTests: XCTestCase {
    func testInitialPositionHasTwentyMoves() {
        XCTAssertEqual(ChessPosition.initial.legalMoves().count, 20)
    }

    func testNormalMoveAndCapture() throws {
        var game = ChessGame()
        try game.makeMove(XCTUnwrap(ChessMove(uci: "e2e4")))
        try game.makeMove(XCTUnwrap(ChessMove(uci: "d7d5")))
        try game.makeMove(XCTUnwrap(ChessMove(uci: "e4d5")))
        XCTAssertEqual(game.position[Square(algebraic: "d5")!], Piece(type: .pawn, color: .white))
        XCTAssertNil(game.position[Square(algebraic: "e4")!])
    }

    func testIllegalMoveRejected() {
        XCTAssertThrowsError(try ChessPosition.initial.applying(ChessMove(uci: "e2e5")!))
    }

    func testPinnedPieceCannotExposeKing() throws {
        let position = try ChessPosition(fen: "4r1k1/8/8/8/8/8/4R3/4K3 w - - 0 1")
        XCTAssertFalse(position.legalMoves().contains(ChessMove(uci: "e2d2")!))
        XCTAssertTrue(position.legalMoves().contains(ChessMove(uci: "e2e8")!))
    }

    func testCastlingMovesRook() throws {
        let position = try ChessPosition(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        let next = try position.applying(ChessMove(uci: "e1g1")!)
        XCTAssertEqual(next[Square(algebraic: "f1")!], Piece(type: .rook, color: .white))
        XCTAssertEqual(next[Square(algebraic: "g1")!], Piece(type: .king, color: .white))
    }

    func testCannotCastleThroughCheck() throws {
        let position = try ChessPosition(fen: "4k3/8/8/8/2b5/8/8/4K2R w K - 0 1")
        XCTAssertFalse(position.legalMoves().contains(ChessMove(uci: "e1g1")!))
    }

    func testEnPassant() throws {
        var position = try ChessPosition(fen: "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2")
        try position.apply(ChessMove(uci: "e5d6")!)
        XCTAssertNil(position[Square(algebraic: "d5")!])
        XCTAssertEqual(position[Square(algebraic: "d6")!], Piece(type: .pawn, color: .white))
    }

    func testPromotion() throws {
        let position = try ChessPosition(fen: "4k3/P7/8/8/8/8/8/4K3 w - - 0 1")
        let next = try position.applying(ChessMove(uci: "a7a8q")!)
        XCTAssertEqual(next[Square(algebraic: "a8")!]?.type, .queen)
        XCTAssertEqual(next.halfmoveClock, 0)
    }

    func testFoolsMateCheckmate() throws {
        var game = ChessGame()
        for uci in ["f2f3", "e7e5", "g2g4", "d8h4"] { try game.makeMove(ChessMove(uci: uci)!) }
        XCTAssertEqual(game.position.outcome, .checkmate(winner: .black))
    }

    func testStalemate() throws {
        let position = try ChessPosition(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")
        XCTAssertEqual(position.outcome, .stalemate)
    }

    func testDoubleCheckAllowsOnlyKingMoves() throws {
        let position = try ChessPosition(fen: "4k3/8/8/1B6/8/8/4R3/4K3 b - - 0 1")
        XCTAssertTrue(position.isInCheck(.black))
        XCTAssertTrue(position.legalMoves().allSatisfy { position[$0.from]?.type == .king })
    }

    func testDiscoveredCheck() throws {
        let position = try ChessPosition(fen: "4k3/8/8/8/8/8/4B3/4R1K1 w - - 0 1")
        let next = try position.applying(ChessMove(uci: "e2b5")!)
        XCTAssertTrue(next.isInCheck(.black))
    }

    func testKingCannotMoveIntoCheck() throws {
        let position = try ChessPosition(fen: "4k3/8/8/8/8/8/3r4/4K3 w - - 0 1")
        XCTAssertFalse(position.legalMoves().contains(ChessMove(uci: "e1d1")!))
    }
}
