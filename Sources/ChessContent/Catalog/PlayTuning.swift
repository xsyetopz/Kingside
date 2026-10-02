/// `play-tuning.json`: the tunable numbers of play, puzzles, and review. `ChessPlay` holds the
/// rules that use them.
public struct PlayTuning: Codable, Hashable, Sendable {
  public let clock: ClockTuning
  public let drawOffer: DrawOfferTuning
  public let game: GameTuning
  public let puzzleRating: PuzzleRatingTuning
  public let puzzleSelection: PuzzleSelectionTuning
  public let puzzleRush: PuzzleRushTuning
  public let puzzleBoard: PuzzleBoardTuning
  public let review: ReviewThresholds
}

public struct ClockTuning: Codable, Hashable, Sendable {
  /// A side's clock counts as low at or below this many seconds.
  public let lowTimeSeconds: Double
  /// Interval at which a running clock is charged and redrawn.
  public let tickMilliseconds: Int

  public var tickInterval: Duration { .milliseconds(tickMilliseconds) }
}

/// When a bot accepts a draw offer.
public struct DrawOfferTuning: Codable, Hashable, Sendable {
  /// Bots accept from this ply on when they are not clearly better.
  public let minimumPly: Int
  /// Largest advantage, in centipawns from the bot's side, at which it still accepts.
  public let maximumAdvantage: Int
  /// "Near zero", in centipawns, for low-material positions.
  public let equalMargin: Int
  /// Total material of both sides (pawn 1, minor 3, rook 5, queen 9) counted as very low.
  public let lowMaterialLimit: Int
  /// Engine time the bot spends judging the position before it answers.
  let analysisMilliseconds: Int

  public var analysisTime: Duration { .milliseconds(analysisMilliseconds) }
}

/// Bot pacing, blunder chat, and hints in a game.
public struct GameTuning: Codable, Hashable, Sendable {
  /// Minimum bot think time is `botThinkBaseSeconds` plus up to `botThinkExtraSeconds`,
  /// scaled by the number of legal moves up to `botThinkBusyMoveCount`.
  public let botThinkBaseSeconds: Double
  public let botThinkExtraSeconds: Double
  public let botThinkBusyMoveCount: Int
  /// Minimum drop, in centipawns from the player's side, that the bot calls a blunder.
  public let blunderCentipawns: Int
  /// Engine time for each of the two evaluations of the blunder check.
  let blunderAnalysisMilliseconds: Int
  /// Engine time for a hint.
  let hintAnalysisMilliseconds: Int

  public var blunderAnalysisTime: Duration { .milliseconds(blunderAnalysisMilliseconds) }
  public var hintAnalysisTime: Duration { .milliseconds(hintAnalysisMilliseconds) }
}

/// Elo update for rated puzzles.
public struct PuzzleRatingTuning: Codable, Hashable, Sendable {
  public let initial: Int
  /// The rating never drops below this.
  public let minimum: Int
  /// Rated puzzles played with `provisionalKFactor`; `establishedKFactor` applies after them.
  public let provisionalGames: Int
  public let provisionalKFactor: Double
  public let establishedKFactor: Double
}

/// Rating windows for picking puzzles.
public struct PuzzleSelectionTuning: Codable, Hashable, Sendable {
  /// Rated play picks an unseen puzzle within this many points of the player's rating.
  public let ratedWindow: Int
  /// Puzzle Rush: the n-th puzzle (0-based) targets `rushStartRating + n * rushRatingStep`,
  /// at most `rushMaximumRating`, within `rushWindow` points.
  public let rushStartRating: Int
  public let rushRatingStep: Int
  public let rushMaximumRating: Int
  public let rushWindow: Int
  /// The Daily Puzzle is drawn from this rating range (inclusive).
  public let dailyMinimumRating: Int
  public let dailyMaximumRating: Int
}

public struct PuzzleRushTuning: Codable, Hashable, Sendable {
  /// Wrong puzzles that end a run.
  public let maxStrikes: Int
  /// Countdown seconds per timed mode id; a mode without an entry has no clock.
  public let timeLimits: [String: Double]
  /// Pause after a puzzle ends, before the next one loads (or the run ends).
  let nextPuzzleMilliseconds: Int

  public var nextPuzzleDelay: Duration { .milliseconds(nextPuzzleMilliseconds) }
}

/// Pacing of a puzzle on the board.
public struct PuzzleBoardTuning: Codable, Hashable, Sendable {
  /// Pause after a puzzle loads, before the opponent's first move.
  let introMilliseconds: Int
  /// Pause between the solver's correct move and the opponent's reply.
  let replyMilliseconds: Int
  /// Pause between the moves of the solution walk-through.
  let solutionStepMilliseconds: Int

  public var introDelay: Duration { .milliseconds(introMilliseconds) }
  public var replyDelay: Duration { .milliseconds(replyMilliseconds) }
  public var solutionStepDelay: Duration { .milliseconds(solutionStepMilliseconds) }
}

/// Game Review grades. Losses and probabilities are expected points (0...1).
public struct ReviewThresholds: Codable, Hashable, Sendable {
  /// Upper bounds (exclusive) of the loss for each grade.
  public let excellentLoss: Double
  public let goodLoss: Double
  public let inaccuracyLoss: Double
  public let mistakeLoss: Double
  /// Great: the played best move is at least this much better than the second-best move.
  public let greatGap: Double
  /// Brilliant: the move gives up at least this much material (pawn = 1)...
  public let brilliantMaterial: Int
  /// ...loses less than `excellentLoss`, and leaves the mover at least this win probability.
  public let brilliantMinWinProbability: Double
  /// Miss: after an opponent mistake or blunder, the best move gave at least this much...
  public let missMinBestWinProbability: Double
  /// ...and the played move lost at least `inaccuracyLoss` without dropping below this.
  public let missMinWinProbabilityAfter: Double
  /// Engine time per position; the Apple TV HD's A8 needs short searches.
  let analysisMilliseconds: Int

  public var analysisTime: Duration { .milliseconds(analysisMilliseconds) }
}

/// `opening-book.json`: common opening lines, used to mark early moves as "Book".
public struct OpeningBook: Codable, Hashable, Sendable {
  /// Main lines in SAN, space separated, without check marks.
  public let lines: [String]
}
