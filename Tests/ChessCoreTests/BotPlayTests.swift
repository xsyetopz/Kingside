@testable import ChessCore
import Testing

@Suite
struct BotPlayTests {
  @Test
  func weakBotsCanChooseAnyRootMove() {
    #expect(EngineStrength(elo: 1399).candidateMoves == 256)
  }

  @Test
  func clubBotsChooseAmongFourRootMoves() {
    #expect(EngineStrength(elo: 1400).candidateMoves == 4)
    #expect(EngineStrength(elo: 1999).candidateMoves == 4)
  }

  @Test
  func strongBotsOnlyConsiderTheBestRootMove() {
    #expect(EngineStrength(elo: 2000).candidateMoves == 1)
  }

  @Test
  func thinkTimeIsLinearBetweenAnchors() {
    // Halfway between the 600 (250 ms) and 1000 (400 ms) anchors.
    #expect(EngineStrength(elo: 800).thinkTime == .milliseconds(325))
  }

  @Test
  func mistakeTemperatureIsLinearBetweenAnchors() {
    // Halfway between the 1000 (120 cp) and 1400 (80 cp) anchors.
    #expect(EngineStrength(elo: 1200).mistakeTemperature == 100)
  }

  // Expected values below are worked out by hand from the anchor table in `EngineStrength`
  // (Elo 250, 600, 1000, 1400, 1800, 2000, 2200), not computed by the code.

  @Test(arguments: [
    (100, 1), (250, 1), (400, 1), (600, 2), (700, 2), (800, 3), (1000, 3), (1400, 5), (1500, 6),
    (1600, 6),
    (1800, 7), (1900, 9), (2000, 10), (2100, 37), (2200, 64), (5000, 64),
  ])
  func searchDepthInterpolatesAndRounds(elo: Int, expected: Int) {
    // 400: 1.43 -> 1; 700: 2.25 -> 2; 800: 2.5 -> 3; 1500: 5.5 -> 6; 1900: 8.5 -> 9.
    #expect(EngineStrength(elo: elo).searchDepth == expected)
  }

  @Test(arguments: [
    (100, 200), (250, 200), (400, 166), (600, 120), (700, 108), (800, 95), (1000, 70), (1400, 35),
    (1500, 30),
    (1600, 25), (1800, 15), (1900, 10), (2000, 5), (2100, 3), (2200, 0), (5000, 0),
  ])
  func evaluationNoiseInterpolatesAndRounds(elo: Int, expected: Int) {
    // 400: 165.71 -> 166; 700: 107.5 -> 108; 2100: 2.5 -> 3.
    #expect(EngineStrength(elo: elo).evaluationNoise == expected)
  }

  @Test(arguments: [
    (100, 0.30), (250, 0.30), (700, 0.18), (800, 0.16), (1000, 0.12), (1400, 0.06), (1500, 0.05),
    (1600, 0.04),
    (1800, 0.02), (1900, 0.01), (2000, 0), (2100, 0), (5000, 0),
  ])
  func mistakeChanceInterpolatesLinearly(elo: Int, expected: Double) {
    #expect(abs(EngineStrength(elo: elo).mistakeChance - expected) < 1e-9)
  }

  @Test(arguments: [
    (100, 150), (250, 150), (400, 192), (600, 250), (700, 287), (800, 325), (1000, 400),
    (1400, 700),
    (1500, 825), (1600, 950), (1800, 1200), (1900, 1500), (2000, 1800), (2100, 2150), (2200, 2500),
    (5000, 2500),
  ])
  func thinkTimeInterpolatesAndTruncates(elo: Int, milliseconds: Int) {
    // 400: 192.86 ms and 700: 287.5 ms are truncated, not rounded.
    #expect(EngineStrength(elo: elo).thinkTime == .milliseconds(milliseconds))
  }

  @Test(arguments: [
    (100, 250), (250, 250), (400, 220), (600, 180), (700, 165), (800, 150), (1000, 120), (1400, 80),
    (1500, 73), (1600, 65), (1800, 50), (1900, 40), (2000, 30), (2100, 25), (2200, 20), (5000, 20),
  ])
  func mistakeTemperatureInterpolatesAndRounds(elo: Int, expected: Int) {
    // 1500: 72.5 -> 73.
    #expect(EngineStrength(elo: elo).mistakeTemperature == expected)
  }

  @Test(arguments: [
    (100, 256), (250, 256), (800, 256), (1399, 256), (1400, 4), (1800, 4), (1999, 4), (2000, 1),
    (2200, 1), (5000, 1),
  ])
  func candidateMovesStepsAtTheThresholds(elo: Int, expected: Int) {
    #expect(EngineStrength(elo: elo).candidateMoves == expected)
  }

  @Test
  func eloIsClampedToTheSupportedRange() {
    #expect(EngineStrength(elo: 100).elo == 250)
    #expect(EngineStrength(elo: 5000).elo == 2200)
    #expect(EngineStrength(elo: 1234).elo == 1234)
  }

  @Test
  func maximumStrengthAlwaysChoosesTheFirstLine() {
    // The second line scores far higher, yet no noise or mistakes apply at 2200.
    let lines = [line(move: 1, score: -1_000), line(move: 2, score: 1_000)]
    var generator = SeededGenerator(state: 7)
    for _ in 0..<200 {
      #expect(
        ChessEngine.choose(from: lines, strength: EngineStrength(elo: 2200), using: &generator) == 1
      )
    }
  }

  @Test(arguments: [2000, 2100])
  func singleCandidateStrengthChoosesTheFirstLine(elo: Int) {
    // Only the best move is exact at these strengths, so the unscored lines are never chosen.
    let lines = [line(move: 1, score: 0), line(move: 2, score: 900, exact: false)]
    var generator = SeededGenerator(state: 7)
    for _ in 0..<200 {
      #expect(
        ChessEngine.choose(from: lines, strength: EngineStrength(elo: elo), using: &generator) == 1
      )
    }
  }

  @Test
  func weakStrengthCanChooseABetterScoredLaterLine() {
    let lines = [line(move: 1, score: -1_000), line(move: 2, score: 1_000)]
    var generator = SeededGenerator(state: 7)
    let moves = (0..<50).map { _ in
      ChessEngine.choose(from: lines, strength: EngineStrength(elo: 250), using: &generator)
    }
    #expect(moves.contains(2))
  }

  private func line(move: EngineMove, score: Int, exact: Bool = true) -> RootLine {
    RootLine(move: move, score: score, exact: exact, pv: [move])
  }
}

/// A deterministic SplitMix64 generator so the draws are reproducible.
private struct SeededGenerator: RandomNumberGenerator {
  var state: UInt64

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}
