import ChessContent
import ChessCore
import Observation

/// One analysed move of a reviewed game.
public struct ReviewedMove: Identifiable, Sendable {
  /// Index into `ChessGame.moves`.
  public let ply: Int
  public let san: String
  public let mover: PieceColor
  public let classification: MoveClassification
  /// Expected points lost, 0...1.
  public let loss: Double
  /// Engine evaluation of the position after the move (White's point of view).
  public let evaluationAfter: Evaluation
  /// Engine best move in the position before the move.
  let bestSAN: String?

  public var id: Int { ply }

  public func coachText(localization: Localization) -> String {
    classification.coachText(san: san, bestSAN: bestSAN, localization: localization)
  }
}

/// Engine results by game id, so reopening a review does not analyse again. The app keeps one
/// for its lifetime and gives it to each `GameReviewModel`.
@preconcurrency
@MainActor
public final class ReviewAnalysisCache {
  var analyses: [SavedGame.ID: [EngineAnalysis]] = [:]

  public init() {}
}

/// Runs the engine over every position of a saved game and classifies each move as results arrive.
/// `thresholds` is `ContentCatalog.tuning.review` and `openingBook` is
/// `ContentCatalog.openingBook`.
@preconcurrency
@Observable
@MainActor
public final class GameReviewModel {
  public let game: SavedGame
  /// Position before each move, followed by the final position.
  public let positions: [ChessPosition]
  public private(set) var analyses: [EngineAnalysis] = []
  public private(set) var moves: [ReviewedMove] = []
  public private(set) var isAnalyzing = false

  private let engine: ChessEngine
  private let thresholds: ReviewThresholds
  private let bookPlies: Int
  private let cache: ReviewAnalysisCache
  private var task: Task<Void, Never>?

  public init(
    game: SavedGame,
    engine: ChessEngine,
    thresholds: ReviewThresholds,
    openingBook: OpeningBook,
    cache: ReviewAnalysisCache
  ) {
    self.game = game
    self.engine = engine
    self.thresholds = thresholds
    self.cache = cache
    positions = game.game.moves.map(\.positionBefore) + [game.game.position]
    bookPlies =
      game.game.initialPosition == .initial
      ? openingBook.bookPlyCount(for: game.game.moves.map(\.san)) : 0
    for analysis in cache.analyses[game.id] ?? [] { append(analysis) }
  }

  public var moveCount: Int { game.game.moves.count }
  public var isComplete: Bool { analyses.count == positions.count }

  /// White's expected points, 0...1, at each analysed position: the evaluation graph.
  public var whiteExpectedPoints: [Double] { analyses.map { WinProbability.white($0.evaluation) } }

  /// Starts or resumes the analysis; results appear one move at a time.
  public func start() {
    guard task == nil, !isComplete else { return }
    isAnalyzing = true
    task = Task { [weak self] in
      await self?.run()
    }
  }

  public func stop() {
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
          limit: .time(thresholds.analysisTime)
        )
        guard !Task.isCancelled else { break }
        append(analysis)
        cache.analyses[game.id] = analyses
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
    let playedBest =
      played.move == before.bestMove
      || (played.move == before.secondBestMove && before.secondBestEvaluation == before.evaluation)
    let context = MoveContext(
      mover: position.sideToMove,
      bestEvaluation: before.evaluation,
      playedEvaluation: after.evaluation,
      secondBestEvaluation: before.secondBestEvaluation,
      playedBest: playedBest,
      isBook: ply < bookPlies,
      materialGivenUp: SacrificeDetector.materialGivenUp(
        by: played.move,
        before: position,
        after: positions[ply + 1]
      ),
      previous: moves.last?.classification
    )
    return ReviewedMove(
      ply: ply,
      san: played.san,
      mover: position.sideToMove,
      classification: MoveClassifier.classify(context, thresholds: thresholds),
      loss: context.loss,
      evaluationAfter: after.evaluation,
      bestSAN: before.bestMove.flatMap { try? ChessNotation.san(for: $0, in: position) }
    )
  }

  public func accuracy(for color: PieceColor) -> Double? {
    AccuracyCalculator.accuracy(losses: moves.filter { $0.mover == color }.map(\.loss))
  }
}
