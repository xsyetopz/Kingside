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

  init(megabytes: Int) {
    let wanted = max(1, megabytes) * 1_048_576 / MemoryLayout<TranspositionEntry>.stride
    var count = 1
    while count * 2 <= wanted { count *= 2 }
    entries = .allocate(capacity: count)
    entries.initialize(repeating: TranspositionEntry(), count: count)
    mask = count - 1
  }

  deinit { entries.deallocate() }

  func startSearch() { generation = (generation &+ 1) & 63 }
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
  static let mate = 31_000
  static let mateBound = mate - maxPly

  private enum Bound {
    static let exact: UInt8 = 1
    static let lower: UInt8 = 2
    static let upper: UInt8 = 3
  }

  var board: EngineBoard
  private let table: TranspositionTable
  private let entries: UnsafeMutablePointer<TranspositionEntry>
  private let tableMask: Int
  private var generation: UInt8 = 0
  private let killers: UnsafeMutablePointer<EngineMove>
  private let history: UnsafeMutablePointer<Int32>
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
    history = .allocate(capacity: 2 * 128 * 128)
    history.initialize(repeating: 0, count: 2 * 128 * 128)
    moveLists = .allocate(capacity: Self.maxPly * 256)
    moveScores = .allocate(capacity: Self.maxPly * 256)
    pvTable = .allocate(capacity: Self.maxPly * Self.maxPly)
    pvLength = .allocate(capacity: Self.maxPly + 1)
    pvLength.initialize(repeating: 0, count: Self.maxPly + 1)
  }

  deinit {
    killers.deallocate()
    history.deallocate()
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
    var lines = orderedRootMoves().map {
      RootLine(move: $0, score: -Self.infinity, exact: false, pv: [$0])
    }
    var result = SearchResult(lines: lines, depth: 0, nodes: 0, cancelled: false, inCheck: inCheck)
    guard !lines.isEmpty else { return result }
    let wanted = min(max(1, multiPV), lines.count)

    for depth in 1...max(1, min(maxDepth, Self.maxPly - 8)) {
      canStopOnTime = depth > 1
      var exactScores: [Int] = []
      var iteration = lines
      for index in iteration.indices {
        let threshold = exactScores.count >= wanted ? exactScores[wanted - 1] : -Self.infinity
        let move = iteration[index].move
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
        if stopped { break }
        let exact = score > threshold
        iteration[index].score = score
        iteration[index].exact = exact
        if exact {
          iteration[index].pv = [move] + childPV
          exactScores.append(score)
          exactScores.sort(by: >)
        }
      }
      if stopped { break }

      // Exact scores first (best first), then bounded moves; ties keep the previous order.
      iteration = iteration.enumerated().sorted { lhs, rhs in
        if lhs.element.exact != rhs.element.exact { return lhs.element.exact }
        if lhs.element.score != rhs.element.score { return lhs.element.score > rhs.element.score }
        return lhs.offset < rhs.offset
      }.map(\.element)
      lines = iteration
      result.lines = lines
      result.depth = depth

      let best = lines[0].score
      if abs(best) >= Self.mateBound && depth > Self.mate - abs(best) + 2 { break }
      if let timeLimit, ContinuousClock.now - start > timeLimit / 2 { break }
    }
    for index in result.lines.indices where result.lines[index].exact {
      result.lines[index].pv = extendedPV(result.lines[index].pv, maxLength: max(result.depth, 1))
    }
    result.nodes = nodes
    result.cancelled = cancelled
    return result
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

  private mutating func negamax(
    _ requestedDepth: Int,
    ply: Int,
    alpha alphaIn: Int,
    beta betaIn: Int,
    allowNull: Bool = true
  ) -> Int {
    pvLength[ply] = ply
    if board.halfmove >= 100 || board.isRepetition || board.hasInsufficientMaterial { return 0 }
    var alpha = max(alphaIn, -Self.mate + ply)
    let beta = min(betaIn, Self.mate - ply - 1)
    if alpha >= beta { return alpha }

    let inCheck = board.inCheck
    let depth = inCheck ? requestedDepth + 1 : requestedDepth
    if depth <= 0 { return quiescence(ply: ply, alpha: alpha, beta: beta) }

    nodes += 1
    if nodes & 1023 == 0 { checkLimits() }
    if stopped { return 0 }
    if ply >= Self.maxPly - 2 { return board.evaluate() }

    let pvNode = beta - alpha > 1
    let slot = entries + (Int(truncatingIfNeeded: board.hash) & tableMask)
    var ttMove: EngineMove = 0
    if slot.pointee.key == board.hash {
      let entry = slot.pointee
      ttMove = entry.move
      if !pvNode && Int(entry.depth) >= depth {
        let score = Self.scoreFromTable(Int(entry.score), ply: ply)
        switch entry.info & 3 {
        case Bound.exact: return score
        case Bound.lower where score >= beta: return score
        case Bound.upper where score <= alpha: return score
        default: break
        }
      }
    }

    var staticEval = Self.infinity
    if !pvNode && !inCheck {
      staticEval = board.evaluate()
      // Reverse futility: far above beta near the leaves.
      if depth <= 3 && abs(beta) < Self.mateBound && staticEval - 110 * depth >= beta {
        return staticEval - 110 * depth
      }
      // Null move: if passing still fails high, a real move will too.
      if allowNull && depth >= 3 && staticEval >= beta && board.hasNonPawnMaterial(board.side) {
        let reduction = depth >= 7 ? 3 : 2
        board.makeNull()
        let score = -negamax(
          depth - 1 - reduction,
          ply: ply + 1,
          alpha: -beta,
          beta: -beta + 1,
          allowNull: false
        )
        board.unmakeNull()
        if stopped { return 0 }
        if score >= beta { return score >= Self.mateBound ? beta : score }
      }
    }
    let futile =
      depth <= 2 && staticEval != Self.infinity && abs(alpha) < Self.mateBound
      && staticEval + 120 * depth + 60 <= alpha

    let list = moveLists + ply * 256
    let scores = moveScores + ply * 256
    let count = board.generateMoves(into: list, capturesOnly: false)
    for index in 0..<count {
      scores[index] = orderScore(list[index], ttMove: ttMove, ply: ply)
    }

    let originalAlpha = alpha
    var best = -Self.infinity
    var bestMove: EngineMove = 0
    var legal = 0
    for index in 0..<count {
      Self.pickNext(list, scores, from: index, count: count)
      let move = list[index]
      guard board.make(move) else { continue }
      legal += 1
      let quiet = move.isQuiet
      let givesCheck = board.inCheck
      if futile && legal > 1 && quiet && !givesCheck {
        board.unmake()
        continue
      }
      var score: Int
      if legal == 1 {
        score = -negamax(depth - 1, ply: ply + 1, alpha: -beta, beta: -alpha)
      } else {
        var reduction = 0
        if depth >= 3 && legal > 3 && quiet && !inCheck && !givesCheck && scores[index] < 790_000 {
          reduction = legal > 10 ? 2 : 1
          if depth >= 8 && !pvNode { reduction += 1 }
          reduction = min(reduction, depth - 2)
        }
        score = -negamax(depth - 1 - reduction, ply: ply + 1, alpha: -alpha - 1, beta: -alpha)
        if !stopped && score > alpha && reduction > 0 {
          score = -negamax(depth - 1, ply: ply + 1, alpha: -alpha - 1, beta: -alpha)
        }
        if !stopped && score > alpha && score < beta {
          score = -negamax(depth - 1, ply: ply + 1, alpha: -beta, beta: -alpha)
        }
      }
      board.unmake()
      if stopped { return 0 }

      if score > best {
        best = score
        bestMove = move
        if score > alpha {
          alpha = score
          updatePV(ply: ply, move: move)
          if score >= beta {
            if quiet { recordCutoff(move, ply: ply, depth: depth) }
            break
          }
        }
      }
    }

    if legal == 0 { return inCheck ? -Self.mate + ply : 0 }

    let bound = best >= beta ? Bound.lower : (best > originalAlpha ? Bound.exact : Bound.upper)
    let existing = slot.pointee
    if existing.key == board.hash || existing.info >> 2 != generation
      || Int(existing.depth) <= depth + 2
    {
      slot.pointee = TranspositionEntry(
        key: board.hash,
        move: bestMove != 0 ? bestMove : existing.move,
        score: Int16(Self.scoreToTable(best, ply: ply)),
        depth: Int8(clamping: depth),
        info: bound | generation << 2
      )
    }
    return best
  }

  private mutating func quiescence(ply: Int, alpha alphaIn: Int, beta: Int) -> Int {
    pvLength[ply] = ply
    nodes += 1
    if nodes & 1023 == 0 { checkLimits() }
    if stopped { return 0 }
    let standPat = board.evaluate()
    if ply >= Self.maxPly - 2 || standPat >= beta { return standPat }
    var alpha = max(alphaIn, standPat)
    var best = standPat

    let list = moveLists + ply * 256
    let scores = moveScores + ply * 256
    let count = board.generateMoves(into: list, capturesOnly: true)
    for index in 0..<count {
      scores[index] = orderScore(list[index], ttMove: 0, ply: ply)
    }
    for index in 0..<count {
      Self.pickNext(list, scores, from: index, count: count)
      let move = list[index]
      if move.promotion == 0 {
        // Delta pruning: even winning the victim cannot lift the score to alpha.
        let victim = move.flag == MoveFlag.enPassant ? EngineKind.pawn : board.squares[move.to] & 7
        if standPat + EngineEvaluation.endgameValue[victim] + 200 <= alpha { continue }
      }
      guard board.make(move) else { continue }
      let score = -quiescence(ply: ply + 1, alpha: -beta, beta: -alpha)
      board.unmake()
      if stopped { return 0 }
      if score > best {
        best = score
        if score > alpha {
          alpha = score
          if score >= beta { break }
        }
      }
    }
    return best
  }

  // MARK: - Move ordering

  private func orderScore(_ move: EngineMove, ttMove: EngineMove, ply: Int) -> Int32 {
    if move == ttMove { return 2_000_000 }
    var score: Int32 = 0
    if move.isCapture {
      let victim = move.flag == MoveFlag.enPassant ? EngineKind.pawn : board.squares[move.to] & 7
      let attacker = board.squares[move.from] & 7
      score = 1_000_000 + Int32(victim * 16 - attacker)
    }
    switch move.promotion {
    case 0: break
    case EngineKind.queen: score += 900_000
    default: return score - 500_000
    }
    if score != 0 { return score }
    if move == killers[ply * 2] { return 800_000 }
    if move == killers[ply * 2 + 1] { return 790_000 }
    return history[board.side * 16384 + move.from * 128 + move.to]
  }

  @inline(__always)
  private static func pickNext(
    _ list: UnsafeMutablePointer<EngineMove>,
    _ scores: UnsafeMutablePointer<Int32>,
    from start: Int,
    count: Int
  ) {
    var bestIndex = start
    var index = start + 1
    while index < count {
      if scores[index] > scores[bestIndex] { bestIndex = index }
      index += 1
    }
    if bestIndex != start {
      list.swapAt(start, bestIndex)
      scores.swapAt(start, bestIndex)
    }
  }

  private mutating func recordCutoff(_ move: EngineMove, ply: Int, depth: Int) {
    if killers[ply * 2] != move {
      killers[ply * 2 + 1] = killers[ply * 2]
      killers[ply * 2] = move
    }
    let index = board.side * 16384 + move.from * 128 + move.to
    history[index] = min(history[index] + Int32(depth * depth), 700_000)
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

extension UnsafeMutablePointer {
  @inline(__always)
  func swapAt(_ i: Int, _ j: Int) {
    let temporary = self[i]
    self[i] = self[j]
    self[j] = temporary
  }
}
