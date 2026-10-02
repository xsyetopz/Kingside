import Testing

@testable import ChessCore

private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
private let kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"

/// A board sized for rules queries holds exactly `plyCapacity` made moves. Node counts are the
/// published perft results from chessprogramming.org.
@Suite
struct EngineBoardCapacityTests {
  @Test
  func perftUsesTheWholeCapacity() throws {
    var board = EngineBoard(try ChessPosition(fen: kiwipete), plyCapacity: 3)
    #expect(board.perft(3) == 97_862)
  }

  @Test
  func legalMovesNeedOneMadeMove() throws {
    var board = EngineBoard(try ChessPosition(fen: startFEN), plyCapacity: 1)
    #expect(board.legalMoves().count == 20)
  }

  @Test
  func gameHistoryDoesNotUseUpCapacity() throws {
    // 1. Nf3 Nf6 2. Ng1 Ng8 returns to the start position.
    let history = try [
      "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      "rnbqkbnr/pppppppp/8/8/8/5N2/PPPPPPPP/RNBQKB1R b KQkq - 1 1",
      "rnbqkb1r/pppppppp/5n2/8/8/5N2/PPPPPPPP/RNBQKB1R w KQkq - 2 2",
      "rnbqkb1r/pppppppp/5n2/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 3 2",
    ].map { try ChessPosition(fen: $0) }
    let current = try ChessPosition(
      fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 4 3"
    )
    var board = EngineBoard(current, history: history, plyCapacity: 2)
    #expect(board.perft(2) == 400)
  }
}
