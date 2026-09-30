import ChessCore
import ChessPlay
import Testing
@testable import ChessUI

struct ReviewLayoutTests {
    @Test func stepsStayInsideTheGame() {
        #expect(ReviewLayout.ply(3, step: .next, moveCount: 10) == 4)
        #expect(ReviewLayout.ply(10, step: .next, moveCount: 10) == 10)
        #expect(ReviewLayout.ply(3, step: .previous, moveCount: 10) == 2)
        #expect(ReviewLayout.ply(0, step: .previous, moveCount: 10) == 0)
        #expect(ReviewLayout.ply(3, step: .first, moveCount: 10) == 0)
        #expect(ReviewLayout.ply(3, step: .last, moveCount: 10) == 10)
        #expect(ReviewLayout.ply(0, step: .next, moveCount: 0) == 0)
    }

    @Test func boardDirectionsBrowse() {
        #expect(ReviewLayout.step(for: .left) == .previous)
        #expect(ReviewLayout.step(for: .right) == .next)
        #expect(ReviewLayout.step(for: .up) == .first)
        #expect(ReviewLayout.step(for: .down) == .last)
    }

    @Test func rowsPairMovesAndKeepAnUnansweredMove() {
        let rows = ReviewLayout.rows(moveCount: 3)
        #expect(rows == [
            ReviewLayout.Row(number: 1, whitePly: 1, blackPly: 2),
            ReviewLayout.Row(number: 2, whitePly: 3, blackPly: nil)
        ])
        #expect(ReviewLayout.rows(moveCount: 0).isEmpty)
    }

    @Test func snapshotIsDisplayOnlyAndMarksTheLastMoveAndCheck() throws {
        let start = ReviewLayout.snapshot(.initial, lastMove: nil, orientation: .black)
        #expect(start.orientation == .black)
        #expect(!start.isInputEnabled)
        #expect(start.checkSquare == nil)
        #expect(start.pieces.count == 32)

        var game = ChessGame()
        var last: ChessMove?
        for uci in ["e2e4", "f7f6", "d1h5"] {
            last = try #require(ChessMove(uci: uci))
            _ = try game.makeMove(#require(last))
        }
        let checked = ReviewLayout.snapshot(game.position, lastMove: last, orientation: .white)
        #expect(checked.lastMove == last)
        #expect(checked.checkSquare == Square(algebraic: "e8"))
    }
}
