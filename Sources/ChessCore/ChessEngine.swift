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
    /// `nil` when the side to move has no legal move (checkmate or stalemate).
    public let bestMove: ChessMove?
    /// Expected line starting with `bestMove`.
    public let principalVariation: [ChessMove]
    /// Last fully completed iteration depth (0 when there is no legal move).
    public let depth: Int
    /// Second-best root move and its score from White's point of view; `nil` with a single legal move.
    public let secondBestMove: ChessMove?
    public let secondBestEvaluation: Evaluation?
    public let nodes: Int
}

/// Playing strength on an Elo-like scale from 250 to 2200. All search settings derive from `elo`.
public struct EngineStrength: Codable, Hashable, Sendable {
    public static let minimumElo = 250
    public static let maximumElo = 2200

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

    private func interpolate(_ values: [Double]) -> Double {
        let anchors = Self.anchors
        guard let upper = anchors.firstIndex(where: { $0 >= elo }), upper > 0 else { return values[0] }
        let fraction = Double(elo - anchors[upper - 1]) / Double(anchors[upper] - anchors[upper - 1])
        return values[upper - 1] + (values[upper] - values[upper - 1]) * fraction
    }

    /// Maximum nominal search depth in plies.
    public var searchDepth: Int { Int(interpolate(Self.depths).rounded()) }
    /// Time budget for one move; the search stops earlier when it reaches `searchDepth`.
    public var thinkTime: Duration { .milliseconds(Int(interpolate(Self.thinkMilliseconds))) }
    /// Scale of the random centipawn noise added to candidate move scores.
    public var evaluationNoise: Int { Int(interpolate(Self.noises).rounded()) }
    /// Probability of choosing among candidates by a score-weighted draw instead of the best noisy score.
    public var mistakeChance: Double { interpolate(Self.mistakes) }
    /// Softmax temperature, in centipawns, of that weighted draw; higher picks worse moves more often.
    public var mistakeTemperature: Int { Int(interpolate(Self.temperatures).rounded()) }
    /// Root moves that receive exact scores and can be chosen (MultiPV width).
    public var candidateMoves: Int { elo < 1400 ? 256 : (elo < 2000 ? 4 : 1) }
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
    /// `ChessEngineError.noLegalMove` when the game is already over.
    public func bestMove(game: ChessGame, strength: EngineStrength) async throws -> ChessMove {
        try Task.checkCancellation()
        let board = EngineBoard(game.position, history: game.moves.map(\.positionBefore))
        var searcher = EngineSearcher(board: board, table: table)
        let result = searcher.search(maxDepth: strength.searchDepth, timeLimit: strength.thinkTime, multiPV: strength.candidateMoves)
        searcher.deallocate()
        if result.cancelled { throw CancellationError() }
        guard !result.lines.isEmpty else { throw ChessEngineError.noLegalMove }
        var generator = SystemRandomNumberGenerator()
        return Self.choose(from: result.lines, strength: strength, using: &generator).chessMove
    }

    /// Searches `position` and reports the best line and the runner-up score (MultiPV 2).
    /// `history` holds the earlier positions of the game, oldest first; repeats count as draws.
    public func analyze(position: ChessPosition, history: [ChessPosition] = [], limit: SearchLimit) async throws -> EngineAnalysis {
        try Task.checkCancellation()
        let whiteToMove = position.sideToMove == .white
        var searcher = EngineSearcher(board: EngineBoard(position, history: history), table: table)
        let time = limit.time ?? (limit.depth == nil ? .seconds(1) : nil)
        let result = searcher.search(maxDepth: limit.depth ?? EngineSearcher.maxPly, timeLimit: time, multiPV: 2)
        searcher.deallocate()
        if result.cancelled { throw CancellationError() }

        guard let best = result.lines.first else {
            let evaluation = result.inCheck
                ? Evaluation(centipawns: whiteToMove ? -20_000 : 20_000, mateIn: 0)
                : Evaluation(centipawns: 0)
            return EngineAnalysis(evaluation: evaluation, bestMove: nil, principalVariation: [], depth: 0,
                                  secondBestMove: nil, secondBestEvaluation: nil, nodes: result.nodes)
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

    /// Picks the move to play from scored root lines. Strong settings play the best move;
    /// weaker settings add noise to candidate scores and sometimes draw a candidate with
    /// probability weighted by its score.
    static func choose<Generator: RandomNumberGenerator>(from lines: [RootLine], strength: EngineStrength,
                                                         using generator: inout Generator) -> EngineMove {
        let candidates = lines.filter(\.exact)
        guard candidates.count > 1, strength.evaluationNoise > 0 || strength.mistakeChance > 0 else { return lines[0].move }
        // Clamp mate scores so a mate still dominates without overflowing the weights.
        let scores = candidates.map { Double(min(max($0.score, -2_000), 2_000)) }

        if Double.random(in: 0..<1, using: &generator) < strength.mistakeChance {
            let top = scores.max() ?? 0
            let temperature = Double(max(strength.mistakeTemperature, 1))
            let weights = scores.map { exp(($0 - top) / temperature) }
            var draw = Double.random(in: 0..<weights.reduce(0, +), using: &generator)
            for (index, weight) in weights.enumerated() {
                draw -= weight
                if draw < 0 { return candidates[index].move }
            }
            return candidates[0].move
        }

        let noise = Double(strength.evaluationNoise)
        var bestIndex = 0
        var bestScore = -Double.infinity
        for (index, score) in scores.enumerated() {
            // The sum of three uniform draws approximates a bell curve with standard deviation `noise`.
            let jitter = (0..<3).reduce(0.0) { sum, _ in sum + Double.random(in: -1...1, using: &generator) } * noise
            if score + jitter > bestScore {
                bestScore = score + jitter
                bestIndex = index
            }
        }
        return candidates[bestIndex].move
    }
}
