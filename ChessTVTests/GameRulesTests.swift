import XCTest
import ChessCore
@testable import ChessTV

final class GameClockTests: XCTestCase {
    private let blitz = TimeControl(initialSeconds: 180, incrementSeconds: 2)

    func testRunsOnlyAfterBothSidesMoved() {
        let clock = GameClock(timeControl: blitz)
        XCTAssertFalse(clock.runs(atPly: 0))
        XCTAssertFalse(clock.runs(atPly: 1))
        XCTAssertTrue(clock.runs(atPly: 2))
        XCTAssertFalse(GameClock(timeControl: .untimed).runs(atPly: 10))
    }

    func testIncrementAddedOnlyWhileRunning() {
        var clock = GameClock(timeControl: blitz)
        clock.recordMove(by: .white, plyBeforeMove: 0)
        XCTAssertEqual(clock.remaining(.white), 180)
        clock.recordMove(by: .white, plyBeforeMove: 2)
        XCTAssertEqual(clock.remaining(.white), 182)
        XCTAssertEqual(clock.remaining(.black), 180)
    }

    func testConsumeFlagsAtZeroAndNeverGoesNegative() {
        var clock = GameClock(timeControl: TimeControl(initialSeconds: 60, incrementSeconds: 0))
        XCTAssertFalse(clock.consume(50, by: .black))
        XCTAssertTrue(clock.isLow(.black))
        XCTAssertFalse(clock.isLow(.white))
        XCTAssertTrue(clock.consume(20, by: .black))
        XCTAssertEqual(clock.remaining(.black), 0)
        XCTAssertTrue(clock.hasFlagged(.black))
    }

    func testUntimedClockNeverFlags() {
        var clock = GameClock(timeControl: .untimed)
        XCTAssertFalse(clock.consume(1000, by: .white))
        XCTAssertFalse(clock.isLow(.white))
    }
}

final class GameAdjudicationTests: XCTestCase {
    func testOutcomeMapping() {
        XCTAssertNil(GameAdjudication.result(for: .ongoing))
        XCTAssertEqual(GameAdjudication.result(for: .checkmate(winner: .black))?.0, .blackWon)
        XCTAssertEqual(GameAdjudication.result(for: .checkmate(winner: .black))?.1, .checkmate)
        XCTAssertEqual(GameAdjudication.result(for: .stalemate)?.1, .stalemate)
        XCTAssertEqual(GameAdjudication.result(for: .drawThreefoldRepetition)?.1, .repetition)
        XCTAssertEqual(GameAdjudication.result(for: .drawFiftyMove)?.1, .fiftyMoveRule)
        XCTAssertEqual(GameAdjudication.result(for: .drawInsufficientMaterial)?.0, .draw)
    }

    func testTimeoutWinsWithMatingMaterial() throws {
        let position = try ChessPosition(fen: "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")
        let (result, termination) = GameAdjudication.timeout(flagged: .black, in: position)
        XCTAssertEqual(result, .whiteWon)
        XCTAssertEqual(termination, .timeout)
    }

    func testTimeoutAgainstLoneMinorPieceIsDraw() throws {
        let position = try ChessPosition(fen: "4k3/8/8/8/8/8/4P3/2B1K3 w - - 0 1")
        let (result, termination) = GameAdjudication.timeout(flagged: .white, in: position)
        XCTAssertEqual(result, .draw)
        XCTAssertEqual(termination, .timeoutVsInsufficientMaterial)
    }

    func testMatingMaterial() throws {
        let position = try ChessPosition(fen: "4k3/8/8/8/8/8/8/1NB1K2n b - - 0 1")
        XCTAssertTrue(GameAdjudication.hasMatingMaterial(.white, in: position))
        XCTAssertFalse(GameAdjudication.hasMatingMaterial(.black, in: position))
    }

    func testMaterialAndMissingPieces() throws {
        let position = try ChessPosition(fen: "4k3/pppppppp/8/8/8/8/PPPPPPP1/RNBQKBNR w KQ - 0 1")
        XCTAssertEqual(Material.points(.white, in: position), 38)
        XCTAssertEqual(Material.points(.black, in: position), 8)
        XCTAssertEqual(Material.missing(.white, in: position), [.pawn])
        XCTAssertEqual(GameViewModel.materialAdvantage(in: position), [.white: 30, .black: 0])
    }
}

final class DrawOfferPolicyTests: XCTestCase {
    private let start = ChessPosition.initial

    func testAcceptsLateWhenNotClearlyBetter() {
        let evaluation = Evaluation(centipawns: -20)
        XCTAssertTrue(DrawOfferPolicy.botAccepts(evaluation: evaluation, botColor: .white, plyCount: 30, position: start))
        XCTAssertFalse(DrawOfferPolicy.botAccepts(evaluation: evaluation, botColor: .white, plyCount: 29, position: start))
    }

    func testRejectsWhenAhead() {
        // +200 for White is +200 for a White bot and -200 for a Black bot.
        let evaluation = Evaluation(centipawns: 200)
        XCTAssertFalse(DrawOfferPolicy.botAccepts(evaluation: evaluation, botColor: .white, plyCount: 60, position: start))
        XCTAssertTrue(DrawOfferPolicy.botAccepts(evaluation: evaluation, botColor: .black, plyCount: 60, position: start))
    }

    func testAcceptsEarlyInLowMaterialEqualPosition() throws {
        let position = try ChessPosition(fen: "4k3/4r3/8/8/8/8/4R3/4K3 w - - 0 1")
        XCTAssertTrue(DrawOfferPolicy.botAccepts(evaluation: Evaluation(centipawns: 40), botColor: .black, plyCount: 4, position: position))
        XCTAssertFalse(DrawOfferPolicy.botAccepts(evaluation: Evaluation(centipawns: 80), botColor: .black, plyCount: 4, position: position))
    }

    func testMateScores() {
        XCTAssertEqual(DrawOfferPolicy.score(Evaluation(centipawns: 0, mateIn: 3), for: .white), 100_000)
        XCTAssertEqual(DrawOfferPolicy.score(Evaluation(centipawns: 0, mateIn: 3), for: .black), -100_000)
        XCTAssertFalse(DrawOfferPolicy.botAccepts(evaluation: Evaluation(centipawns: 0, mateIn: -2), botColor: .black, plyCount: 80, position: start))
    }
}

final class GameViewModelRulesTests: XCTestCase {
    func testBotThinkDelay() {
        XCTAssertEqual(GameViewModel.botThinkDelay(legalMoveCount: 0), 0.4, accuracy: 1e-9)
        XCTAssertEqual(GameViewModel.botThinkDelay(legalMoveCount: 20), 0.8, accuracy: 1e-9)
        XCTAssertEqual(GameViewModel.botThinkDelay(legalMoveCount: 80), 1.2, accuracy: 1e-9)
    }

    func testBlunderDetection() {
        let before = Evaluation(centipawns: 50)
        XCTAssertTrue(GameViewModel.isBlunder(before: before, after: Evaluation(centipawns: -200), by: .white))
        XCTAssertFalse(GameViewModel.isBlunder(before: before, after: Evaluation(centipawns: -199), by: .white))
        XCTAssertTrue(GameViewModel.isBlunder(before: Evaluation(centipawns: -50), after: Evaluation(centipawns: 200), by: .black))
        XCTAssertTrue(GameViewModel.isBlunder(before: before, after: Evaluation(centipawns: 0, mateIn: -3), by: .white))
    }

    func testTakebackPlies() {
        XCTAssertEqual(GameViewModel.takebackPlies(plyCount: 2, sideToMove: .white, humanColor: .white), 2)
        XCTAssertEqual(GameViewModel.takebackPlies(plyCount: 1, sideToMove: .black, humanColor: .white), 1)
        XCTAssertEqual(GameViewModel.takebackPlies(plyCount: 1, sideToMove: .black, humanColor: .black), 0)
        XCTAssertEqual(GameViewModel.takebackPlies(plyCount: 0, sideToMove: .white, humanColor: .white), 0)
        XCTAssertEqual(GameViewModel.takebackPlies(plyCount: 3, sideToMove: .black, humanColor: nil), 1)
        XCTAssertEqual(GameViewModel.takebackPlies(plyCount: 0, sideToMove: .white, humanColor: nil), 0)
    }

    func testResultTitles() {
        XCTAssertEqual(GameViewModel.resultTitle(.whiteWon, humanColor: .white), "You Won!")
        XCTAssertEqual(GameViewModel.resultTitle(.whiteWon, humanColor: .black), "You Lost")
        XCTAssertEqual(GameViewModel.resultTitle(.blackWon, humanColor: nil), "Black Won")
        XCTAssertEqual(GameViewModel.resultTitle(.whiteWon, humanColor: nil), "White Won")
        XCTAssertEqual(GameViewModel.resultTitle(.draw, humanColor: .white), "Draw")
    }

    func testMoveRows() throws {
        var game = ChessGame()
        for uci in ["e2e4", "e7e5", "g1f3"] { try game.makeMove(XCTUnwrap(ChessMove(uci: uci))) }
        XCTAssertEqual(GameViewModel.moveRows(game.moves), [
            MoveRow(number: 1, white: "e4", black: "e5"),
            MoveRow(number: 2, white: "Nf3", black: nil)
        ])
    }

    func testChatEvents() {
        XCTAssertEqual(GameViewModel.chatEvent(moveByBot: true, isCapture: true, givesCheck: true), .check)
        XCTAssertEqual(GameViewModel.chatEvent(moveByBot: true, isCapture: true, givesCheck: false), .botCaptures)
        XCTAssertEqual(GameViewModel.chatEvent(moveByBot: false, isCapture: true, givesCheck: true), .playerCaptures)
        XCTAssertNil(GameViewModel.chatEvent(moveByBot: false, isCapture: false, givesCheck: false))
    }
}
