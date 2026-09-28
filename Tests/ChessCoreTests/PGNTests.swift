import XCTest
@testable import ChessCore

final class PGNTests: XCTestCase {
    func testParseReplayAndExport() throws {
        let text = """
        [Event "Friendly"]
        [Result "*"]

        1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 *
        """
        let pgn = try PGNParser().parse(text)
        let game = try PGNParser().chessGame(from: pgn)
        XCTAssertEqual(game.moves.count, 6)
        XCTAssertEqual(game.moves.map(\.san), ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6"])
        XCTAssertTrue(PGNExporter().export(game: game, tags: pgn.tags).contains("1. e4 e5 2. Nf3 Nc6"))
    }

    func testCommentsAndVariationsAreIgnored() throws {
        let pgn = try PGNParser().parse("1. e4 {main line} e5 (1... c5) ; note\n2. Nf3 *")
        XCTAssertEqual(pgn.moves, ["e4", "e5", "Nf3"])
    }

    func testBlackMoveNumberPrefixIsParsed() throws {
        let pgn = try PGNParser().parse("1... e5 2. Nf3 *")
        XCTAssertEqual(pgn.moves, ["e5", "Nf3"])
    }

    func testFENRoundTrip() throws {
        let fen = "r3k2r/ppp2ppp/2n5/3pp3/8/2N5/PPP2PPP/R3K2R w KQkq d6 4 10"
        XCTAssertEqual(try ChessPosition(fen: fen).fen, fen)
    }
}
