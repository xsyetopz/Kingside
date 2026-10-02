import ChessContent
import ChessCore
import Testing

@testable import ChessPlay

@Suite
struct GameClockTests {
  private let blitz = TimeControl(initialSeconds: 180, incrementSeconds: 2)

  @Test
  func runsOnlyAfterBothSidesMoved() {
    let clock = GameClock(timeControl: blitz)
    #expect(!clock.runs(atPly: 0))
    #expect(!clock.runs(atPly: 1))
    #expect(clock.runs(atPly: 2))
    #expect(!GameClock(timeControl: .untimed).runs(atPly: 10))
  }

  @Test
  func incrementAddedOnlyWhileRunning() {
    var clock = GameClock(timeControl: blitz)
    clock.recordMove(by: .white, plyBeforeMove: 0)
    #expect(clock.remaining(.white) == 180)
    clock.recordMove(by: .white, plyBeforeMove: 2)
    #expect(clock.remaining(.white) == 182)
    #expect(clock.remaining(.black) == 180)
  }

  @Test
  func consumeFlagsAtZeroAndNeverGoesNegative() throws {
    let tuning = try Shared.catalog.tuning.clock
    var clock = GameClock(timeControl: TimeControl(initialSeconds: 60, incrementSeconds: 0))
    let flaggedEarly = clock.consume(50, by: .black)
    #expect(!flaggedEarly)
    #expect(clock.isLow(.black, tuning: tuning))
    #expect(!clock.isLow(.white, tuning: tuning))
    let flagged = clock.consume(20, by: .black)
    #expect(flagged)
    #expect(clock.remaining(.black) == 0)
    #expect(clock.hasFlagged(.black))
  }

  @Test
  func untimedClockNeverFlags() throws {
    var clock = GameClock(timeControl: .untimed)
    let flagged = clock.consume(1000, by: .white)
    #expect(!flagged)
    #expect(!clock.isLow(.white, tuning: try Shared.catalog.tuning.clock))
  }
}

@Suite
struct GameAdjudicationTests {
  @Test
  func outcomeMapping() {
    #expect(GameAdjudication.result(for: .ongoing) == nil)
    #expect(GameAdjudication.result(for: .checkmate(winner: .black))?.0 == .blackWon)
    #expect(GameAdjudication.result(for: .checkmate(winner: .black))?.1 == .checkmate)
    #expect(GameAdjudication.result(for: .stalemate)?.1 == .stalemate)
    #expect(GameAdjudication.result(for: .drawThreefoldRepetition)?.1 == .repetition)
    #expect(GameAdjudication.result(for: .drawFiftyMove)?.1 == .fiftyMoveRule)
    #expect(GameAdjudication.result(for: .drawInsufficientMaterial)?.0 == .draw)
  }

  @Test
  func timeoutWinsWithMatingMaterial() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/8/8/4P3/4K3 w - - 0 1")
    let (result, termination) = GameAdjudication.timeout(flagged: .black, in: position)
    #expect(result == .whiteWon)
    #expect(termination == .timeout)
  }

  @Test
  func timeoutAgainstLoneMinorPieceIsDraw() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/8/8/4P3/2B1K3 w - - 0 1")
    let (result, termination) = GameAdjudication.timeout(flagged: .white, in: position)
    #expect(result == .draw)
    #expect(termination == .timeoutVsInsufficientMaterial)
  }

  @Test
  func matingMaterial() throws {
    let position = try ChessPosition(fen: "4k3/8/8/8/8/8/8/1NB1K2n b - - 0 1")
    #expect(GameAdjudication.hasMatingMaterial(.white, in: position))
    #expect(!GameAdjudication.hasMatingMaterial(.black, in: position))
  }

  @Test
  func materialAndMissingPieces() throws {
    let position = try ChessPosition(fen: "4k3/pppppppp/8/8/8/8/PPPPPPP1/RNBQKBNR w KQ - 0 1")
    #expect(Material.points(.white, in: position) == 38)
    #expect(Material.points(.black, in: position) == 8)
    #expect(Material.missing(.white, in: position) == [.pawn])
    #expect(GamePresentation.materialAdvantage(in: position) == [.white: 30, .black: 0])
  }
}

@Suite
struct DrawOfferPolicyTests {
  private let start = ChessPosition.initial

  private var policy: DrawOfferTuning {
    get throws { try Shared.catalog.tuning.drawOffer }
  }

  @Test
  func acceptsLateWhenNotClearlyBetter() throws {
    let evaluation = Evaluation(centipawns: -20)
    #expect(
      try policy.botAccepts(evaluation: evaluation, botColor: .white, plyCount: 30, position: start)
    )
    #expect(
      try !policy.botAccepts(
        evaluation: evaluation,
        botColor: .white,
        plyCount: 29,
        position: start
      )
    )
  }

  @Test
  func rejectsWhenAhead() throws {
    // +200 for White is +200 for a White bot and -200 for a Black bot.
    let evaluation = Evaluation(centipawns: 200)
    #expect(
      try !policy.botAccepts(
        evaluation: evaluation,
        botColor: .white,
        plyCount: 60,
        position: start
      )
    )
    #expect(
      try policy.botAccepts(evaluation: evaluation, botColor: .black, plyCount: 60, position: start)
    )
  }

  @Test
  func acceptsEarlyInLowMaterialEqualPosition() throws {
    let position = try ChessPosition(fen: "4k3/4r3/8/8/8/8/4R3/4K3 w - - 0 1")
    #expect(
      try policy.botAccepts(
        evaluation: Evaluation(centipawns: 40),
        botColor: .black,
        plyCount: 4,
        position: position
      )
    )
    #expect(
      try !policy.botAccepts(
        evaluation: Evaluation(centipawns: 80),
        botColor: .black,
        plyCount: 4,
        position: position
      )
    )
  }

  @Test
  func mateScores() throws {
    #expect(DrawOfferTuning.score(Evaluation(centipawns: 0, mateIn: 3), for: .white) == 100_000)
    #expect(DrawOfferTuning.score(Evaluation(centipawns: 0, mateIn: 3), for: .black) == -100_000)
    #expect(
      try !policy.botAccepts(
        evaluation: Evaluation(centipawns: 0, mateIn: -2),
        botColor: .black,
        plyCount: 80,
        position: start
      )
    )
  }
}

@Suite
struct GameSessionRulesTests {
  private var tuning: GameTuning {
    get throws { try Shared.catalog.tuning.game }
  }

  @Test
  func botThinkDelay() throws {
    let tuning = try tuning
    #expect(abs(GameSession.botThinkDelay(legalMoveCount: 0, tuning: tuning) - 0.4) < 1e-9)
    #expect(abs(GameSession.botThinkDelay(legalMoveCount: 20, tuning: tuning) - 0.8) < 1e-9)
    #expect(abs(GameSession.botThinkDelay(legalMoveCount: 80, tuning: tuning) - 1.2) < 1e-9)
  }

  @Test
  func blunderDetection() throws {
    let tuning = try tuning
    let before = Evaluation(centipawns: 50)
    #expect(
      GameSession.isBlunder(
        before: before,
        after: Evaluation(centipawns: -200),
        by: .white,
        tuning: tuning
      )
    )
    #expect(
      !GameSession.isBlunder(
        before: before,
        after: Evaluation(centipawns: -199),
        by: .white,
        tuning: tuning
      )
    )
    #expect(
      GameSession.isBlunder(
        before: Evaluation(centipawns: -50),
        after: Evaluation(centipawns: 200),
        by: .black,
        tuning: tuning
      )
    )
    #expect(
      GameSession.isBlunder(
        before: before,
        after: Evaluation(centipawns: 0, mateIn: -3),
        by: .white,
        tuning: tuning
      )
    )
  }

  @Test
  func takebackPlies() {
    #expect(GameSession.takebackPlies(plyCount: 2, sideToMove: .white, humanColor: .white) == 2)
    #expect(GameSession.takebackPlies(plyCount: 1, sideToMove: .black, humanColor: .white) == 1)
    #expect(GameSession.takebackPlies(plyCount: 1, sideToMove: .black, humanColor: .black) == 0)
    #expect(GameSession.takebackPlies(plyCount: 0, sideToMove: .white, humanColor: .white) == 0)
    #expect(GameSession.takebackPlies(plyCount: 3, sideToMove: .black, humanColor: nil) == 1)
    #expect(GameSession.takebackPlies(plyCount: 0, sideToMove: .white, humanColor: nil) == 0)
  }

  @Test
  func resultTitles() {
    let english = Shared.english
    #expect(
      GamePresentation.resultTitle(.whiteWon, humanColor: .white, localization: english)
        == "You Won!"
    )
    #expect(
      GamePresentation.resultTitle(.whiteWon, humanColor: .black, localization: english)
        == "You Lost"
    )
    #expect(
      GamePresentation.resultTitle(.blackWon, humanColor: nil, localization: english) == "Black Won"
    )
    #expect(
      GamePresentation.resultTitle(.whiteWon, humanColor: nil, localization: english) == "White Won"
    )
    #expect(
      GamePresentation.resultTitle(.draw, humanColor: .white, localization: english) == "Draw"
    )
  }

  @Test
  func moveRows() throws {
    var game = ChessGame()
    for uci in ["e2e4", "e7e5", "g1f3"] { try game.makeMove(#require(ChessMove(uci: uci))) }
    #expect(
      GamePresentation.moveRows(game.moves) == [
        MoveRow(number: 1, white: "e4", black: "e5"),
        MoveRow(number: 2, white: "Nf3", black: nil),
      ]
    )
  }

  @Test
  func chatEvents() {
    #expect(GameSession.chatEvent(moveByBot: true, isCapture: true, givesCheck: true) == .check)
    #expect(
      GameSession.chatEvent(moveByBot: true, isCapture: true, givesCheck: false) == .botCaptures
    )
    #expect(
      GameSession.chatEvent(moveByBot: false, isCapture: true, givesCheck: true) == .playerCaptures
    )
    #expect(GameSession.chatEvent(moveByBot: false, isCapture: false, givesCheck: false) == nil)
  }
}
