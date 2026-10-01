import ChessCore
import Testing

private let startFEN = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
private let kiwipete = "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
private let position3 = "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
private let position4 = "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"

/// Published node counts from chessprogramming.org "Perft Results", one entry per depth.
private struct PositionPerft: Sendable, CustomTestStringConvertible {
  let name: String
  let fen: String
  let nodes: [Int]
  var testDescription: String { name }
}

private func perft(_ position: ChessPosition, depth: Int) throws -> Int {
  let moves = position.legalMoves()
  if depth == 1 { return moves.count }
  return try moves.reduce(0) { $0 + (try perft(position.applying($1), depth: depth - 1)) }
}

@Suite
struct PerftTests {
  @Test(arguments: [
    PositionPerft(name: "start", fen: startFEN, nodes: [20, 400, 8_902, 197_281]),
    PositionPerft(name: "kiwipete", fen: kiwipete, nodes: [48, 2_039, 97_862]),
    PositionPerft(name: "position 3", fen: position3, nodes: [14, 191, 2_812, 43_238]),
    PositionPerft(name: "position 4", fen: position4, nodes: [6, 264, 9_467]),
  ])
  private func perftMatchesPublishedCounts(_ test: PositionPerft) throws {
    let position = try ChessPosition(fen: test.fen)
    for (index, expected) in test.nodes.enumerated() {
      #expect(try perft(position, depth: index + 1) == expected, "depth \(index + 1)")
    }
  }
}
