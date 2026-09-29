import Foundation
import ChessCore

// Pure Game Review logic (no UI, no engine calls), unit-tested in ReviewTests.swift.
// - `ReviewThresholds`: every tuning constant of the review in one place.
// - `WinProbability`: White's expected points from an engine `Evaluation`.
// - `MoveClassifier.classify(_:)`: a `MoveClassification` from a `MoveContext`.
// - `AccuracyCalculator`: 0-100 accuracy from win-probability losses.
// - `SacrificeDetector.materialGivenUp(by:before:after:)`: SEE-lite material drop of a move.
// - `EvaluationLabel.text(_:)`: "+1.25", "-0.40", "M3", "1-0".
// - `MoveClassification.coachText(san:bestSAN:)`: coach line such as "e5 is a blunder. The best move was d4."

/// Game Review verdict for one played move.
enum MoveClassification: String, CaseIterable, Sendable {
    case brilliant, great, best, excellent, good, book, inaccuracy, mistake, miss, blunder

    var title: String {
        switch self {
        case .brilliant: "Brilliant"
        case .great: "Great"
        case .best: "Best"
        case .excellent: "Excellent"
        case .good: "Good"
        case .book: "Book"
        case .inaccuracy: "Inaccuracy"
        case .mistake: "Mistake"
        case .miss: "Miss"
        case .blunder: "Blunder"
        }
    }

    /// Moves that deserve a "best move was ..." hint and an engine arrow.
    var showsBestMove: Bool {
        switch self {
        case .good, .inaccuracy, .mistake, .miss, .blunder: true
        default: false
        }
    }

    /// Marked on the evaluation graph.
    var isError: Bool { self == .mistake || self == .miss || self == .blunder }

    /// Coach line for the move panel, e.g. "e5 is a blunder. The best move was d4."
    func coachText(san: String, bestSAN: String?) -> String {
        let hint = bestSAN.map { " The best move was \($0)." } ?? ""
        switch self {
        case .brilliant: return "\(san) is brilliant! A strong sacrifice."
        case .great: return "\(san) is a great move. Nothing else keeps the position."
        case .best: return "\(san) is best."
        case .excellent: return "\(san) is excellent."
        case .good: return "\(san) is good." + hint
        case .book: return "\(san) is a book move."
        case .inaccuracy: return "\(san) is an inaccuracy." + hint
        case .mistake: return "\(san) is a mistake." + hint
        case .miss: return "\(san) misses the chance to punish the last move." + hint
        case .blunder: return "\(san) is a blunder." + hint
        }
    }
}

/// Tuning constants of Game Review. Losses and probabilities are expected points (0...1).
enum ReviewThresholds {
    /// Logistic slope that maps centipawns to win probability.
    static let logisticSlope = 0.00368208
    /// Upper bounds (exclusive) of the loss for each grade.
    static let excellentLoss = 0.02
    static let goodLoss = 0.05
    static let inaccuracyLoss = 0.10
    static let mistakeLoss = 0.20
    /// Great: the played best move is at least this much better than the second-best move.
    static let greatGap = 0.15
    /// Brilliant: the move gives up at least this much material (pawn = 1)...
    static let brilliantMaterial = 2
    /// ...loses less than `excellentLoss`, and leaves the mover at least this win probability.
    static let brilliantMinWinProbability = 0.45
    /// Miss: after an opponent mistake or blunder, the best move gave at least this much...
    static let missMinBestWinProbability = 0.75
    /// ...and the played move lost at least `inaccuracyLoss` without dropping below this.
    static let missMinWinProbabilityAfter = 0.5
    /// Engine time per position; the Apple TV HD's A8 needs short searches.
    static let analysisTime: Duration = .milliseconds(250)
}

enum WinProbability {
    /// White's expected points for `evaluation`; forced mates count as certain.
    static func white(_ evaluation: Evaluation) -> Double {
        if let mate = evaluation.mateIn, mate != 0 { return mate > 0 ? 1 : 0 }
        if evaluation.mateIn == 0 { return evaluation.centipawns > 0 ? 1 : 0 }
        return 1 / (1 + exp(-ReviewThresholds.logisticSlope * Double(evaluation.centipawns)))
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

    /// Expected points the move lost; 0 for book moves and when the engine's best move was played.
    var loss: Double {
        guard !playedBest, !isBook else { return 0 }
        let before = WinProbability.forSide(mover, bestEvaluation)
        let after = WinProbability.forSide(mover, playedEvaluation)
        return max(0, before - after)
    }
}

enum MoveClassifier {
    static func classify(_ context: MoveContext) -> MoveClassification {
        typealias T = ReviewThresholds
        if context.isBook { return .book }
        let loss = context.loss
        let bestProbability = WinProbability.forSide(context.mover, context.bestEvaluation)
        let afterProbability = WinProbability.forSide(context.mover, context.playedEvaluation)

        if context.materialGivenUp >= T.brilliantMaterial, loss < T.excellentLoss,
           afterProbability >= T.brilliantMinWinProbability {
            return .brilliant
        }
        if context.playedBest, let second = context.secondBestEvaluation,
           bestProbability - WinProbability.forSide(context.mover, second) >= T.greatGap {
            return .great
        }
        if context.playedBest { return .best }
        if let previous = context.previous, previous == .mistake || previous == .blunder,
           loss >= T.inaccuracyLoss, bestProbability >= T.missMinBestWinProbability,
           afterProbability >= T.missMinWinProbabilityAfter {
            return .miss
        }
        if loss < T.excellentLoss { return .excellent }
        if loss < T.goodLoss { return .good }
        if loss < T.inaccuracyLoss { return .inaccuracy }
        if loss < T.mistakeLoss { return .mistake }
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
    static func materialGivenUp(by move: ChessMove, before: ChessPosition, after: ChessPosition) -> Int {
        let mover = before.sideToMove
        var captured = before[move.to].map { value($0.type) } ?? 0
        if captured == 0, before[move.from]?.type == .pawn, move.from.file != move.to.file { captured = 1 }
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

enum EvaluationLabel {
    /// "+1.25" / "-0.40" in pawns, "M3" / "-M3" for mates, "1-0" / "0-1" once mated.
    static func text(_ evaluation: Evaluation) -> String {
        if let mate = evaluation.mateIn {
            if mate == 0 { return evaluation.centipawns > 0 ? "1-0" : "0-1" }
            return mate > 0 ? "M\(mate)" : "-M\(-mate)"
        }
        let pawns = Double(evaluation.centipawns) / 100
        return pawns >= 0 ? String(format: "+%.2f", pawns) : String(format: "%.2f", pawns)
    }
}
