import XCTest
@testable import ChessCore

final class EngineAdapterTests: XCTestCase {
    private static let kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"

    private func perft(_ fen: String, _ depth: Int) throws -> Int {
        var board = EngineBoard(try ChessPosition(fen: fen))
        defer { board.deallocate() }
        return board.perft(depth)
    }

    func testPerftStartPosition() throws {
        let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
        XCTAssertEqual(try perft(fen, 1), 20)
        XCTAssertEqual(try perft(fen, 2), 400)
        XCTAssertEqual(try perft(fen, 3), 8_902)
        XCTAssertEqual(try perft(fen, 4), 197_281)
    }

    func testPerftKiwipete() throws {
        XCTAssertEqual(try perft(Self.kiwipete, 1), 48)
        XCTAssertEqual(try perft(Self.kiwipete, 2), 2_039)
        XCTAssertEqual(try perft(Self.kiwipete, 3), 97_862)
    }

    func testPerftEnPassantAndPromotionEdgeCases() throws {
        // Position 3 and position 4 from the standard perft suite.
        let position3 = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
        XCTAssertEqual(try perft(position3, 1), 14)
        XCTAssertEqual(try perft(position3, 2), 191)
        XCTAssertEqual(try perft(position3, 3), 2_812)
        XCTAssertEqual(try perft(position3, 4), 43_238)
        XCTAssertEqual(try perft("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 3), 9_467)
    }

    func testInternalLegalMovesMatchChessPosition() throws {
        for fen in [Self.kiwipete, "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"] {
            let position = try ChessPosition(fen: fen)
            var board = EngineBoard(position)
            defer { board.deallocate() }
            XCTAssertEqual(Set(board.legalMoves().map(\.chessMove)), Set(position.legalMoves()), fen)
        }
    }

    func testIncrementalHashMatchesRecomputedHash() throws {
        var board = EngineBoard(try ChessPosition(fen: Self.kiwipete))
        defer { board.deallocate() }
        var generator = SplitMix(seed: 7)
        for _ in 0..<200 {
            let moves = board.legalMoves()
            guard !moves.isEmpty else { break }
            board.make(moves[Int(generator.next() % UInt64(moves.count))])
            XCTAssertEqual(board.hash, board.computeHash())
        }
    }

    func testFindsMateInOne() async throws {
        let position = try ChessPosition(fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1")
        let analysis = try await ChessEngine().analyze(position: position, limit: .depth(3))
        XCTAssertEqual(analysis.bestMove, ChessMove(uci: "d1d8"))
        XCTAssertEqual(analysis.evaluation.mateIn, 1)
    }

    func testFindsMateInTwo() async throws {
        // 1. Rd8+ Rxd8 (forced) 2. Rxd8#.
        let position = try ChessPosition(fen: "2r3k1/5ppp/8/8/8/8/3R1PPP/3R2K1 w - - 0 1")
        let analysis = try await ChessEngine().analyze(position: position, limit: .depth(5))
        XCTAssertEqual(analysis.evaluation.mateIn, 2)
        XCTAssertEqual(analysis.bestMove, ChessMove(uci: "d2d8"))
        XCTAssertEqual(analysis.principalVariation.first, analysis.bestMove)
    }

    func testTakesHangingQueen() async throws {
        let game = ChessGame(position: try ChessPosition(fen: "rnb1kbnr/pppp1ppp/8/4p1q1/4P3/3P4/PPP2PPP/RNBQKBNR w KQkq - 0 1"))
        let move = try await ChessEngine().bestMove(game: game, strength: EngineStrength(elo: 2200))
        XCTAssertEqual(move, ChessMove(uci: "c1g5"))
    }

    func testLowStrengthReturnsLegalMoves() async throws {
        let engine = ChessEngine()
        var game = ChessGame()
        for _ in 0..<12 {
            guard !game.position.legalMoves().isEmpty else { break }
            let move = try await engine.bestMove(game: game, strength: EngineStrength(elo: 250))
            XCTAssertTrue(game.position.legalMoves().contains(move))
            try game.makeMove(move)
        }
    }

    func testAnalysisScoresFromWhitePointOfView() async throws {
        let engine = ChessEngine()
        // White is a queen up; the score is positive whoever is to move.
        let whiteToMove = try ChessPosition(fen: "4k3/8/8/8/8/8/8/3QK3 w - - 0 1")
        let blackToMove = try ChessPosition(fen: "4k3/8/8/8/8/8/8/3QK3 b - - 0 1")
        let first = try await engine.analyze(position: whiteToMove, limit: .depth(2))
        let second = try await engine.analyze(position: blackToMove, limit: .depth(2))
        XCTAssertGreaterThan(first.evaluation.centipawns, 500)
        XCTAssertGreaterThan(second.evaluation.centipawns, 500)
        XCTAssertNotNil(first.secondBestEvaluation)

        // Black mates in one: the mate count is negative.
        let blackMates = try ChessPosition(fen: "3r2k1/8/8/8/8/8/5PPP/6K1 b - - 0 1")
        let mate = try await engine.analyze(position: blackMates, limit: .depth(3))
        XCTAssertEqual(mate.evaluation.mateIn, -1)
        XCTAssertLessThan(mate.evaluation.centipawns, 0)

        // Already checkmated: no move, mate 0, sign shows the winner.
        let mated = try ChessPosition(fen: "3R2k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1")
        let over = try await engine.analyze(position: mated, limit: .depth(3))
        XCTAssertNil(over.bestMove)
        XCTAssertEqual(over.evaluation.mateIn, 0)
        XCTAssertGreaterThan(over.evaluation.centipawns, 0)
    }

    func testRepetitionInHistoryScoresAsDraw() async throws {
        // White has a bare king against king and queen. After Kb1 Qc6 Ka1 Qc5 the start
        // position is back on the board, so Kb1 now repeats a position from the history.
        var game = ChessGame(position: try ChessPosition(fen: "7k/8/8/2q5/8/8/8/K7 w - - 0 1"))
        for uci in ["a1b1", "c5c6", "b1a1", "c6c5"] { try game.makeMove(XCTUnwrap(ChessMove(uci: uci))) }
        let engine = ChessEngine()
        let withHistory = try await engine.analyze(
            position: game.position, history: game.moves.map(\.positionBefore), limit: .depth(4)
        )
        XCTAssertEqual(withHistory.evaluation.centipawns, 0)
        XCTAssertEqual(withHistory.bestMove, ChessMove(uci: "a1b1"))

        let withoutHistory = try await ChessEngine().analyze(position: game.position, limit: .depth(4))
        XCTAssertLessThan(withoutHistory.evaluation.centipawns, -500)
    }

    func testCancellationStopsSearch() async throws {
        let engine = ChessEngine()
        let task = Task { try await engine.analyze(position: .initial, limit: .time(.seconds(30))) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {}
    }

    func testStrengthSettingsScaleWithElo() {
        let weak = EngineStrength(elo: 100)
        let strong = EngineStrength(elo: 3000)
        XCTAssertEqual(weak.elo, 250)
        XCTAssertEqual(strong.elo, 2200)
        XCTAssertEqual(weak.searchDepth, 1)
        XCTAssertLessThan(weak.searchDepth, EngineStrength(elo: 1500).searchDepth)
        XCTAssertGreaterThan(weak.evaluationNoise, EngineStrength(elo: 1500).evaluationNoise)
        XCTAssertEqual(strong.evaluationNoise, 0)
        XCTAssertEqual(strong.mistakeChance, 0)
    }
}

private struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
