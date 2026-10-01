import Testing

@testable import ChessCore

private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
private let kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
// Positions 3 and 4 of the standard perft suite (en passant and promotion edge cases).
private let position3 = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
private let position4 = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"

struct PerftCase: Sendable, CustomTestStringConvertible {
  let name: String
  let fen: String
  let depth: Int
  let nodes: Int
  var testDescription: String { "\(name) depth \(depth)" }
}

struct UnsupportedCase: Sendable, CustomTestStringConvertible {
  let name: String
  let position: ChessPosition
  var testDescription: String { name }

  private static let kings: [Square: Piece] = [
    Square(file: 4, rank: 0): Piece(type: .king, color: .white),
    Square(file: 4, rank: 7): Piece(type: .king, color: .black),
  ]

  static let all = [
    Self(
      name: "no black king",
      position: ChessPosition(board: [Square(file: 4, rank: 0): Piece(type: .king, color: .white)])
    ),
    Self(
      name: "white king off the board",
      position: ChessPosition(board: [
        Square(file: 8, rank: 0): Piece(type: .king, color: .white),
        Square(file: 0, rank: 0): Piece(type: .rook, color: .white),
        Square(file: 4, rank: 7): Piece(type: .king, color: .black),
      ])
    ),
    Self(
      name: "side not to move in check",
      position: ChessPosition(board: [
        Square(file: 4, rank: 0): Piece(type: .king, color: .white),
        Square(file: 4, rank: 1): Piece(type: .rook, color: .white),
        Square(file: 4, rank: 7): Piece(type: .king, color: .black),
      ])
    ),
    Self(
      name: "halfmove clock Int.max",
      position: ChessPosition(board: kings, halfmoveClock: .max)
    ),
    Self(
      name: "halfmove clock Int.min",
      position: ChessPosition(board: kings, halfmoveClock: .min)
    ),
    Self(name: "fullmove number 0", position: ChessPosition(board: kings, fullmoveNumber: 0)),
    Self(
      name: "fullmove number Int.max",
      position: ChessPosition(board: kings, fullmoveNumber: .max)
    ),
  ]
}

@Suite
struct EngineAdapterTests {
  @Test(arguments: UnsupportedCase.all)
  func analyzeReportsNoMoveForUnsupportedPosition(_ test: UnsupportedCase) async throws {
    let analysis = try await ChessEngine().analyze(position: test.position, limit: .depth(2))
    #expect(analysis.bestMove == nil)
    #expect(analysis.principalVariation.isEmpty)
  }

  @Test(arguments: UnsupportedCase.all)
  func bestMoveThrowsForUnsupportedPosition(_ test: UnsupportedCase) async {
    await #expect(throws: ChessEngineError.noLegalMove) {
      try await ChessEngine().bestMove(
        game: ChessGame(position: test.position),
        strength: EngineStrength(elo: 250)
      )
    }
  }

  @Test(arguments: [
    PerftCase(name: "start", fen: startFEN, depth: 1, nodes: 20),
    PerftCase(name: "start", fen: startFEN, depth: 2, nodes: 400),
    PerftCase(name: "start", fen: startFEN, depth: 3, nodes: 8_902),
    PerftCase(name: "start", fen: startFEN, depth: 4, nodes: 197_281),
    PerftCase(name: "kiwipete", fen: kiwipete, depth: 1, nodes: 48),
    PerftCase(name: "kiwipete", fen: kiwipete, depth: 2, nodes: 2_039),
    PerftCase(name: "kiwipete", fen: kiwipete, depth: 3, nodes: 97_862),
    PerftCase(name: "position 3", fen: position3, depth: 1, nodes: 14),
    PerftCase(name: "position 3", fen: position3, depth: 2, nodes: 191),
    PerftCase(name: "position 3", fen: position3, depth: 3, nodes: 2_812),
    PerftCase(name: "position 3", fen: position3, depth: 4, nodes: 43_238),
    PerftCase(name: "position 4", fen: position4, depth: 3, nodes: 9_467),
  ])
  func perft(_ test: PerftCase) throws {
    var board = EngineBoard(try ChessPosition(fen: test.fen))
    defer { board.deallocate() }
    #expect(board.perft(test.depth) == test.nodes)
  }

  @Test(arguments: [kiwipete, position3, "4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 2"])
  func internalLegalMovesMatchChessPosition(fen: String) throws {
    let position = try ChessPosition(fen: fen)
    var board = EngineBoard(position)
    defer { board.deallocate() }
    #expect(Set(board.legalMoves().map(\.chessMove)) == Set(position.legalMoves()))
  }

  @Test
  func incrementalHashMatchesRecomputedHash() throws {
    var board = EngineBoard(try ChessPosition(fen: kiwipete))
    defer { board.deallocate() }
    var generator = SplitMix(seed: 7)
    for _ in 0..<200 {
      let moves = board.legalMoves()
      guard !moves.isEmpty else { break }
      board.make(moves[Int(generator.next() % UInt64(moves.count))])
      #expect(board.hash == board.computeHash())
    }
  }

  @Test
  func findsMateInOne() async throws {
    let position = try ChessPosition(fen: "6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1")
    let analysis = try await ChessEngine().analyze(position: position, limit: .depth(3))
    #expect(analysis.bestMove == ChessMove(uci: "d1d8"))
    #expect(analysis.evaluation.mateIn == 1)
  }

  @Test
  func findsMateInTwo() async throws {
    // 1. Rd8+ Rxd8 (forced) 2. Rxd8#.
    let position = try ChessPosition(fen: "2r3k1/5ppp/8/8/8/8/3R1PPP/3R2K1 w - - 0 1")
    let analysis = try await ChessEngine().analyze(position: position, limit: .depth(5))
    #expect(analysis.evaluation.mateIn == 2)
    #expect(analysis.bestMove == ChessMove(uci: "d2d8"))
    #expect(analysis.principalVariation.first == analysis.bestMove)
  }

  @Test
  func takesHangingQueen() async throws {
    let game = ChessGame(
      position: try ChessPosition(
        fen: "rnb1kbnr/pppp1ppp/8/4p1q1/4P3/3P4/PPP2PPP/RNBQKBNR w KQkq - 0 1"
      )
    )
    let analysis = try await ChessEngine().analyze(position: game.position, limit: .depth(4))
    #expect(analysis.bestMove == ChessMove(uci: "c1g5"))
  }

  @Test
  func chooseWithFixedSeedIsStableAndLegal() throws {
    // Refactor pin: the expected move was recorded from the current code, not derived
    // independently. It detects any change in how `choose` consumes the generator.
    var board = EngineBoard(.initial)
    defer { board.deallocate() }
    let scored = [("e2e4", 30), ("d2d4", 20), ("g1f3", 10), ("a2a3", -40)]
    var lines: [RootLine] = []
    for (uci, score) in scored {
      let found = board.engineMove(for: try move(uci))
      let engineMove = try #require(found)
      lines.append(RootLine(move: engineMove, score: score, exact: true, pv: [engineMove]))
    }
    // Several seeds, so both the noisy-best and the weighted-draw paths are exercised.
    let chosen = (1...12).map { seed in
      var generator = SplitMix(seed: UInt64(seed))
      let pick = ChessEngine.choose(
        from: lines,
        strength: EngineStrength(elo: 250),
        using: &generator
      )
      return pick.chessMove.uci
    }
    #expect(
      chosen == [
        "e2e4", "e2e4", "g1f3", "e2e4", "g1f3", "e2e4", "a2a3", "e2e4", "g1f3", "a2a3", "g1f3",
        "e2e4",
      ]
    )
    #expect(Set(chosen).isSubset(of: Set(scored.map(\.0))))
  }

  @Test
  func lowStrengthReturnsLegalMoves() async throws {
    let engine = ChessEngine()
    var game = ChessGame()
    for _ in 0..<12 {
      guard !game.position.legalMoves().isEmpty else { break }
      let move = try await engine.bestMove(game: game, strength: EngineStrength(elo: 250))
      #expect(game.position.legalMoves().contains(move))
      try game.makeMove(move)
    }
  }

  @Test
  func analysisScoresFromWhitePointOfView() async throws {
    let engine = ChessEngine()
    // White is a queen up; the score is positive whoever is to move.
    let whiteToMove = try ChessPosition(fen: "4k3/8/8/8/8/8/8/3QK3 w - - 0 1")
    let blackToMove = try ChessPosition(fen: "4k3/8/8/8/8/8/8/3QK3 b - - 0 1")
    let first = try await engine.analyze(position: whiteToMove, limit: .depth(2))
    let second = try await engine.analyze(position: blackToMove, limit: .depth(2))
    #expect(first.evaluation.centipawns > 500)
    #expect(second.evaluation.centipawns > 500)
    #expect(first.secondBestEvaluation != nil)

    // Black mates in one: the mate count is negative.
    let blackMates = try ChessPosition(fen: "3r2k1/8/8/8/8/8/5PPP/6K1 b - - 0 1")
    let mate = try await engine.analyze(position: blackMates, limit: .depth(3))
    #expect(mate.evaluation.mateIn == -1)
    #expect(mate.evaluation.centipawns < 0)

    // Already checkmated: no move, mate 0, sign shows the winner.
    let mated = try ChessPosition(fen: "3R2k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1")
    let over = try await engine.analyze(position: mated, limit: .depth(3))
    #expect(over.bestMove == nil)
    #expect(over.evaluation.mateIn == 0)
    #expect(over.evaluation.centipawns > 0)
  }

  @Test
  func repetitionInHistoryScoresAsDraw() async throws {
    // White has a bare king against king and queen. After Kb1 Qc6 Ka1 Qc5 the start
    // position is back on the board, so Kb1 now repeats a position from the history.
    var game = ChessGame(position: try ChessPosition(fen: "7k/8/8/2q5/8/8/8/K7 w - - 0 1"))
    for uci in ["a1b1", "c5c6", "b1a1", "c6c5"] { try game.makeMove(move(uci)) }
    let withHistory = try await ChessEngine().analyze(
      position: game.position,
      history: game.moves.map(\.positionBefore),
      limit: .depth(4)
    )
    #expect(withHistory.evaluation.centipawns == 0)
    #expect(withHistory.bestMove == ChessMove(uci: "a1b1"))

    let withoutHistory = try await ChessEngine().analyze(
      position: game.position,
      limit: .depth(4)
    )
    #expect(withoutHistory.evaluation.centipawns < -500)
  }

  @Test
  func cancellationStopsSearch() async {
    let engine = ChessEngine()
    let task = Task { try await engine.analyze(position: .initial, limit: .time(.seconds(30))) }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test
  func strengthSettingsScaleWithElo() {
    let weak = EngineStrength(elo: 100)
    let strong = EngineStrength(elo: 3000)
    #expect(weak.elo == 250)
    #expect(strong.elo == 2200)
    #expect(weak.searchDepth == 1)
    #expect(weak.searchDepth < EngineStrength(elo: 1500).searchDepth)
    #expect(weak.evaluationNoise > EngineStrength(elo: 1500).evaluationNoise)
    #expect(strong.evaluationNoise == 0)
    #expect(strong.mistakeChance == 0)
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
