import ChessCore
import Testing

// Refactor pin: literals recorded from the search as of T2c, not independent oracles. They
// detect any change in search behavior (pruning, ordering, evaluation) and are re-recorded
// only when a change is meant to alter the search.
struct SearchPin: Sendable, CustomTestStringConvertible {
  let name: String
  let fen: String
  let nodes: Int
  let best: String
  var testDescription: String { name }
}

@Suite
struct SearchPinTests {
  @Test(arguments: [
    SearchPin(
      name: "start",
      fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1",
      nodes: 6_454,
      best: "c2c4"
    ),
    SearchPin(
      name: "kiwipete",
      fen: "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
      nodes: 28_155,
      best: "e2a6"
    ),
    SearchPin(
      name: "middlegame",
      fen: "r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R1BQKB1R w KQ - 0 7",
      nodes: 9_910,
      best: "f1d3"
    ),
    SearchPin(
      name: "endgame",
      fen: "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1",
      nodes: 5_111,
      best: "b4c4"
    ),
  ])
  func depthFiveSearch(_ pin: SearchPin) async throws {
    let analysis = try await ChessEngine().analyze(
      position: try ChessPosition(fen: pin.fen),
      limit: .depth(5)
    )
    #expect(analysis.nodes == pin.nodes)
    #expect(analysis.bestMove?.uci == pin.best)
  }
}
