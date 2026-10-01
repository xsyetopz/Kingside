import Foundation

/// Playing strength on an Elo-like scale from 250 to 2200. All search settings derive from `elo`.
public struct EngineStrength: Codable, Hashable, Sendable {
  static let minimumElo = 250
  static let maximumElo = 2200

  public let elo: Int

  public init(elo: Int) {
    self.elo = min(max(elo, Self.minimumElo), Self.maximumElo)
  }

  //                            elo:   250   600  1000  1400  1800  2000  2200
  private static let anchors = [250, 600, 1000, 1400, 1800, 2000, 2200]
  private static let depths = [1.0, 2, 3, 5, 7, 10, 64]
  private static let thinkMilliseconds = [150.0, 250, 400, 700, 1200, 1800, 2500]
  private static let noises = [200.0, 120, 70, 35, 15, 5, 0]
  private static let mistakes = [0.30, 0.20, 0.12, 0.06, 0.02, 0, 0]
  private static let temperatures = [250.0, 180, 120, 80, 50, 30, 20]

  /// Below this Elo every root move is scored exactly, so any of them can be chosen.
  private static let allCandidatesBelowElo = 1400
  /// From this Elo on only the best move is scored exactly.
  private static let singleCandidateFromElo = 2000
  /// MultiPV width meaning "every root move"; no position has more legal moves.
  private static let allCandidates = 256
  private static let fewCandidates = 4

  private func interpolate(_ values: [Double]) -> Double {
    let anchors = Self.anchors
    guard let upper = anchors.firstIndex(where: { $0 >= elo }), upper > 0 else { return values[0] }
    let fraction = Double(elo - anchors[upper - 1]) / Double(anchors[upper] - anchors[upper - 1])
    return values[upper - 1] + (values[upper] - values[upper - 1]) * fraction
  }

  /// Maximum nominal search depth in plies.
  var searchDepth: Int { Int(interpolate(Self.depths).rounded()) }
  /// Time budget for one move; the search stops earlier when it reaches `searchDepth`.
  var thinkTime: Duration { .milliseconds(Int(interpolate(Self.thinkMilliseconds))) }
  /// Scale of the random centipawn noise added to candidate move scores.
  var evaluationNoise: Int { Int(interpolate(Self.noises).rounded()) }
  /// Probability of choosing among candidates by a score-weighted draw instead of the best noisy
  /// score.
  var mistakeChance: Double { interpolate(Self.mistakes) }
  /// Softmax temperature, in centipawns, of that weighted draw; higher picks worse moves more
  /// often.
  var mistakeTemperature: Int { Int(interpolate(Self.temperatures).rounded()) }
  /// Root moves that receive exact scores and can be chosen (MultiPV width).
  var candidateMoves: Int {
    if elo < Self.allCandidatesBelowElo { return Self.allCandidates }
    return elo < Self.singleCandidateFromElo ? Self.fewCandidates : 1
  }
}

extension ChessEngine {
  /// Mate scores are clamped to this many centipawns so a mate still dominates without
  /// overflowing the softmax weights.
  private static let chooseScoreClamp = 2_000
  /// The sum of this many uniform draws in -1...1 approximates a bell curve with standard
  /// deviation 1, which `noise` then scales.
  private static let noiseDrawCount = 3

  /// Picks the move to play from scored root lines. Strong settings play the best move;
  /// weaker settings add noise to candidate scores and sometimes draw a candidate with
  /// probability weighted by its score.
  static func choose<Generator: RandomNumberGenerator>(
    from lines: [RootLine],
    strength: EngineStrength,
    using generator: inout Generator
  ) -> EngineMove {
    let candidates = lines.filter(\.exact)
    guard candidates.count > 1, strength.evaluationNoise > 0 || strength.mistakeChance > 0 else {
      return lines[0].move
    }
    let scores = candidates.map {
      Double(min(max($0.score, -chooseScoreClamp), chooseScoreClamp))
    }
    let index =
      Double.random(in: 0..<1, using: &generator) < strength.mistakeChance
      ? weightedDrawIndex(scores, temperature: strength.mistakeTemperature, using: &generator)
      : noisyBestIndex(scores, noise: strength.evaluationNoise, using: &generator)
    return candidates[index].move
  }

  /// Draws an index with softmax probability over `scores` at `temperature` centipawns.
  private static func weightedDrawIndex<Generator: RandomNumberGenerator>(
    _ scores: [Double],
    temperature: Int,
    using generator: inout Generator
  ) -> Int {
    let top = scores.max() ?? 0
    let temperature = Double(max(temperature, 1))
    let weights = scores.map { exp(($0 - top) / temperature) }
    var draw = Double.random(in: 0..<weights.reduce(0, +), using: &generator)
    for (index, weight) in weights.enumerated() {
      draw -= weight
      if draw < 0 { return index }
    }
    return 0
  }

  /// The index of the highest score after adding random noise of scale `noise` to each.
  private static func noisyBestIndex<Generator: RandomNumberGenerator>(
    _ scores: [Double],
    noise: Int,
    using generator: inout Generator
  ) -> Int {
    let noise = Double(noise)
    var bestIndex = 0
    var bestScore = -Double.infinity
    for (index, score) in scores.enumerated() {
      let jitter =
        (0..<noiseDrawCount).reduce(0.0) { sum, _ in
          sum + Double.random(in: -1...1, using: &generator)
        } * noise
      if score + jitter > bestScore {
        bestScore = score + jitter
        bestIndex = index
      }
    }
    return bestIndex
  }
}
