import ChessCore
import ChessPlay
// Foundation provides `CGPoint`, `CGSize`, and `CGFloat`; unused_import does not attribute them.
// swiftlint:disable:next unused_import
import Foundation
import Testing
@testable import ChessUI

struct ReviewLayoutTests {
  @Test
  func stepsStayInsideTheGame() {
    #expect(ReviewLayout.ply(3, step: .next, moveCount: 10) == 4)
    #expect(ReviewLayout.ply(10, step: .next, moveCount: 10) == 10)
    #expect(ReviewLayout.ply(3, step: .previous, moveCount: 10) == 2)
    #expect(ReviewLayout.ply(0, step: .previous, moveCount: 10) == 0)
    #expect(ReviewLayout.ply(3, step: .first, moveCount: 10) == 0)
    #expect(ReviewLayout.ply(3, step: .last, moveCount: 10) == 10)
    #expect(ReviewLayout.ply(0, step: .next, moveCount: 0) == 0)
  }

  @Test
  func boardDirectionsBrowse() {
    #expect(ReviewLayout.step(for: .left) == .previous)
    #expect(ReviewLayout.step(for: .right) == .next)
    #expect(ReviewLayout.step(for: .up) == .first)
    #expect(ReviewLayout.step(for: .down) == .last)
  }

  @Test
  func rowsPairMovesAndKeepAnUnansweredMove() {
    let rows = ReviewLayout.rows(moveCount: 3)
    #expect(
      rows == [
        ReviewLayout.Row(number: 1, whitePly: 1, blackPly: 2),
        ReviewLayout.Row(number: 2, whitePly: 3, blackPly: nil),
      ]
    )
    #expect(ReviewLayout.rows(moveCount: 0).isEmpty)
  }

  @Test
  func snapshotIsDisplayOnlyAndMarksTheLastMoveAndCheck() throws {
    let start = ReviewLayout.snapshot(.initial, lastMove: nil, orientation: .black)
    #expect(start.orientation == .black)
    #expect(!start.isInputEnabled)
    #expect(start.checkSquare == nil)
    #expect(start.pieces.count == 32)

    var game = ChessGame()
    var last: ChessMove?
    for uci in ["e2e4", "f7f6", "d1h5"] {
      let move = try #require(ChessMove(uci: uci))
      _ = try game.makeMove(move)
      last = move
    }
    let checked = ReviewLayout.snapshot(game.position, lastMove: last, orientation: .white)
    #expect(checked.lastMove == last)
    #expect(checked.checkSquare == Square(algebraic: "e8"))
  }

  @Test
  func graphRisesWithWhitesChancesAcrossTheWidth() {
    let size = CGSize(width: 200, height: 100)
    let points = ReviewLayout.graphPoints([0.5, 1, 0, 1.5], moveCount: 4, in: size)
    #expect(
      points == [
        CGPoint(x: 0, y: 50), CGPoint(x: 50, y: 0), CGPoint(x: 100, y: 100), CGPoint(x: 150, y: 0),
      ]
    )
    #expect(ReviewLayout.graphPoints([0.5], moveCount: 0, in: size) == [CGPoint(x: 0, y: 50)])
    #expect(ReviewLayout.graphX(ply: 4, moveCount: 4, width: 200) == 200)
  }

  @Test
  func graphClicksPickTheNearestPly() {
    #expect(ReviewLayout.graphPly(atX: 0, width: 200, moveCount: 4) == 0)
    #expect(ReviewLayout.graphPly(atX: 70, width: 200, moveCount: 4) == 1)
    #expect(ReviewLayout.graphPly(atX: 80, width: 200, moveCount: 4) == 2)
    #expect(ReviewLayout.graphPly(atX: 250, width: 200, moveCount: 4) == 4)
    #expect(ReviewLayout.graphPly(atX: -5, width: 200, moveCount: 4) == 0)
    #expect(ReviewLayout.graphPly(atX: 50, width: 0, moveCount: 4) == 0)
  }

  @Test
  func annotatedGradesUseChessNotation() {
    #expect(MoveClassification.brilliant.mark == .annotation("!!"))
    #expect(MoveClassification.great.mark == .annotation("!"))
    #expect(MoveClassification.inaccuracy.mark == .annotation("?!"))
    #expect(MoveClassification.mistake.mark == .annotation("?"))
    #expect(MoveClassification.blunder.mark == .annotation("??"))
  }
}
