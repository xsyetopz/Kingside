import XCTest
import ChessCore
@testable import ChessTV

final class ReviewTests: XCTestCase {
    private func context(
        _ mover: PieceColor = .white,
        best: Int,
        played: Int,
        second: Int? = nil,
        playedBest: Bool = false,
        isBook: Bool = false,
        sacrifice: Int = 0,
        previous: MoveClassification? = nil
    ) -> MoveContext {
        MoveContext(
            mover: mover,
            bestEvaluation: Evaluation(centipawns: best),
            playedEvaluation: Evaluation(centipawns: played),
            secondBestEvaluation: second.map { Evaluation(centipawns: $0) },
            playedBest: playedBest,
            isBook: isBook,
            materialGivenUp: sacrifice,
            previous: previous
        )
    }

    private func classify(_ context: MoveContext) -> MoveClassification { MoveClassifier.classify(context) }

    // MARK: Win probability

    func testWinProbabilityIsEvenAtZeroAndCertainForMates() {
        XCTAssertEqual(WinProbability.white(Evaluation(centipawns: 0)), 0.5, accuracy: 1e-9)
        XCTAssertEqual(WinProbability.white(Evaluation(centipawns: 19_995, mateIn: 3)), 1)
        XCTAssertEqual(WinProbability.white(Evaluation(centipawns: -19_996, mateIn: -2)), 0)
        XCTAssertEqual(WinProbability.white(Evaluation(centipawns: -20_000, mateIn: 0)), 0)
        // 1 / (1 + e^-0.368208) for one pawn.
        XCTAssertEqual(WinProbability.white(Evaluation(centipawns: 100)), 0.59103, accuracy: 1e-4)
        XCTAssertEqual(WinProbability.forSide(.black, Evaluation(centipawns: 100)), 0.40897, accuracy: 1e-4)
    }

    // MARK: Classification

    func testLossGradesUseThresholds() {
        XCTAssertEqual(classify(context(best: 50, played: 40)), .excellent)   // loss ~0.009
        XCTAssertEqual(classify(context(best: 0, played: -35)), .good)        // loss ~0.032
        XCTAssertEqual(classify(context(best: 0, played: -80)), .inaccuracy)  // loss ~0.073
        XCTAssertEqual(classify(context(best: 0, played: -200)), .mistake)    // loss ~0.176
        XCTAssertEqual(classify(context(best: 0, played: -300)), .blunder)    // loss ~0.251
    }

    func testLossIsFromTheMoversPointOfView() {
        XCTAssertEqual(classify(context(.black, best: 0, played: 300)), .blunder)
        XCTAssertEqual(classify(context(.black, best: 0, played: -300)), .excellent)
        XCTAssertEqual(context(best: 0, played: 200).loss, 0)
    }

    func testBookMovesLoseNothing() {
        // Short searches rate theory moves a few centipawns apart; that noise must not cost accuracy.
        XCTAssertEqual(context(best: 40, played: -20, isBook: true).loss, 0)
    }

    func testPlayingTheEngineMoveIsBestOrGreatWhenItIsTheOnlyGoodMove() {
        XCTAssertEqual(classify(context(best: 30, played: -10, playedBest: true)), .best)
        XCTAssertEqual(classify(context(best: 0, played: 0, second: -100, playedBest: true)), .best)
        XCTAssertEqual(classify(context(best: 0, played: 0, second: -300, playedBest: true)), .great)
    }

    func testBrilliantNeedsSacrificeAndAGoodPosition() {
        XCTAssertEqual(classify(context(best: 150, played: 150, playedBest: true, sacrifice: 3)), .brilliant)
        XCTAssertEqual(classify(context(best: 150, played: 150, playedBest: true, sacrifice: 1)), .best)
        XCTAssertEqual(classify(context(best: -300, played: -300, playedBest: true, sacrifice: 3)), .best)
        XCTAssertEqual(classify(context(best: 150, played: -50, sacrifice: 5)), .mistake)
    }

    func testBookWinsOverEverything() {
        XCTAssertEqual(classify(context(best: 0, played: -300, isBook: true)), .book)
    }

    func testMissWhenNotPunishingAnOpponentError() {
        XCTAssertEqual(classify(context(best: 500, played: 150, previous: .blunder)), .miss)
        XCTAssertEqual(classify(context(best: 500, played: 150, previous: .good)), .blunder)
        // Dropping to a worse position than equal is a plain error, not a miss.
        XCTAssertEqual(classify(context(best: 500, played: -100, previous: .mistake)), .blunder)
        // Nothing big to win: an ordinary grade.
        XCTAssertEqual(classify(context(best: 50, played: -150, previous: .mistake)), .mistake)
    }

    // MARK: Accuracy

    func testAccuracyFormula() {
        XCTAssertNil(AccuracyCalculator.accuracy(losses: []))
        XCTAssertEqual(AccuracyCalculator.accuracy(losses: [0, 0])!, 100, accuracy: 0.001)
        // 103.1668 * e^(-0.4354) - 3.1669 for a 10% average loss.
        XCTAssertEqual(AccuracyCalculator.accuracy(losses: [0.05, 0.15])!, 63.585, accuracy: 0.01)
        XCTAssertEqual(AccuracyCalculator.accuracy(losses: [1, 1]), 0)
    }

    // MARK: Opening book

    func testBookPlyCountFollowsTheLongestMatchingLine() {
        XCTAssertEqual(OpeningBook.bookPlyCount(for: ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "h3"]), 6)
        XCTAssertEqual(OpeningBook.bookPlyCount(for: ["e4", "e5", "Qh5"]), 2)
        XCTAssertEqual(OpeningBook.bookPlyCount(for: ["h4"]), 0)
        XCTAssertEqual(OpeningBook.bookPlyCount(for: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Nf6", "Ng5", "d5", "exd5", "Na5"]), 10)
    }

    func testEveryBookLineIsLegal() throws {
        for line in OpeningBook.lines {
            var position = ChessPosition.initial
            for san in line.split(separator: " ") {
                let move = try XCTUnwrap(ChessNotation.move(fromSAN: String(san), in: position), "\(san) in \(line)")
                position = try position.applying(move)
            }
        }
    }

    // MARK: Sacrifice detection

    private func given(_ fen: String, _ uci: String) throws -> Int {
        let before = try ChessPosition(fen: fen)
        let move = try XCTUnwrap(ChessMove(uci: uci))
        return SacrificeDetector.materialGivenUp(by: move, before: before, after: try before.applying(move))
    }

    func testSacrificeDetectorMeasuresPiecesLeftEnPrise() throws {
        let fen = "4k3/8/8/3p4/8/1Q6/8/4K3 w - - 0 1"
        XCTAssertEqual(try given(fen, "b3c4"), 9)   // queen steps next to the pawn's capture square
        XCTAssertEqual(try given(fen, "b3b4"), 0)   // quiet, safe
        XCTAssertEqual(try given(fen, "b3d5"), 0)   // wins the pawn safely
        // Defended by the d3 pawn: the pawn capture still wins queen for pawn.
        XCTAssertEqual(try given("4k3/8/8/3p4/8/1Q1P4/8/4K3 w - - 0 1", "b3c4"), 8)
        // Knight takes a defended pawn: gives up the knight for a pawn.
        XCTAssertEqual(try given("4k3/2p5/3p4/8/4N3/8/8/4K3 w - - 0 1", "e4d6"), 2)
    }

    // MARK: Text

    func testEvaluationLabelsAndCoachText() {
        XCTAssertEqual(EvaluationLabel.text(Evaluation(centipawns: 125)), "+1.25")
        XCTAssertEqual(EvaluationLabel.text(Evaluation(centipawns: -40)), "-0.40")
        XCTAssertEqual(EvaluationLabel.text(Evaluation(centipawns: 19_995, mateIn: 3)), "M3")
        XCTAssertEqual(EvaluationLabel.text(Evaluation(centipawns: -19_996, mateIn: -2)), "-M2")
        XCTAssertEqual(EvaluationLabel.text(Evaluation(centipawns: -20_000, mateIn: 0)), "0-1")
        XCTAssertEqual(MoveClassification.blunder.coachText(san: "e5", bestSAN: "d4"), "e5 is a blunder. The best move was d4.")
        XCTAssertEqual(MoveClassification.best.coachText(san: "Nf3", bestSAN: "Nf3"), "Nf3 is best.")
    }
}
