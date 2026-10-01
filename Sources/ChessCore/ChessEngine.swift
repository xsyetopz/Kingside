import Foundation

/// An engine score from White's point of view.
///
/// `mateIn` is set when a forced mate was found: positive when White mates in that many
/// moves, negative when Black does, and `0` when the side to move is already checkmated.
/// For mate scores `centipawns` is ±(20000 − plies to mate), so it still sorts correctly
/// and its sign tells who wins.
public struct Evaluation: Codable, Equatable, Sendable {
  public let centipawns: Int
  public let mateIn: Int?

  public init(centipawns: Int, mateIn: Int? = nil) {
    self.centipawns = centipawns
    self.mateIn = mateIn
  }
}

public enum ChessEngineError: Error, Equatable {
  case noLegalMove
}

/// How long an analysis may search. The search stops at whichever limit comes first; with
/// neither set it searches for one second.
public struct SearchLimit: Hashable, Sendable {
  public var depth: Int?
  public var time: Duration?

  public init(depth: Int? = nil, time: Duration? = nil) {
    self.depth = depth
    self.time = time
  }

  public static func depth(_ depth: Int) -> Self { Self(depth: depth) }
  public static func time(_ time: Duration) -> Self { Self(time: time) }
}

public struct EngineAnalysis: Equatable, Sendable {
  /// Score of the best move, from White's point of view.
  public let evaluation: Evaluation
  /// `nil` when the side to move has no legal move (checkmate or stalemate) or the engine does
  /// not support the position (see `ChessEngine.analyze`).
  public let bestMove: ChessMove?
  /// Expected line starting with `bestMove`.
  public let principalVariation: [ChessMove]
  /// Last fully completed iteration depth (0 when there is no legal move).
  public let depth: Int
  /// Second-best root move and its score from White's point of view; `nil` with a single legal
  /// move.
  public let secondBestMove: ChessMove?
  public let secondBestEvaluation: Evaluation?
  public let nodes: Int
}

/// Built-in engine: alpha-beta search over an internal 0x88 board. Searches run on this actor,
/// never on the main actor, and stop cooperatively when their task is cancelled.
public actor ChessEngine {
  private let table: TranspositionTable

  public init(hashMegabytes: Int = 8) {
    table = TranspositionTable(megabytes: hashMegabytes)
  }

  /// Picks a move for the side to move in `game`, playing at `strength`. Earlier positions of
  /// the game count for repetition. Throws `CancellationError` when the task is cancelled and
  /// `ChessEngineError.noLegalMove` when the game is already over or the engine does not support
  /// the position.
  public func bestMove(game: ChessGame, strength: EngineStrength) throws -> ChessMove {
    try Task.checkCancellation()
    guard game.position.isSupportedByEngine else { throw ChessEngineError.noLegalMove }
    let board = EngineBoard(game.position, history: game.moves.map(\.positionBefore))
    var searcher = EngineSearcher(board: board, table: table)
    let result = searcher.search(
      maxDepth: strength.searchDepth,
      timeLimit: strength.thinkTime,
      multiPV: strength.candidateMoves
    )
    if result.cancelled { throw CancellationError() }
    guard !result.lines.isEmpty else { throw ChessEngineError.noLegalMove }
    var generator = SystemRandomNumberGenerator()
    return Self.choose(from: result.lines, strength: strength, using: &generator).chessMove
  }

  /// Searches `position` and reports the best line and the runner-up score (MultiPV 2).
  /// `history` holds the earlier positions of the game, oldest first; repeats count as draws.
  /// A position the engine does not support has no best move: one without exactly one king per
  /// side, with a clock outside 0 (1 for the move number) ..< `Int.max`, with more material than
  /// a game can reach, or with the side not to move in check.
  public func analyze(
    position: ChessPosition,
    history: [ChessPosition] = [],
    limit: SearchLimit
  ) throws -> EngineAnalysis {
    try Task.checkCancellation()
    let whiteToMove = position.sideToMove == .white
    guard position.isSupportedByEngine else {
      return Self.analysisWithoutMove(evaluation: Evaluation(centipawns: 0), nodes: 0)
    }
    var searcher = EngineSearcher(board: EngineBoard(position, history: history), table: table)
    let time = limit.time ?? (limit.depth == nil ? .seconds(1) : nil)
    let result = searcher.search(
      maxDepth: limit.depth ?? EngineSearcher.maxPly,
      timeLimit: time,
      multiPV: 2
    )
    if result.cancelled { throw CancellationError() }

    guard let best = result.lines.first else {
      let evaluation =
        result.inCheck
        ? Evaluation(centipawns: whiteToMove ? -20_000 : 20_000, mateIn: 0)
        : Evaluation(centipawns: 0)
      return Self.analysisWithoutMove(evaluation: evaluation, nodes: result.nodes)
    }
    let second = result.lines.count > 1 && result.lines[1].exact ? result.lines[1] : nil
    return EngineAnalysis(
      evaluation: Self.evaluation(best.score, whiteToMove: whiteToMove),
      bestMove: best.move.chessMove,
      principalVariation: best.pv.map(\.chessMove),
      depth: result.depth,
      secondBestMove: second?.move.chessMove,
      secondBestEvaluation: second.map { Self.evaluation($0.score, whiteToMove: whiteToMove) },
      nodes: result.nodes
    )
  }

  private static func analysisWithoutMove(evaluation: Evaluation, nodes: Int) -> EngineAnalysis {
    EngineAnalysis(
      evaluation: evaluation,
      bestMove: nil,
      principalVariation: [],
      depth: 0,
      secondBestMove: nil,
      secondBestEvaluation: nil,
      nodes: nodes
    )
  }

  /// Converts a side-to-move search score into a White-relative `Evaluation`.
  static func evaluation(_ score: Int, whiteToMove: Bool) -> Evaluation {
    let white = whiteToMove ? score : -score
    guard abs(white) >= EngineSearcher.mateBound else { return Evaluation(centipawns: white) }
    let plies = EngineSearcher.mate - abs(white)
    let moves = (plies + 1) / 2
    return white > 0
      ? Evaluation(centipawns: 20_000 - plies, mateIn: moves)
      : Evaluation(centipawns: -(20_000 - plies), mateIn: -moves)
  }
}
