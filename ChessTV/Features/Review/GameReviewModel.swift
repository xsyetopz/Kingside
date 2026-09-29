import Foundation
import ChessCore

/// One analysed move of a reviewed game.
struct ReviewedMove: Identifiable, Sendable {
    /// Index into `ChessGame.moves`.
    let ply: Int
    let san: String
    let move: ChessMove
    let mover: PieceColor
    let classification: MoveClassification
    /// Expected points lost, 0...1.
    let loss: Double
    /// Engine evaluation of the position after the move (White's point of view).
    let evaluationAfter: Evaluation
    /// Engine best move and line in the position before the move.
    let bestMove: ChessMove?
    let bestSAN: String?
    let bestLine: [ChessMove]

    var id: Int { ply }

    var coachText: String { classification.coachText(san: san, bestSAN: bestSAN) }
}

/// Engine results kept for the app session so reopening a review does not analyse again.
@MainActor
private enum ReviewAnalysisCache {
    static var analyses: [UUID: [EngineAnalysis]] = [:]
}

/// Runs the engine over every position of a saved game and classifies each move as results arrive.
@MainActor
final class GameReviewModel: ObservableObject {
    let game: SavedGame
    /// Position before each move, followed by the final position.
    let positions: [ChessPosition]
    @Published private(set) var analyses: [EngineAnalysis] = []
    @Published private(set) var moves: [ReviewedMove] = []
    @Published private(set) var isAnalyzing = false

    private let engine: ChessEngine
    private let bookPlies: Int
    private var task: Task<Void, Never>?

    init(game: SavedGame, engine: ChessEngine) {
        self.game = game
        self.engine = engine
        positions = game.game.moves.map(\.positionBefore) + [game.game.position]
        bookPlies = game.game.initialPosition == .initial ? OpeningBook.bookPlyCount(for: game.game.moves.map(\.san)) : 0
        for analysis in ReviewAnalysisCache.analyses[game.id] ?? [] { append(analysis) }
    }

    var moveCount: Int { game.game.moves.count }
    var isComplete: Bool { analyses.count == positions.count }

    /// Starts or resumes the analysis; results appear one move at a time.
    func start() {
        guard task == nil, !isComplete else { return }
        isAnalyzing = true
        task = Task { [weak self] in
            await self?.run()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isAnalyzing = false
    }

    private func run() async {
        while analyses.count < positions.count, !Task.isCancelled {
            let index = analyses.count
            do {
                let analysis = try await engine.analyze(
                    position: positions[index],
                    history: Array(positions[..<index]),
                    limit: .time(ReviewThresholds.analysisTime)
                )
                guard !Task.isCancelled else { break }
                append(analysis)
                ReviewAnalysisCache.analyses[game.id] = analyses
            } catch {
                break
            }
        }
        // A cancelled run was already reset by `stop()`, which may have started a new task since.
        guard !Task.isCancelled else { return }
        task = nil
        isAnalyzing = false
    }

    /// Adds the analysis of the next position; each new position completes the move before it.
    private func append(_ analysis: EngineAnalysis) {
        analyses.append(analysis)
        let ply = analyses.count - 2
        guard ply >= 0 else { return }
        moves.append(review(ply: ply, before: analyses[ply], after: analysis))
    }

    private func review(ply: Int, before: EngineAnalysis, after: EngineAnalysis) -> ReviewedMove {
        let played = game.game.moves[ply]
        let position = positions[ply]
        let playedBest = played.move == before.bestMove
            || (played.move == before.secondBestMove && before.secondBestEvaluation == before.evaluation)
        let context = MoveContext(
            mover: position.sideToMove,
            bestEvaluation: before.evaluation,
            playedEvaluation: after.evaluation,
            secondBestEvaluation: before.secondBestEvaluation,
            playedBest: playedBest,
            isBook: ply < bookPlies,
            materialGivenUp: SacrificeDetector.materialGivenUp(by: played.move, before: position, after: positions[ply + 1]),
            previous: moves.last?.classification
        )
        return ReviewedMove(
            ply: ply,
            san: played.san,
            move: played.move,
            mover: position.sideToMove,
            classification: MoveClassifier.classify(context),
            loss: context.loss,
            evaluationAfter: after.evaluation,
            bestMove: before.bestMove,
            bestSAN: before.bestMove.flatMap { try? ChessNotation.san(for: $0, in: position) },
            bestLine: before.principalVariation
        )
    }

    func accuracy(for color: PieceColor) -> Double? {
        AccuracyCalculator.accuracy(losses: moves.filter { $0.mover == color }.map(\.loss))
    }

    func count(_ classification: MoveClassification, for color: PieceColor) -> Int {
        moves.filter { $0.mover == color && $0.classification == classification }.count
    }
}
