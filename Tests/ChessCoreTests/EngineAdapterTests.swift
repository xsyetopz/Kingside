import XCTest
@testable import ChessCore

private struct StubStockfishBridge: StockfishBridge {
    let move: String
    let evaluationValue: Evaluation
    func bestMove(fen: String, depth: Int, timeLimit: Duration) async throws -> String { move }
    func evaluation(fen: String) async throws -> Evaluation { evaluationValue }
}

final class EngineAdapterTests: XCTestCase {
    func testStockfishAdapterAcceptsLegalUCI() async throws {
        let bridge = StubStockfishBridge(move: "e2e4", evaluationValue: Evaluation(centipawns: 25))
        let engine = StockfishEngine(bridge: bridge)
        let move = try await engine.bestMove(position: .initial, difficulty: .beginner)
        let evaluation = try await engine.evaluate(position: .initial)
        XCTAssertEqual(move, ChessMove(uci: "e2e4"))
        XCTAssertEqual(evaluation, Evaluation(centipawns: 25))
    }

    func testStockfishAdapterRejectsIllegalUCI() async {
        let engine = StockfishEngine(bridge: StubStockfishBridge(move: "e2e5", evaluationValue: Evaluation(centipawns: 0)))
        do {
            _ = try await engine.bestMove(position: .initial, difficulty: .beginner)
            XCTFail("Expected invalid engine move")
        } catch {
            XCTAssertEqual(error as? ChessEngineError, .unavailable("Stockfish returned an invalid move"))
        }
    }
}
