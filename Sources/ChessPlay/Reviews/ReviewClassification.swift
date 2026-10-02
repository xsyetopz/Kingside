import ChessContent
import ChessCore
import Foundation

// Pure Game Review logic (no UI, no engine calls), tested in ReviewTests.swift.
// - `WinProbability`: White's expected points from an engine `Evaluation`.
// - `MoveClassifier.classify(_:thresholds:)`: a `MoveClassification` from a `MoveContext`;
//   the thresholds are `ContentCatalog.tuning.review`.
// - `AccuracyCalculator`: 0-100 accuracy from win-probability losses.
// - `SacrificeDetector.materialGivenUp(by:before:after:)`: SEE-lite material drop of a move.
// - `EvaluationLabel.text(_:)`: "+1.25", "-0.40", "M3", "1-0".
// - `MoveClassification.coachText(san:bestSAN:localization:)`: coach line such as
//   "e5 is a blunder. The best move was d4."

/// Game Review verdict for one played move.
public enum MoveClassification: String, CaseIterable, Sendable {
  case brilliant, great, best, excellent, good, book, inaccuracy, mistake, miss, blunder

  /// Localisation key of the grade's name, such as "Blunder".
  public var titleKey: String { "review.classification.\(rawValue).name" }

  /// Marked on the evaluation graph.
  public var isError: Bool { self == .mistake || self == .miss || self == .blunder }

  /// Moves that deserve a "best move was ..." hint and an engine arrow.
  var showsBestMove: Bool {
    switch self {
    case .good, .inaccuracy, .mistake, .miss, .blunder: true
    default: false
    }
  }

  /// Localisation key of the coach line, such as "%@ is a blunder."; the argument is the SAN.
  var coachKey: String { "review.coach.\(rawValue)" }

  /// Coach line for the move panel, e.g. "e5 is a blunder. The best move was d4."
  /// The best-move hint is added only to grades that `showsBestMove`.
  public func coachText(san: String, bestSAN: String?, localization: Localization) -> String {
    let text = localization.string(coachKey, san)
    guard showsBestMove, let bestSAN else { return text }
    return text + " " + localization.string("review.coach.bestMove", bestSAN)
  }
}

enum WinProbability {
  /// Logistic slope that maps centipawns to win probability; a model constant, not tuning.
  static let logisticSlope = 0.00368208

  /// White's expected points for `evaluation`; forced mates count as certain.
  static func white(_ evaluation: Evaluation) -> Double {
    if let mate = evaluation.mateIn, mate != 0 { return mate > 0 ? 1 : 0 }
    if evaluation.mateIn == 0 { return evaluation.centipawns > 0 ? 1 : 0 }
    return 1 / (1 + exp(-logisticSlope * Double(evaluation.centipawns)))
  }

  static func forSide(_ color: PieceColor, _ evaluation: Evaluation) -> Double {
    let white = white(evaluation)
    return color == .white ? white : 1 - white
  }
}

/// Everything the classifier needs about one ply. Evaluations are White's point of view.
struct MoveContext: Equatable, Sendable {
  var mover: PieceColor
  /// Best evaluation of the position before the move.
  var bestEvaluation: Evaluation
  /// Evaluation of the position after the played move.
  var playedEvaluation: Evaluation
  /// Evaluation of the runner-up move before the move; nil with a single legal move.
  var secondBestEvaluation: Evaluation?
  var playedBest: Bool
  var isBook: Bool = false
  /// Material the move gives up, from `SacrificeDetector`.
  var materialGivenUp: Int = 0
  /// Classification of the opponent's previous move.
  var previous: MoveClassification?

  init(
    mover: PieceColor,
    bestEvaluation: Evaluation,
    playedEvaluation: Evaluation,
    secondBestEvaluation: Evaluation?,
    playedBest: Bool,
    isBook: Bool = false,
    materialGivenUp: Int = 0,
    previous: MoveClassification? = nil
  ) {
    self.mover = mover
    self.bestEvaluation = bestEvaluation
    self.playedEvaluation = playedEvaluation
    self.secondBestEvaluation = secondBestEvaluation
    self.playedBest = playedBest
    self.isBook = isBook
    self.materialGivenUp = materialGivenUp
    self.previous = previous
  }

  /// Expected points the move lost; 0 for book moves and when the engine's best move was played.
  var loss: Double {
    guard !playedBest, !isBook else { return 0 }
    let before = WinProbability.forSide(mover, bestEvaluation)
    let after = WinProbability.forSide(mover, playedEvaluation)
    return max(0, before - after)
  }
}

enum MoveClassifier {
  /// `thresholds` is `ContentCatalog.tuning.review`.
  static func classify(
    _ context: MoveContext,
    thresholds: ReviewThresholds
  ) -> MoveClassification {
    if context.isBook { return .book }
    let loss = context.loss
    let bestProbability = WinProbability.forSide(context.mover, context.bestEvaluation)
    let afterProbability = WinProbability.forSide(context.mover, context.playedEvaluation)

    if context.materialGivenUp >= thresholds.brilliantMaterial, loss < thresholds.excellentLoss,
      afterProbability >= thresholds.brilliantMinWinProbability
    {
      return .brilliant
    }
    if context.playedBest, let second = context.secondBestEvaluation,
      bestProbability - WinProbability.forSide(context.mover, second) >= thresholds.greatGap
    {
      return .great
    }
    if context.playedBest { return .best }
    if let previous = context.previous, previous == .mistake || previous == .blunder,
      loss >= thresholds.inaccuracyLoss, bestProbability >= thresholds.missMinBestWinProbability,
      afterProbability >= thresholds.missMinWinProbabilityAfter
    {
      return .miss
    }
    if loss < thresholds.excellentLoss { return .excellent }
    if loss < thresholds.goodLoss { return .good }
    if loss < thresholds.inaccuracyLoss { return .inaccuracy }
    if loss < thresholds.mistakeLoss { return .mistake }
    return .blunder
  }
}

enum AccuracyCalculator {
  /// Accuracy 0...100 from the per-move losses (0...1) of one player; nil without moves.
  static func accuracy(losses: [Double]) -> Double? {
    guard !losses.isEmpty else { return nil }
    let averagePercent = losses.reduce(0, +) / Double(losses.count) * 100
    let value = 103.1668 * exp(-0.04354 * averagePercent) - 3.1669
    return min(100, max(0, value))
  }
}

enum SacrificeDetector {
  static func value(_ type: PieceType) -> Int {
    switch type {
    case .pawn: 1
    case .knight, .bishop: 3
    case .rook: 5
    case .queen: 9
    case .king: 0
    }
  }

  /// Net material the mover leaves en prise with `move`: the largest SEE-lite loss among the
  /// mover's pieces after the move, minus what the move captured. 0 when nothing is given up.
  static func materialGivenUp(
    by move: ChessMove,
    before: ChessPosition,
    after: ChessPosition
  ) -> Int {
    let mover = before.sideToMove
    var captured = before[move.to].map { value($0.type) } ?? 0
    if captured == 0, before[move.from]?.type == .pawn, move.from.file != move.to.file {
      captured = 1
    }
    let replies = after.legalMoves()
    var exposed = 0
    for (square, piece) in after.board where piece.color == mover && piece.type != .king {
      let attackers = replies.filter { $0.to == square }.compactMap { after[$0.from] }
      guard let cheapest = attackers.map({ value($0.type) }).min() else { continue }
      // Without the piece itself, which would otherwise count as its own defender.
      var others = after.board
      others[square] = nil
      let defended = ChessPosition(board: others).isSquareAttacked(square, by: mover)
      let loss = defended ? value(piece.type) - cheapest : value(piece.type)
      exposed = max(exposed, loss)
    }
    return max(0, exposed - captured)
  }
}

public enum EvaluationLabel {
  /// "+1.25" / "-0.40" in pawns, "M3" / "-M3" for mates, "1-0" / "0-1" once mated.
  public static func text(_ evaluation: Evaluation) -> String {
    if let mate = evaluation.mateIn {
      if mate == 0 { return evaluation.centipawns > 0 ? "1-0" : "0-1" }
      return mate > 0 ? "M\(mate)" : "-M\(-mate)"
    }
    let pawns = Double(evaluation.centipawns) / 100
    return pawns >= 0 ? String(format: "+%.2f", pawns) : String(format: "%.2f", pawns)
  }
}

/// Marks early moves as "Book"; the lines are `ContentCatalog.openingBook`.
extension OpeningBook {
  /// Number of leading plies of `sans` that follow a book line. Check and mate marks are ignored.
  func bookPlyCount(for sans: [String]) -> Int {
    let played = sans.map {
      $0.replacingOccurrences(of: "+", with: "").replacingOccurrences(of: "#", with: "")
    }
    var best = 0
    for line in lines.map({ $0.split(separator: " ").map(String.init) }) {
      var count = 0
      while count < min(line.count, played.count), line[count] == played[count] { count += 1 }
      best = max(best, count)
    }
    return best
  }
}
