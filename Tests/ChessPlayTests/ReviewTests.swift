import ChessContent
import ChessCore
import Foundation
import Testing

@testable import ChessPlay

@Suite
struct ReviewTests {
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

  private func classify(_ context: MoveContext) throws -> MoveClassification {
    MoveClassifier.classify(context, thresholds: try Shared.catalog.tuning.review)
  }

  // MARK: Win probability

  @Test
  func winProbabilityIsEvenAtZeroAndCertainForMates() {
    #expect(abs(WinProbability.white(Evaluation(centipawns: 0)) - 0.5) < 1e-9)
    #expect(WinProbability.white(Evaluation(centipawns: 19_995, mateIn: 3)) == 1)
    #expect(WinProbability.white(Evaluation(centipawns: -19_996, mateIn: -2)) == 0)
    #expect(WinProbability.white(Evaluation(centipawns: -20_000, mateIn: 0)) == 0)
    // 1 / (1 + e^-0.368208) for one pawn.
    #expect(abs(WinProbability.white(Evaluation(centipawns: 100)) - 0.59103) < 1e-4)
    #expect(abs(WinProbability.forSide(.black, Evaluation(centipawns: 100)) - 0.40897) < 1e-4)
  }

  // MARK: Classification

  @Test
  func lossGradesUseThresholds() throws {
    #expect(try classify(context(best: 50, played: 40)) == .excellent)  // loss ~0.009
    #expect(try classify(context(best: 0, played: -35)) == .good)  // loss ~0.032
    #expect(try classify(context(best: 0, played: -80)) == .inaccuracy)  // loss ~0.073
    #expect(try classify(context(best: 0, played: -200)) == .mistake)  // loss ~0.176
    #expect(try classify(context(best: 0, played: -300)) == .blunder)  // loss ~0.251
  }

  @Test
  func lossIsFromTheMoversPointOfView() throws {
    #expect(try classify(context(.black, best: 0, played: 300)) == .blunder)
    #expect(try classify(context(.black, best: 0, played: -300)) == .excellent)
    #expect(context(best: 0, played: 200).loss == 0)
  }

  @Test
  func bookMovesLoseNothing() {
    // Short searches rate theory moves a few centipawns apart; that noise must not cost accuracy.
    #expect(context(best: 40, played: -20, isBook: true).loss == 0)
  }

  @Test
  func playingTheEngineMoveIsBestOrGreatWhenItIsTheOnlyGoodMove() throws {
    #expect(try classify(context(best: 30, played: -10, playedBest: true)) == .best)
    #expect(try classify(context(best: 0, played: 0, second: -100, playedBest: true)) == .best)
    #expect(try classify(context(best: 0, played: 0, second: -300, playedBest: true)) == .great)
  }

  @Test
  func brilliantNeedsSacrificeAndAGoodPosition() throws {
    #expect(
      try classify(context(best: 150, played: 150, playedBest: true, sacrifice: 3)) == .brilliant
    )
    #expect(try classify(context(best: 150, played: 150, playedBest: true, sacrifice: 1)) == .best)
    #expect(
      try classify(context(best: -300, played: -300, playedBest: true, sacrifice: 3)) == .best
    )
    #expect(try classify(context(best: 150, played: -50, sacrifice: 5)) == .mistake)
  }

  @Test
  func bookWinsOverEverything() throws {
    #expect(try classify(context(best: 0, played: -300, isBook: true)) == .book)
  }

  @Test
  func missWhenNotPunishingAnOpponentError() throws {
    #expect(try classify(context(best: 500, played: 150, previous: .blunder)) == .miss)
    #expect(try classify(context(best: 500, played: 150, previous: .good)) == .blunder)
    // Dropping to a worse position than equal is a plain error, not a miss.
    #expect(try classify(context(best: 500, played: -100, previous: .mistake)) == .blunder)
    // Nothing big to win: an ordinary grade.
    #expect(try classify(context(best: 50, played: -150, previous: .mistake)) == .mistake)
  }

  // MARK: Accuracy

  @Test
  func accuracyFormula() throws {
    #expect(AccuracyCalculator.accuracy(losses: []) == nil)
    #expect(abs(try #require(AccuracyCalculator.accuracy(losses: [0, 0])) - 100) < 0.001)
    // 103.1668 * e^(-0.4354) - 3.1669 for a 10% average loss.
    #expect(abs(try #require(AccuracyCalculator.accuracy(losses: [0.05, 0.15])) - 63.585) < 0.01)
    #expect(AccuracyCalculator.accuracy(losses: [1, 1]) == 0)
  }

  // MARK: Opening book

  @Test
  func bookPlyCountFollowsTheLongestMatchingLine() throws {
    let book = try Shared.catalog.openingBook
    #expect(book.bookPlyCount(for: ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "h3"]) == 6)
    #expect(book.bookPlyCount(for: ["e4", "e5", "Qh5"]) == 2)
    #expect(book.bookPlyCount(for: ["h4"]) == 0)
    #expect(
      book.bookPlyCount(for: ["e4", "e5", "Nf3", "Nc6", "Bc4", "Nf6", "Ng5", "d5", "exd5", "Na5"])
        == 10
    )
  }

  @Test
  func everyBookLineIsLegal() throws {
    for line in try Shared.catalog.openingBook.lines {
      var position = ChessPosition.initial
      for san in line.split(separator: " ") {
        let move = try #require(
          ChessNotation.move(fromSAN: String(san), in: position),
          "\(san) in \(line)"
        )
        position = try position.applying(move)
      }
    }
  }

  // MARK: Sacrifice detection

  private func given(_ fen: String, _ uci: String) throws -> Int {
    let before = try ChessPosition(fen: fen)
    let move = try #require(ChessMove(uci: uci))
    return SacrificeDetector.materialGivenUp(
      by: move,
      before: before,
      after: try before.applying(move)
    )
  }

  @Test
  func sacrificeDetectorMeasuresPiecesLeftEnPrise() throws {
    let fen = "4k3/8/8/3p4/8/1Q6/8/4K3 w - - 0 1"
    #expect(try given(fen, "b3c4") == 9)  // queen steps next to the pawn's capture square
    #expect(try given(fen, "b3b4") == 0)  // quiet, safe
    #expect(try given(fen, "b3d5") == 0)  // wins the pawn safely
    // Defended by the d3 pawn: the pawn capture still wins queen for pawn.
    #expect(try given("4k3/8/8/3p4/8/1Q1P4/8/4K3 w - - 0 1", "b3c4") == 8)
    // Knight takes a defended pawn: gives up the knight for a pawn.
    #expect(try given("4k3/2p5/3p4/8/4N3/8/8/4K3 w - - 0 1", "e4d6") == 2)
  }

  // MARK: Text

  @Test
  func evaluationLabelsAndCoachText() {
    #expect(EvaluationLabel.text(Evaluation(centipawns: 125)) == "+1.25")
    #expect(EvaluationLabel.text(Evaluation(centipawns: -40)) == "-0.40")
    #expect(EvaluationLabel.text(Evaluation(centipawns: 19_995, mateIn: 3)) == "M3")
    #expect(EvaluationLabel.text(Evaluation(centipawns: -19_996, mateIn: -2)) == "-M2")
    #expect(EvaluationLabel.text(Evaluation(centipawns: -20_000, mateIn: 0)) == "0-1")
    #expect(
      MoveClassification.blunder.coachText(san: "e5", bestSAN: "d4", localization: Shared.english)
        == "e5 is a blunder. The best move was d4."
    )
    #expect(
      MoveClassification.best.coachText(san: "Nf3", bestSAN: "Nf3", localization: Shared.english)
        == "Nf3 is best."
    )
  }
}
