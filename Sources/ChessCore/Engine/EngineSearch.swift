import Foundation

struct TranspositionEntry {
  var key: UInt64 = 0
  var move: EngineMove = 0
  var score: Int16 = 0
  var depth: Int8 = 0
  /// Low 2 bits: bound (see `Bound`); high 6 bits: search generation.
  var info: UInt8 = 0
}

/// Fixed-size, single-slot-per-bucket hash table shared by successive searches of one engine.
final class TranspositionTable {
  let entries: UnsafeMutablePointer<TranspositionEntry>
  let mask: Int
  private(set) var generation: UInt8 = 0

  private static let bytesPerMegabyte = 1_048_576
  /// Generations fit the 6 high bits of `TranspositionEntry.info`.
  private static let generationMask: UInt8 = 63

  init(megabytes: Int) {
    let wanted = max(1, megabytes) * Self.bytesPerMegabyte / MemoryLayout<TranspositionEntry>.stride
    var count = 1
    while count * 2 <= wanted { count *= 2 }
    entries = .allocate(capacity: count)
    entries.initialize(repeating: TranspositionEntry(), count: count)
    mask = count - 1
  }

  deinit { entries.deallocate() }

  func startSearch() { generation = (generation &+ 1) & Self.generationMask }
}

/// One root move with its latest score (side to move's point of view).
struct RootLine {
  var move: EngineMove
  var score: Int
  /// `false` when the score is only an upper bound (the move was proven worse than the
  /// moves ranked ahead of it).
  var exact: Bool
  var pv: [EngineMove]
}

struct SearchResult {
  /// Root moves, best first. Empty when the side to move has no legal move.
  var lines: [RootLine]
  var depth: Int
  var nodes: Int
  var cancelled: Bool
  var inCheck: Bool
}

/// Alpha-beta searcher over an `EngineBoard`: iterative deepening, PVS, transposition table,
/// null-move pruning, late-move reductions, futility pruning, check extension and quiescence.
struct EngineSearcher: ~Copyable {
  static let maxPly = 96
  static let infinity = 32_000
  /// Score of a side mated at the root; a mate at ply `n` scores `mate - n`.
  static let mate = 31_000
  static let mateBound = mate - maxPly
  /// Iterative deepening stops this many plies short of `maxPly` to leave room for extensions.
  private static let maxRootDepth = maxPly - 8
  /// Nodes at this ply return a static score so children stay inside the per-ply buffers.
  private static let horizonPly = maxPly - 2
  /// Time and cancellation are polled once per 1024 nodes.
  private static let limitCheckMask = 1023
  private static let fiftyMoveHalfmoves = 100

  private enum Bound {
    static let exact: UInt8 = 1
    static let lower: UInt8 = 2
    static let upper: UInt8 = 3
    /// `TranspositionEntry.info` keeps the bound in its low 2 bits and the generation above.
    static let mask: UInt8 = 3
    static let generationShift: UInt8 = 2
  }

  /// A deeper entry from the current search survives unless the new result is at most this
  /// many plies shallower.
  private static let tableReplaceDepthSlack = 2

  /// Move-ordering scores, from first searched to last. Butterfly scores stay below
  /// `butterflyCap`, so every quiet move without a killer slot sorts below `secondKiller`;
  /// late-move reductions rely on that to reduce only those moves.
  private enum Ordering {
    static let tableMove: Int32 = 2_000_000
    static let capture: Int32 = 1_000_000
    /// Captures are ranked most valuable victim first, then least valuable attacker.
    static let victimWeight = 16
    static let queenPromotion: Int32 = 900_000
    static let firstKiller: Int32 = 800_000
    static let secondKiller: Int32 = 790_000
    static let butterflyCap: Int32 = 700_000
    static let underpromotionPenalty: Int32 = 500_000
  }

  /// Butterfly table: one score per side, from-square and to-square (0x88 squares).
  private enum Butterfly {
    static let squareCount = 128
    static let sideStride = squareCount * squareCount
    static let size = 2 * sideStride
  }

  private enum ReverseFutility {
    static let maxDepth = 3
    static let marginPerDepth = 110
  }

  private enum NullMove {
    static let minDepth = 3
    static let deepDepth = 7
    static let reduction = 2
    static let deepReduction = 3
  }

  private enum Futility {
    static let maxDepth = 2
    static let marginPerDepth = 120
    static let baseMargin = 60
  }

  private enum LateMoveReduction {
    static let minDepth = 3
    /// The first moves in order are searched at full depth.
    static let fullDepthMoves = 3
    /// Moves after this many get the larger reduction.
    static let deeperReductionAfter = 10
    static let reduction = 1
    static let deeperReduction = 2
    /// Non-PV nodes at least this deep reduce one more ply.
    static let extraReductionDepth = 8
    /// A reduced search keeps at least this much depth below the node.
    static let minRemainingDepth = 2
  }

  /// Quiescence skips a capture whose victim plus this margin cannot reach alpha.
  private static let deltaMargin = 200
  /// A found mate ends deepening once depth passes its distance by this many plies.
  private static let mateDepthSlack = 2
  /// An iteration that took over half the time budget would not finish another.
  private static let iterationTimeDivisor = 2

  var board: EngineBoard
  private let table: TranspositionTable
  private let entries: UnsafeMutablePointer<TranspositionEntry>
  private let tableMask: Int
  private var generation: UInt8 = 0
  private let killers: UnsafeMutablePointer<EngineMove>
  private let butterflyScores: UnsafeMutablePointer<Int32>
  private let moveLists: UnsafeMutablePointer<EngineMove>
  private let moveScores: UnsafeMutablePointer<Int32>
  private let pvTable: UnsafeMutablePointer<EngineMove>
  private let pvLength: UnsafeMutablePointer<Int>

  private(set) var nodes = 0
  private var stopped = false
  private var cancelled = false
  private var canStopOnTime = false
  private var deadline: ContinuousClock.Instant?

  init(board: consuming EngineBoard, table: TranspositionTable) {
    // The search and `extendedPV` (with its `legalMoves()` probe) make fewer than `maxPly` moves.
    precondition(
      board.plyCapacity - board.undoCount >= Self.maxPly,
      "board too small for a search"
    )
    self.board = board
    self.table = table
    entries = table.entries
    tableMask = table.mask
    killers = .allocate(capacity: Self.maxPly * 2)
    killers.initialize(repeating: 0, count: Self.maxPly * 2)
    butterflyScores = .allocate(capacity: Butterfly.size)
    butterflyScores.initialize(repeating: 0, count: Butterfly.size)
    moveLists = .allocate(capacity: Self.maxPly * EngineBoard.moveListCapacity)
    moveScores = .allocate(capacity: Self.maxPly * EngineBoard.moveListCapacity)
    pvTable = .allocate(capacity: Self.maxPly * Self.maxPly)
    pvLength = .allocate(capacity: Self.maxPly + 1)
    pvLength.initialize(repeating: 0, count: Self.maxPly + 1)
  }

  deinit {
    killers.deallocate()
    butterflyScores.deallocate()
    moveLists.deallocate()
    moveScores.deallocate()
    pvTable.deallocate()
    pvLength.deallocate()
  }

  // MARK: - Iterative deepening

  /// Searches the root until `maxDepth` is reached, the time budget runs out or the task is
  /// cancelled. `multiPV` root moves get exact scores; the rest only get upper bounds.
  /// Depth 1 always completes unless the task is cancelled.
  mutating func search(maxDepth: Int, timeLimit: Duration?, multiPV: Int) -> SearchResult {
    table.startSearch()
    generation = table.generation
    let start = ContinuousClock.now
    deadline = timeLimit.map { start.advanced(by: $0) }
    let inCheck = board.inCheck
    let lines = orderedRootMoves().map {
      RootLine(move: $0, score: -Self.infinity, exact: false, pv: [$0])
    }
    var result = SearchResult(lines: lines, depth: 0, nodes: 0, cancelled: false, inCheck: inCheck)
    guard !lines.isEmpty else { return result }
    let wanted = min(max(1, multiPV), lines.count)

    for depth in 1...max(1, min(maxDepth, Self.maxRootDepth)) {
      canStopOnTime = depth > 1
      guard let ranked = searchIteration(result.lines, depth: depth, wanted: wanted) else { break }
      result.lines = ranked
      result.depth = depth
      if Self.mateWithinDepth(ranked[0].score, depth: depth) { break }
      if let timeLimit, ContinuousClock.now - start > timeLimit / Self.iterationTimeDivisor {
        break
      }
    }
    for index in result.lines.indices where result.lines[index].exact {
      result.lines[index].pv = extendedPV(result.lines[index].pv, maxLength: max(result.depth, 1))
    }
    result.nodes = nodes
    result.cancelled = cancelled
    return result
  }

  /// Searches every root move to `depth`; `nil` when the search stopped part way.
  private mutating func searchIteration(
    _ lines: [RootLine],
    depth: Int,
    wanted: Int
  ) -> [RootLine]? {
    var exactScores: [Int] = []
    var iteration = lines
    for index in iteration.indices {
      let threshold = exactScores.count >= wanted ? exactScores[wanted - 1] : -Self.infinity
      let move = iteration[index].move
      guard let searched = searchRootMove(move, depth: depth, threshold: threshold) else {
        return nil
      }
      let score = searched.score
      let exact = score > threshold
      iteration[index].score = score
      iteration[index].exact = exact
      if exact {
        iteration[index].pv = [move] + searched.childPV
        exactScores.append(score)
        exactScores.sort(by: >)
      }
    }
    // Exact scores first (best first), then bounded moves; ties keep the previous order.
    return iteration.enumerated().sorted { lhs, rhs in
      if lhs.element.exact != rhs.element.exact { return lhs.element.exact }
      if lhs.element.score != rhs.element.score { return lhs.element.score > rhs.element.score }
      return lhs.offset < rhs.offset
    }.map(\.element)
  }

  /// Scores one root move; a null window at `threshold` only proves whether it beats the
  /// moves already holding an exact score. `nil` when the search stopped.
  private mutating func searchRootMove(
    _ move: EngineMove,
    depth: Int,
    threshold: Int
  ) -> (score: Int, childPV: [EngineMove])? {
    board.make(move)
    var score: Int
    if threshold == -Self.infinity {
      score = -negamax(depth - 1, ply: 1, alpha: -Self.infinity, beta: Self.infinity)
    } else {
      score = -negamax(depth - 1, ply: 1, alpha: -threshold - 1, beta: -threshold)
      if !stopped && score > threshold {
        score = -negamax(depth - 1, ply: 1, alpha: -Self.infinity, beta: -threshold)
      }
    }
    let childPV = Array(
      UnsafeBufferPointer(start: pvTable + Self.maxPly + 1, count: max(0, pvLength[1] - 1))
    )
    board.unmake()
    return stopped ? nil : (score, childPV)
  }

  private static func mateWithinDepth(_ score: Int, depth: Int) -> Bool {
    abs(score) >= mateBound && depth > mate - abs(score) + mateDepthSlack
  }

  private mutating func orderedRootMoves() -> [EngineMove] {
    let moves = board.legalMoves()
    let slot = entries + (Int(truncatingIfNeeded: board.hash) & tableMask)
    let ttMove = slot.pointee.key == board.hash ? slot.pointee.move : 0
    return moves.enumerated().sorted { lhs, rhs in
      let left = orderScore(lhs.element, ttMove: ttMove, ply: 0)
      let right = orderScore(rhs.element, ttMove: ttMove, ply: 0)
      return left != right ? left > right : lhs.offset < rhs.offset
    }.map(\.element)
  }

  /// Continues a PV with transposition-table moves so analysis lines are not cut short
  /// by table cutoffs.
  private mutating func extendedPV(_ pv: [EngineMove], maxLength: Int) -> [EngineMove] {
    var line: [EngineMove] = []
    for move in pv {
      guard board.legalMoves().contains(move) else { break }
      board.make(move)
      line.append(move)
    }
    while line.count < maxLength, !board.isRepetition {
      let slot = entries + (Int(truncatingIfNeeded: board.hash) & tableMask)
      guard slot.pointee.key == board.hash, slot.pointee.move != 0,
        board.legalMoves().contains(slot.pointee.move)
      else { break }
      board.make(slot.pointee.move)
      line.append(slot.pointee.move)
    }
    for _ in line { board.unmake() }
    return line
  }

  // MARK: - Alpha-beta

  private mutating func checkLimits() {
    if Task.isCancelled {
      stopped = true
      cancelled = true
    } else if canStopOnTime, let deadline, ContinuousClock.now >= deadline {
      stopped = true
    }
  }

  /// Counts a node, polls the limits now and then, and tells whether the search stopped.
  @inline(__always)
  private mutating func enterNode() -> Bool {
    nodes += 1
    if nodes & Self.limitCheckMask == 0 { checkLimits() }
    return stopped
  }

  private var isDrawByRule: Bool {
    board.halfmove >= Self.fiftyMoveHalfmoves || board.isRepetition
      || board.hasInsufficientMaterial
  }

  private mutating func negamax(
    _ requestedDepth: Int,
    ply: Int,
    alpha alphaIn: Int,
    beta betaIn: Int,
    allowNull: Bool = true
  ) -> Int {
    pvLength[ply] = ply
    if isDrawByRule { return 0 }
    let alpha = max(alphaIn, -Self.mate + ply)
    let beta = min(betaIn, Self.mate - ply - 1)
    if alpha >= beta { return alpha }

    let inCheck = board.inCheck
    let depth = inCheck ? requestedDepth + 1 : requestedDepth
    if depth <= 0 { return quiescence(ply: ply, alpha: alpha, beta: beta) }
    if enterNode() { return 0 }
    if ply >= Self.horizonPly { return board.evaluate() }

    let node = Node(
      depth: depth,
      ply: ply,
      pvNode: beta - alpha > 1,
      inCheck: inCheck,
      slot: entries + (Int(truncatingIfNeeded: board.hash) & tableMask)
    )
    var ttMove: EngineMove = 0
    if let score = probeTable(node, alpha: alpha, beta: beta, ttMove: &ttMove) { return score }
    var staticEval = Self.infinity
    if let score = tryPrune(node, beta: beta, allowNull: allowNull, staticEval: &staticEval) {
      return score
    }
    let futile = Self.isFutile(staticEval, depth: depth, alpha: alpha)
    return searchMoves(node, alpha: alpha, beta: beta, ttMove: ttMove, futile: futile)
  }

  /// What the phases of one `negamax` node share.
  private struct Node {
    let depth: Int
    let ply: Int
    let pvNode: Bool
    let inCheck: Bool
    let slot: UnsafeMutablePointer<TranspositionEntry>
  }

  /// Returns the stored score when the table entry decides this node, and hands back the
  /// stored move for ordering either way.
  @inline(__always)
  private func probeTable(
    _ node: Node,
    alpha: Int,
    beta: Int,
    ttMove: inout EngineMove
  ) -> Int? {
    guard node.slot.pointee.key == board.hash else { return nil }
    let entry = node.slot.pointee
    ttMove = entry.move
    guard !node.pvNode && Int(entry.depth) >= node.depth else { return nil }
    let score = Self.scoreFromTable(Int(entry.score), ply: node.ply)
    switch entry.info & Bound.mask {
    case Bound.exact: return score
    case Bound.lower where score >= beta: return score
    case Bound.upper where score <= alpha: return score
    default: return nil
    }
  }

  /// Prunes a quiet non-PV node from its static score before any move is searched. Sets
  /// `staticEval` when it evaluates the node.
  @inline(__always)
  private mutating func tryPrune(
    _ node: Node,
    beta: Int,
    allowNull: Bool,
    staticEval: inout Int
  ) -> Int? {
    guard !node.pvNode && !node.inCheck else { return nil }
    staticEval = board.evaluate()
    if let score = tryStaticPrune(staticEval, depth: node.depth, beta: beta) { return score }
    return allowNull ? tryNullMove(staticEval, node, beta: beta) : nil
  }

  /// Reverse futility: far above beta near the leaves.
  @inline(__always)
  private func tryStaticPrune(_ staticEval: Int, depth: Int, beta: Int) -> Int? {
    guard depth <= ReverseFutility.maxDepth && abs(beta) < Self.mateBound else { return nil }
    let score = staticEval - ReverseFutility.marginPerDepth * depth
    return score >= beta ? score : nil
  }

  /// Null move: if passing still fails high, a real move will too.
  @inline(__always)
  private mutating func tryNullMove(_ staticEval: Int, _ node: Node, beta: Int) -> Int? {
    guard
      node.depth >= NullMove.minDepth && staticEval >= beta
        && board.hasNonPawnMaterial(board.side)
    else { return nil }
    let reduction = node.depth >= NullMove.deepDepth ? NullMove.deepReduction : NullMove.reduction
    board.makeNull()
    let score = -negamax(
      node.depth - 1 - reduction,
      ply: node.ply + 1,
      alpha: -beta,
      beta: -beta + 1,
      allowNull: false
    )
    board.unmakeNull()
    if stopped { return 0 }
    guard score >= beta else { return nil }
    return score >= Self.mateBound ? beta : score
  }

  /// Futility: quiet moves cannot lift a static score this far below alpha.
  @inline(__always)
  private static func isFutile(_ staticEval: Int, depth: Int, alpha: Int) -> Bool {
    depth <= Futility.maxDepth && staticEval != infinity && abs(alpha) < mateBound
      && staticEval + Futility.marginPerDepth * depth + Futility.baseMargin <= alpha
  }

  @inline(__always)
  private mutating func searchMoves(
    _ node: Node,
    alpha alphaIn: Int,
    beta: Int,
    ttMove: EngineMove,
    futile: Bool
  ) -> Int {
    let (list, scores, count) = orderedMoves(ply: node.ply, ttMove: ttMove, capturesOnly: false)
    var alpha = alphaIn
    var best = -Self.infinity
    var bestMove: EngineMove = 0
    var legal = 0
    for index in 0..<count {
      let move = Self.pickNext(list, scores, from: index, count: count)
      guard board.make(move) else { continue }
      legal += 1
      let givesCheck = board.inCheck
      if Self.isFutileMove(move, futile: futile, legal: legal, givesCheck: givesCheck) {
        board.unmake()
        continue
      }
      let reduction = Self.lateMoveReduction(node, move, legal, givesCheck, scores[index])
      let score = searchChild(node, legal: legal, reduction: reduction, alpha: alpha, beta: beta)
      board.unmake()
      if stopped { return 0 }
      guard score > best else { continue }
      best = score
      bestMove = move
      guard score > alpha else { continue }
      alpha = score
      updatePV(ply: node.ply, move: move)
      guard score < beta else {
        if move.isQuiet { recordCutoff(move, ply: node.ply, depth: node.depth) }
        break
      }
    }
    guard legal > 0 else { return Self.scoreWithoutMoves(node) }
    storeTable(node, best: best, bestMove: bestMove, alpha: alphaIn, beta: beta)
    return best
  }

  /// Checkmate scores the distance from the root; stalemate is a draw.
  @inline(__always)
  private static func scoreWithoutMoves(_ node: Node) -> Int {
    node.inCheck ? -mate + node.ply : 0
  }

  /// Futility: at a futile node, quiet moves after the first that give no check are skipped.
  @inline(__always)
  private static func isFutileMove(
    _ move: EngineMove,
    futile: Bool,
    legal: Int,
    givesCheck: Bool
  ) -> Bool {
    futile && legal > 1 && move.isQuiet && !givesCheck
  }

  /// Principal variation search: the first move gets the full window, later moves a null
  /// window (reduced first if `reduction > 0`) and a re-search only when they beat alpha.
  @inline(__always)
  private mutating func searchChild(
    _ node: Node,
    legal: Int,
    reduction: Int,
    alpha: Int,
    beta: Int
  ) -> Int {
    let depth = node.depth
    let ply = node.ply + 1
    if legal == 1 { return -negamax(depth - 1, ply: ply, alpha: -beta, beta: -alpha) }
    var score = -negamax(depth - 1 - reduction, ply: ply, alpha: -alpha - 1, beta: -alpha)
    if !stopped && score > alpha && reduction > 0 {
      score = -negamax(depth - 1, ply: ply, alpha: -alpha - 1, beta: -alpha)
    }
    if !stopped && score > alpha && score < beta {
      score = -negamax(depth - 1, ply: ply, alpha: -beta, beta: -alpha)
    }
    return score
  }

  /// Plies to cut from a late quiet move. Only moves ordered below the killers qualify, which
  /// `Ordering` guarantees for every quiet move ranked by its butterfly score.
  @inline(__always)
  private static func lateMoveReduction(
    _ node: Node,
    _ move: EngineMove,
    _ legal: Int,
    _ givesCheck: Bool,
    _ orderScore: Int32
  ) -> Int {
    guard
      node.depth >= LateMoveReduction.minDepth && legal > LateMoveReduction.fullDepthMoves
        && move.isQuiet && !node.inCheck && !givesCheck && orderScore < Ordering.secondKiller
    else { return 0 }
    var reduction =
      legal > LateMoveReduction.deeperReductionAfter
      ? LateMoveReduction.deeperReduction : LateMoveReduction.reduction
    if node.depth >= LateMoveReduction.extraReductionDepth && !node.pvNode { reduction += 1 }
    return min(reduction, node.depth - LateMoveReduction.minRemainingDepth)
  }

  @inline(__always)
  private func storeTable(
    _ node: Node,
    best: Int,
    bestMove: EngineMove,
    alpha: Int,
    beta: Int
  ) {
    let bound = best >= beta ? Bound.lower : (best > alpha ? Bound.exact : Bound.upper)
    let existing = node.slot.pointee
    guard
      existing.key == board.hash || existing.info >> Bound.generationShift != generation
        || Int(existing.depth) <= node.depth + Self.tableReplaceDepthSlack
    else { return }
    node.slot.pointee = TranspositionEntry(
      key: board.hash,
      move: bestMove != 0 ? bestMove : existing.move,
      score: Int16(Self.scoreToTable(best, ply: node.ply)),
      depth: Int8(clamping: node.depth),
      info: bound | generation << Bound.generationShift
    )
  }

  private mutating func quiescence(ply: Int, alpha alphaIn: Int, beta: Int) -> Int {
    pvLength[ply] = ply
    if enterNode() { return 0 }
    let standPat = board.evaluate()
    if ply >= Self.horizonPly || standPat >= beta { return standPat }
    var alpha = max(alphaIn, standPat)
    var best = standPat

    let (list, scores, count) = orderedMoves(ply: ply, ttMove: 0, capturesOnly: true)
    for index in 0..<count {
      let move = Self.pickNext(list, scores, from: index, count: count)
      if isDeltaPruned(move, standPat: standPat, alpha: alpha) { continue }
      guard board.make(move) else { continue }
      let score = -quiescence(ply: ply + 1, alpha: -beta, beta: -alpha)
      board.unmake()
      if stopped { return 0 }
      best = max(best, score)
      guard score > alpha else { continue }
      alpha = score
      if score >= beta { break }
    }
    return best
  }

  /// Delta pruning: even winning the victim cannot lift the score to alpha.
  @inline(__always)
  private func isDeltaPruned(_ move: EngineMove, standPat: Int, alpha: Int) -> Bool {
    move.promotion == 0
      && standPat + EngineEvaluation.endgameValue[capturedKind(move)] + Self.deltaMargin <= alpha
  }

  // MARK: - Move ordering

  /// Generates the moves of `ply` into its buffer and scores them for `pickNext`.
  @inline(__always)
  private func orderedMoves(
    ply: Int,
    ttMove: EngineMove,
    capturesOnly: Bool
  ) -> (UnsafeMutablePointer<EngineMove>, UnsafeMutablePointer<Int32>, Int) {
    let list = moveLists + ply * EngineBoard.moveListCapacity
    let scores = moveScores + ply * EngineBoard.moveListCapacity
    let count = board.generateMoves(into: list, capturesOnly: capturesOnly)
    for index in 0..<count {
      scores[index] = orderScore(list[index], ttMove: ttMove, ply: ply)
    }
    return (list, scores, count)
  }

  @inline(__always)
  private func capturedKind(_ move: EngineMove) -> Int {
    move.flag == MoveFlag.enPassant ? EngineKind.pawn : board.squares[move.to] & EngineKind.mask
  }

  private func orderScore(_ move: EngineMove, ttMove: EngineMove, ply: Int) -> Int32 {
    if move == ttMove { return Ordering.tableMove }
    var score: Int32 = 0
    if move.isCapture {
      let attacker = board.squares[move.from] & EngineKind.mask
      score = Ordering.capture + Int32(capturedKind(move) * Ordering.victimWeight - attacker)
    }
    switch move.promotion {
    case 0: break
    case EngineKind.queen: score += Ordering.queenPromotion
    default: return score - Ordering.underpromotionPenalty
    }
    if score != 0 { return score }
    if move == killers[ply * 2] { return Ordering.firstKiller }
    if move == killers[ply * 2 + 1] { return Ordering.secondKiller }
    return butterflyScores[butterflyIndex(move)]
  }

  @inline(__always)
  private func butterflyIndex(_ move: EngineMove) -> Int {
    board.side * Butterfly.sideStride + move.from * Butterfly.squareCount + move.to
  }

  /// Swaps the best-scored remaining move into `start` and returns it.
  @inline(__always)
  private static func pickNext(
    _ list: UnsafeMutablePointer<EngineMove>,
    _ scores: UnsafeMutablePointer<Int32>,
    from start: Int,
    count: Int
  ) -> EngineMove {
    var bestIndex = start
    var index = start + 1
    while index < count {
      if scores[index] > scores[bestIndex] { bestIndex = index }
      index += 1
    }
    if bestIndex != start {
      (list[start], list[bestIndex]) = (list[bestIndex], list[start])
      (scores[start], scores[bestIndex]) = (scores[bestIndex], scores[start])
    }
    return list[start]
  }

  private mutating func recordCutoff(_ move: EngineMove, ply: Int, depth: Int) {
    if killers[ply * 2] != move {
      killers[ply * 2 + 1] = killers[ply * 2]
      killers[ply * 2] = move
    }
    let index = butterflyIndex(move)
    butterflyScores[index] = min(
      butterflyScores[index] + Int32(depth * depth),
      Ordering.butterflyCap
    )
  }

  private func updatePV(ply: Int, move: EngineMove) {
    let row = pvTable + ply * Self.maxPly
    row[ply] = move
    let childLength = pvLength[ply + 1]
    var index = ply + 1
    while index < childLength {
      row[index] = pvTable[(ply + 1) * Self.maxPly + index]
      index += 1
    }
    pvLength[ply] = max(childLength, ply + 1)
  }

  // MARK: - Mate score storage

  private static func scoreToTable(_ score: Int, ply: Int) -> Int {
    if score >= mateBound { return score + ply }
    if score <= -mateBound { return score - ply }
    return score
  }

  private static func scoreFromTable(_ score: Int, ply: Int) -> Int {
    if score >= mateBound { return score - ply }
    if score <= -mateBound { return score + ply }
    return score
  }
}
