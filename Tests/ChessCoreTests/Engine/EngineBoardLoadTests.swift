import Testing

@testable import ChessCore

/// Builds a position without FEN validation, so it can hold states that FEN parsing rejects.
/// `pieces` lists tokens such as `"Ke1 pd7"`: the letter's case gives the color (upper white).
private func position(
  _ pieces: String,
  sideToMove: PieceColor = .white,
  enPassantTarget: String? = nil,
  halfmoveClock: Int = 0
) throws -> ChessPosition {
  let kinds: [Character: PieceType] = [
    "p": .pawn, "n": .knight, "b": .bishop, "r": .rook, "q": .queen, "k": .king,
  ]
  var board: [Square: Piece] = [:]
  for token in pieces.split(separator: " ") {
    let letter = try #require(token.first)
    let kind = try #require(kinds[Character(letter.lowercased())])
    let square = try #require(Square(algebraic: String(token.dropFirst())))
    board[square] = Piece(type: kind, color: letter.isUppercase ? .white : .black)
  }
  return ChessPosition(
    board: board,
    sideToMove: sideToMove,
    enPassantTarget: try enPassantTarget.map { try #require(Square(algebraic: $0)) },
    halfmoveClock: halfmoveClock
  )
}

private func legalMoveCount(_ position: ChessPosition) -> Int {
  var board = EngineBoard(position, plyCapacity: 1)
  return board.legalMoves().count
}

/// `load` keeps an en-passant target only when a pawn just skipped it. Move counts are counted by
/// hand: each position allows its pawn moves plus five king moves from e1 (three from a1).
@Suite
struct EngineBoardEnPassantLoadTests {
  @Test
  func targetWithoutAPawnInFrontIsIgnored() throws {
    // Only d5-d6 and the king moves: no black pawn stands on e5.
    #expect(legalMoveCount(try position("Ke1 ke8 Pd5", enPassantTarget: "e6")) == 6)
  }

  @Test
  func targetWhoseOriginSquareIsOccupiedIsIgnored() throws {
    // The pawn on e5 cannot have come from e7, which is still occupied.
    #expect(legalMoveCount(try position("Ke1 ke8 Pd5 pe5 pe7", enPassantTarget: "e6")) == 6)
  }

  @Test
  func occupiedTargetIsIgnored() throws {
    // d5xe6 would land on the white knight; the knight itself has eight moves.
    #expect(legalMoveCount(try position("Ke1 ke8 Pd5 pe5 Ne6", enPassantTarget: "e6")) == 14)
  }

  @Test
  func targetOnTheWrongRankIsIgnored() throws {
    // White to move can only capture en passant on rank 6; d2 keeps d3 and d4.
    #expect(legalMoveCount(try position("Ka1 kh8 Pd2 pe2", enPassantTarget: "e3")) == 5)
  }

  @Test
  func realSkippedSquareAllowsTheCapture() throws {
    // d5-d6, d5xe6 en passant and the king moves.
    #expect(legalMoveCount(try position("Ke1 ke8 Pd5 pe5", enPassantTarget: "e6")) == 7)
  }

  @Test
  func realSkippedSquareForBlackAllowsTheCapture() throws {
    // d4-d3, d4xe3 en passant and five king moves from e8.
    let skipped = try position("Ke1 ke8 pd4 Pe4", sideToMove: .black, enPassantTarget: "e3")
    #expect(legalMoveCount(skipped) == 7)
  }

  @Test
  func targetOnTheWrongRankForBlackIsIgnored() throws {
    // Black to move can only capture en passant on rank 3: d7-d6, d7-d5 and three king moves.
    let wrongRank = try position("Ke1 kh8 pd7 Pe7", sideToMove: .black, enPassantTarget: "e6")
    #expect(legalMoveCount(wrongRank) == 5)
  }

  @Test
  func targetWhoseOriginSquareIsOccupiedForBlackIsIgnored() throws {
    // The pawn on e4 cannot have come from e2, which is still occupied: d4-d3 and the king moves.
    let occupied = try position(
      "Ke1 ke8 pd4 Pe4 Pe2",
      sideToMove: .black,
      enPassantTarget: "e3"
    )
    #expect(legalMoveCount(occupied) == 6)
  }

  @Test(arguments: [
    ("Ke1 ke8 Pb5 pa5", PieceColor.white, "a6"),
    ("Ke1 ke8 Pg5 ph5", PieceColor.white, "h6"),
    ("Ke1 ke8 pb4 Pa4", PieceColor.black, "a3"),
    ("Ke1 ke8 pg4 Ph4", PieceColor.black, "h3"),
  ])
  func targetOnAnEdgeFileAllowsTheCapture(
    _ pieces: String,
    _ sideToMove: PieceColor,
    _ target: String
  ) throws {
    // One push, the en passant capture from the neighbouring file and five king moves.
    let skipped = try position(pieces, sideToMove: sideToMove, enPassantTarget: target)
    #expect(legalMoveCount(skipped) == 7)
  }
}

/// `load` refuses positions the move generator cannot handle: they have no legal moves and no
/// perft nodes.
@Suite
struct EngineBoardSupportTests {
  @Test
  func missingKingHasNoLegalMoves() throws {
    #expect(legalMoveCount(try position("Ra1 ke8")) == 0)
  }

  @Test
  func secondKingHasNoLegalMoves() throws {
    #expect(legalMoveCount(try position("Ke1 Ka1 ke8")) == 0)
  }

  @Test
  func pawnOnTheFirstRankHasNoLegalMoves() throws {
    #expect(legalMoveCount(try position("Ke1 ke8 Ph1")) == 0)
  }

  @Test
  func pawnOnTheLastRankHasNoLegalMoves() throws {
    #expect(legalMoveCount(try position("Ke1 ke8 pa8")) == 0)
  }

  @Test
  func morePromotedPiecesThanMissingPawnsHasNoLegalMoves() throws {
    // Eight pawns leave no room for a third knight.
    let pieces = "Ke1 ke8 Pa2 Pb2 Pc2 Pd2 Pe2 Pf2 Pg2 Ph2 Nb1 Ng1 Nc3"
    #expect(legalMoveCount(try position(pieces)) == 0)
  }

  @Test
  func promotedPieceInPlaceOfAMissingPawnIsSupported() throws {
    // Seven pawns and a third knight: 8 king, 14 pawn and 1 + 1 + 3 knight moves.
    let pieces = "Ke5 ke8 Pa2 Pb2 Pc2 Pd2 Pe2 Pf2 Pg2 Na1 Nh1 Nh3"
    #expect(legalMoveCount(try position(pieces)) == 27)
  }

  @Test
  func sideNotToMoveInCheckHasNoLegalMoves() throws {
    #expect(legalMoveCount(try position("Ka1 Re2 ke8")) == 0)
  }

  @Test
  func nearlyExhaustedHalfmoveClockCountsLikeAClockOf100() throws {
    // Two quiet made moves would take the raw clock past Int.max; the engine treats every clock
    // from 100 on alike.
    var nearLimit = EngineBoard(
      try position("Ke1 ke8 Ra1", halfmoveClock: Int.max - 1),
      plyCapacity: 2
    )
    var at100 = EngineBoard(try position("Ke1 ke8 Ra1", halfmoveClock: 100), plyCapacity: 2)
    #expect(nearLimit.perft(2) == at100.perft(2))
  }

  @Test
  func halfmoveClockWithRoomForEveryMadeMoveIsSupported() throws {
    // Five king moves, seven rook moves up the a-file and three along the first rank.
    #expect(legalMoveCount(try position("Ke1 ke8 Ra1", halfmoveClock: Int.max - 1)) == 15)
  }

  @Test
  func nineQueensFromPromotionsAreSupported() throws {
    // Eight queens promoted from the eight missing pawns, next to all other starting pieces.
    let nineQueens = try ChessPosition(fen: "3Q4/1Q4Q1/4Q3/2Q4R/Q4Q2/3Q4/1Q4Rp/1K1BBNNk w - - 0 1")
    let isSupported = EngineBoard(nineQueens, plyCapacity: 1).isSupported
    #expect(isSupported)
  }

  @Test
  func unsupportedPositionHasNoPerftNodes() throws {
    var board = EngineBoard(try position("Ra1 ke8"), plyCapacity: 2)
    #expect(board.perft(2) == 0)
  }
}

private func uciMove(_ uci: String) throws -> ChessMove { try #require(ChessMove(uci: uci)) }

/// Both sides may still castle either way, and d7-d5 has just made e5xd6 en passant legal.
private let castlingAndEnPassant = "r3k2r/8/8/3pP3/8/8/8/R3K2R w KQkq d6 0 1"

/// `copy(plyCapacity:)` and `play(_:)`, which let a small board follow a game.
@Suite
struct EngineBoardPlayTests {
  @Test
  func copyStartsFromTheCurrentNodeWithNoMadeMoves() throws {
    var board = EngineBoard(.initial, plyCapacity: 1)
    let e4 = try #require(board.engineMove(for: try uciMove("e2e4")))
    board.make(e4)
    // The source has used its whole capacity; the copy still holds two made moves. 600 is the
    // published perft divide count for e2e4 at depth 3.
    var copy = board.copy(plyCapacity: 2)
    #expect(copy.perft(2) == 600)
  }

  @Test
  func copyMatchesItsSourceOnEveryQuery() throws {
    var board = EngineBoard(try ChessPosition(fen: castlingAndEnPassant), plyCapacity: 2)
    var copy = board.copy(plyCapacity: 2)
    let moves = copy.legalMoves()
    for uci in ["e1g1", "e1c1", "e5d6"] {
      #expect(moves.contains { $0.chessMove == (try? uciMove(uci)) }, "\(uci)")
    }
    #expect(Set(moves) == Set(board.legalMoves()))
    #expect(copy.computeHash() == copy.hash)
    #expect(copy.hash == board.hash)
    #expect(copy.perft(2) == board.perft(2))
  }

  @Test
  func playOnACopyLeavesTheSourceUnchanged() throws {
    var board = EngineBoard(try ChessPosition(fen: castlingAndEnPassant), plyCapacity: 1)
    let moves = Set(board.legalMoves())
    let hash = board.hash
    var copy = board.copy(plyCapacity: 1)
    #expect(copy.play(try uciMove("e5d6")))
    #expect(copy.hash != hash)
    #expect(Set(board.legalMoves()) == moves)
    #expect(board.hash == hash)
  }

  @Test
  func copyOfAnUnsupportedBoardStaysUnsupported() throws {
    let board = EngineBoard(try position("Ra1 ke8"), plyCapacity: 1)
    var copy = board.copy(plyCapacity: 1)
    #expect(copy.legalMoves().isEmpty)
    #expect(!copy.play(try uciMove("a1a2")))
  }

  @Test
  func playRefusesEveryMoveOnAnUnsupportedBoard() throws {
    // Without a white king the rook move would pass the generator's own legality check.
    var board = EngineBoard(try position("Ra1 ke8"), plyCapacity: 1)
    #expect(!board.play(try uciMove("a1a2")))
  }

  @Test
  func playForgetsTheRepetitionHistory() throws {
    let knightsOutAndBack = try ["g1f3", "g8f6", "f3g1", "f6g8"].map(uciMove)
    var made = EngineBoard(.initial, plyCapacity: 4)
    for move in knightsOutAndBack {
      let engineMove = made.engineMove(for: move)
      made.make(try #require(engineMove))
    }
    let madeRepeats = made.isRepetition
    #expect(madeRepeats)
    var played = EngineBoard(.initial, plyCapacity: 4)
    for move in knightsOutAndBack {
      let isPlayed = played.play(move)
      #expect(isPlayed)
    }
    let playedRepeats = played.isRepetition
    #expect(!playedRepeats)
  }

  @Test
  func playKeepsGoingFromANearlyExhaustedHalfmoveClock() throws {
    var board = EngineBoard(try position("Ke1 ke8 Ra1", halfmoveClock: Int.max - 1), plyCapacity: 1)
    for uci in ["a1a2", "e8e7", "a2a1", "e7e8"] {
      #expect(board.play(try uciMove(uci)), "\(uci)")
    }
  }

  @Test
  func analyzeFindsAMoveForASideInCheckWithANearlyExhaustedClock() async throws {
    // The king escapes the rook check, or captures the rook on e2.
    let fen = "4k3/8/8/8/8/8/4r3/4K3 w - - 9223372036854775806 1"
    let analysis = try await ChessEngine().analyze(
      position: try ChessPosition(fen: fen),
      limit: .depth(2)
    )
    let best = try #require(analysis.bestMove)
    #expect(["e1d1", "e1f1", "e1e2"].compactMap(ChessMove.init(uci:)).contains(best))
    #expect(analysis.evaluation.mateIn == nil)
  }

  @Test
  func playWithAnOutstandingMadeMoveStops() async {
    await #expect(processExitsWith: .failure) {
      var board = EngineBoard(.initial, plyCapacity: 2)
      guard let e2e4 = ChessMove(uci: "e2e4"), let e7e5 = ChessMove(uci: "e7e5"),
        let made = board.engineMove(for: e2e4)
      else { return }
      board.make(made)
      _ = board.play(e7e5)
    }
  }

  @Test
  func playKeepsGoingPastThePlyCapacity() throws {
    var board = EngineBoard(.initial, plyCapacity: 1)
    for uci in ["g1f3", "g8f6", "f3g1", "f6g8", "e2e4"] {
      #expect(board.play(try uciMove(uci)), "\(uci)")
    }
    let afterE4 = try ChessPosition(
      fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 3"
    )
    #expect(board.hash == EngineBoard(afterE4, plyCapacity: 1).hash)
    #expect(board.perft(1) == 20)
  }

  @Test
  func playRejectsAMoveThatIsNotPseudoLegal() throws {
    var board = EngineBoard(.initial, plyCapacity: 1)
    #expect(!board.play(try uciMove("e2e5")))
    #expect(board.hash == EngineBoard(.initial, plyCapacity: 1).hash)
  }

  @Test
  func playRejectsAMoveIntoCheckAndLeavesTheBoardUnchanged() throws {
    let pinned = try position("Ke1 Be2 re8 ka8")
    var board = EngineBoard(pinned, plyCapacity: 1)
    #expect(!board.play(try uciMove("e2d3")))
    #expect(board.hash == EngineBoard(pinned, plyCapacity: 1).hash)
    // The pinned bishop cannot move; the king has d1, d2, f1 and f2.
    #expect(board.legalMoves().count == 4)
  }

  @Test
  func playMatchesThePromotionPiece() throws {
    var board = EngineBoard(try position("Ke1 kh8 Pa7"), plyCapacity: 1)
    #expect(!board.play(try uciMove("a7a8")))
    #expect(board.play(try uciMove("a7a8n")))
    let promoted = try position("Ke1 kh8 Na8", sideToMove: .black)
    #expect(board.hash == EngineBoard(promoted, plyCapacity: 1).hash)
  }
}
