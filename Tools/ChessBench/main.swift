import ChessCore
import Foundation

// Fixed-depth searches with a fresh engine per position; prints nodes per second.
// Run with `swift run -c release ChessBench`.
let positions: [(name: String, fen: String, depth: Int)] = [
  ("start", "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 12),
  ("kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 10),
  ("middlegame", "r1bq1rk1/pp2bppp/2n1pn2/3p4/2PP4/2N1PN2/PP3PPP/R1BQKB1R w KQ - 0 7", 10),
  ("endgame", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 16),
]
var totalNodes = 0
var totalSeconds = 0.0
for entry in positions {
  let position = try ChessPosition(fen: entry.fen)
  let clock = ContinuousClock()
  var analysis: EngineAnalysis?
  let elapsed = try await clock.measure {
    analysis = try await ChessEngine().analyze(position: position, limit: .depth(entry.depth))
  }
  let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
  let nodes = analysis?.nodes ?? 0
  totalNodes += nodes
  totalSeconds += seconds
  let best = analysis?.bestMove?.uci ?? "-"
  print(
    "\(entry.name): depth \(entry.depth) nodes \(nodes) time \(String(format: "%.2f", seconds)) s "
      + "nps \(Int(Double(nodes) / max(seconds, 1e-9))) best \(best) "
      + "score \(analysis?.evaluation.centipawns ?? 0)"
  )
}
print(
  "total: nodes \(totalNodes) time \(String(format: "%.2f", totalSeconds)) s "
    + "nps \(Int(Double(totalNodes) / max(totalSeconds, 1e-9)))"
)
