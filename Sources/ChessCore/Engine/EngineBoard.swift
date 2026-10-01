import Foundation

// Internal fast board used by the search engine.
//
// Squares use the 0x88 layout (index = rank * 16 + file), so `square & 0x88 != 0` means
// "off the board". Pieces are small integers: kind 1...6 (pawn...king) plus 8 for black.
// Moves are packed into a `UInt32` (see `EngineMove`). All storage lives in manually
// managed buffers so that make/unmake and move generation never allocate.

enum EngineKind {
  static let pawn = 1
  static let knight = 2
  static let bishop = 3
  static let rook = 4
  static let queen = 5
  static let king = 6
  static let blackBit = 8
}

/// Packed move: bits 0-6 from, 7-13 to, 14-16 promotion kind, 17-18 flag, 19 capture.
typealias EngineMove = UInt32

enum MoveFlag {
  static let normal = 0
  static let doublePush = 1
  static let enPassant = 2
  static let castle = 3
}

extension EngineMove {
  @inline(__always)
  static func pack(
    _ from: Int,
    _ to: Int,
    flag: Int = MoveFlag.normal,
    promotion: Int = 0,
    capture: Bool = false
  ) -> EngineMove {
    EngineMove(from | to << 7 | promotion << 14 | flag << 17 | (capture ? 1 << 19 : 0))
  }
  @inline(__always)
  var from: Int { Int(self & 0x7F) }
  @inline(__always)
  var to: Int { Int((self >> 7) & 0x7F) }
  @inline(__always)
  var promotion: Int { Int((self >> 14) & 7) }
  @inline(__always)
  var flag: Int { Int((self >> 17) & 3) }
  @inline(__always)
  var isCapture: Bool { self & (1 << 19) != 0 }
  @inline(__always)
  var isQuiet: Bool { self & (1 << 19 | 7 << 14) == 0 }

  var chessMove: ChessMove {
    let kind: PieceType?
    switch promotion {
    case EngineKind.knight: kind = .knight
    case EngineKind.bishop: kind = .bishop
    case EngineKind.rook: kind = .rook
    case EngineKind.queen: kind = .queen
    default: kind = nil
    }
    return ChessMove(from: EngineBoard.square(from), to: EngineBoard.square(to), promotion: kind)
  }
}

/// Immutable lookup tables shared by every board: move offsets, Zobrist keys, piece-square
/// tables and castling masks. Built once, never mutated, never freed.
final class EngineTables: @unchecked Sendable {
  static let shared = EngineTables()

  /// 0..<8 knight jumps, 8..<12 diagonal steps, 12..<16 orthogonal steps.
  let offsets: UnsafeMutablePointer<Int>
  /// Zobrist keys: 16 * 128 piece-square keys, then 16 castling keys, 8 en-passant file keys, 1
  /// side key.
  let zobrist: UnsafeMutablePointer<UInt64>
  /// Middlegame / endgame value (material + placement) indexed by piece * 128 + square.
  let middlegame: UnsafeMutablePointer<Int>
  let endgame: UnsafeMutablePointer<Int>
  /// Castling rights kept after a move touches a square.
  let castleMask: UnsafeMutablePointer<Int>

  static let castleKeyBase = 16 * 128
  static let enPassantKeyBase = castleKeyBase + 16
  static let sideKeyIndex = enPassantKeyBase + 8

  private init() {
    offsets = .allocate(capacity: 16)
    for (index, offset) in [-33, -31, -18, -14, 14, 18, 31, 33, -17, -15, 15, 17, -16, -1, 1, 16]
      .enumerated()
    {
      offsets[index] = offset
    }

    zobrist = .allocate(capacity: Self.sideKeyIndex + 1)
    var seed: UInt64 = 0x5EED_C0DE_1234_5678
    for index in 0...Self.sideKeyIndex {
      // SplitMix64 gives well-distributed, deterministic keys.
      seed &+= 0x9E37_79B9_7F4A_7C15
      var value = seed
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      zobrist[index] = value ^ (value >> 31)
    }

    middlegame = .allocate(capacity: 16 * 128)
    endgame = .allocate(capacity: 16 * 128)
    middlegame.initialize(repeating: 0, count: 16 * 128)
    endgame.initialize(repeating: 0, count: 16 * 128)
    for kind in 1...6 {
      for rank in 0..<8 {
        for file in 0..<8 {
          let (mg, eg) = EngineEvaluation.placement(kind: kind, file: file, rank: rank)
          let white = kind * 128 + rank * 16 + file
          let black = (kind | EngineKind.blackBit) * 128 + (7 - rank) * 16 + file
          middlegame[white] = mg + EngineEvaluation.middlegameValue[kind]
          endgame[white] = eg + EngineEvaluation.endgameValue[kind]
          middlegame[black] = -middlegame[white]
          endgame[black] = -endgame[white]
        }
      }
    }

    castleMask = .allocate(capacity: 128)
    castleMask.initialize(repeating: 15, count: 128)
    castleMask[0x00] = 15 & ~2  // a1: white queen side
    castleMask[0x07] = 15 & ~1  // h1: white king side
    castleMask[0x04] = 15 & ~3  // e1: both white rights
    castleMask[0x70] = 15 & ~8  // a8: black queen side
    castleMask[0x77] = 15 & ~4  // h8: black king side
    castleMask[0x74] = 15 & ~12  // e8: both black rights
  }
}

struct EngineUndo {
  var move: EngineMove
  var captured: Int
  var castling: Int
  var enPassant: Int
  var halfmove: Int
  var hash: UInt64
  var middlegame: Int
  var endgame: Int
  var phase: Int
}

/// Mutable 0x88 board with make/unmake. Owns its buffers; call `deallocate()` when done.
struct EngineBoard {
  static let maxGamePly = 2048

  let squares: UnsafeMutablePointer<Int>
  /// Number of pieces on the board per piece code (0..<16).
  let counts: UnsafeMutablePointer<Int>
  /// King square per side (0 white, 1 black).
  let kings: UnsafeMutablePointer<Int>
  let undoStack: UnsafeMutablePointer<EngineUndo>
  /// Hash of every position from the start of the known game history to the current node.
  let hashHistory: UnsafeMutablePointer<UInt64>

  let offsets: UnsafeMutablePointer<Int>
  let zobrist: UnsafeMutablePointer<UInt64>
  let pstMiddlegame: UnsafeMutablePointer<Int>
  let pstEndgame: UnsafeMutablePointer<Int>
  let castleMask: UnsafeMutablePointer<Int>

  /// 0 = white to move, 1 = black to move.
  var side = 0
  /// Bit set matching `CastlingRights.rawValue`.
  var castling = 0
  /// 0x88 en-passant target, or -1 when no en-passant capture is available.
  var enPassant = -1
  var halfmove = 0
  var hash: UInt64 = 0
  /// Incremental material + placement sums, white minus black.
  var middlegame = 0
  var endgame = 0
  /// Game phase: 0 (bare kings and pawns) up to 24 (all minor and major pieces).
  var phase = 0
  var undoCount = 0
  var historyCount = 0

  init(_ position: ChessPosition, history: [ChessPosition] = []) {
    let tables = EngineTables.shared
    offsets = tables.offsets
    zobrist = tables.zobrist
    pstMiddlegame = tables.middlegame
    pstEndgame = tables.endgame
    castleMask = tables.castleMask
    squares = .allocate(capacity: 128)
    counts = .allocate(capacity: 16)
    kings = .allocate(capacity: 2)
    undoStack = .allocate(capacity: Self.maxGamePly)
    hashHistory = .allocate(capacity: history.count + Self.maxGamePly)
    for earlier in history {
      load(earlier)
      hashHistory[historyCount] = hash
      historyCount += 1
    }
    load(position)
    hashHistory[historyCount] = hash
    historyCount += 1
  }

  func deallocate() {
    squares.deallocate()
    counts.deallocate()
    kings.deallocate()
    undoStack.deallocate()
    hashHistory.deallocate()
  }

  static func square(_ index: Int) -> Square { Square(file: index & 7, rank: index >> 4) }
  static func index(_ square: Square) -> Int { square.rank * 16 + square.file }

  private static func code(_ piece: Piece) -> Int {
    let kind: Int
    switch piece.type {
    case .pawn: kind = EngineKind.pawn
    case .knight: kind = EngineKind.knight
    case .bishop: kind = EngineKind.bishop
    case .rook: kind = EngineKind.rook
    case .queen: kind = EngineKind.queen
    case .king: kind = EngineKind.king
    }
    return piece.color == .white ? kind : kind | EngineKind.blackBit
  }

  private mutating func load(_ position: ChessPosition) {
    squares.initialize(repeating: 0, count: 128)
    counts.initialize(repeating: 0, count: 16)
    hash = 0
    middlegame = 0
    endgame = 0
    phase = 0
    for (square, piece) in position.board where square.isValid {
      place(Self.code(piece), at: Self.index(square))
    }
    side = position.sideToMove == .white ? 0 : 1
    if side == 1 { hash ^= zobrist[EngineTables.sideKeyIndex] }
    castling = position.castlingRights.rawValue & 15
    hash ^= zobrist[EngineTables.castleKeyBase + castling]
    enPassant = -1
    if let target = position.enPassantTarget, target.isValid {
      setEnPassantIfCapturable(Self.index(target))
    }
    halfmove = position.halfmoveClock
    undoCount = 0
  }

  // MARK: - Piece bookkeeping

  @inline(__always)
  private mutating func place(_ piece: Int, at square: Int) {
    squares[square] = piece
    counts[piece] += 1
    let key = piece * 128 + square
    hash ^= zobrist[key]
    middlegame += pstMiddlegame[key]
    endgame += pstEndgame[key]
    phase += EngineEvaluation.phaseWeight(piece & 7)
    if piece & 7 == EngineKind.king { kings[piece >> 3] = square }
  }

  @inline(__always)
  private mutating func remove(at square: Int) {
    let piece = squares[square]
    squares[square] = 0
    counts[piece] -= 1
    let key = piece * 128 + square
    hash ^= zobrist[key]
    middlegame -= pstMiddlegame[key]
    endgame -= pstEndgame[key]
    phase -= EngineEvaluation.phaseWeight(piece & 7)
  }

  /// Records an en-passant target only when a pawn of the side to move can actually
  /// capture there, so equal positions hash equally for repetition detection.
  @inline(__always)
  private mutating func setEnPassantIfCapturable(_ target: Int) {
    let pawn = side == 0 ? EngineKind.pawn : EngineKind.pawn | EngineKind.blackBit
    let from = side == 0 ? target - 16 : target + 16
    let left = from - 1, right = from + 1
    if (left & 0x88 == 0 && squares[left] == pawn) || (right & 0x88 == 0 && squares[right] == pawn)
    {
      enPassant = target
      hash ^= zobrist[EngineTables.enPassantKeyBase + (target & 7)]
    }
  }

  // MARK: - Attacks

  /// Whether `square` is attacked by pieces of `color` (0 white, 1 black).
  func isAttacked(_ square: Int, by color: Int) -> Bool {
    let colorBit = color << 3
    // Pawns.
    let pawn = EngineKind.pawn | colorBit
    let pawnFrom = color == 0 ? square - 16 : square + 16
    if (pawnFrom - 1) & 0x88 == 0 && squares[pawnFrom - 1] == pawn { return true }
    if (pawnFrom + 1) & 0x88 == 0 && squares[pawnFrom + 1] == pawn { return true }
    // Knights.
    let knight = EngineKind.knight | colorBit
    for index in 0..<8 {
      let from = square + offsets[index]
      if from & 0x88 == 0 && squares[from] == knight { return true }
    }
    // King and sliders.
    let king = EngineKind.king | colorBit
    let bishop = EngineKind.bishop | colorBit
    let rook = EngineKind.rook | colorBit
    let queen = EngineKind.queen | colorBit
    for index in 8..<16 {
      let step = offsets[index]
      let diagonal = index < 12
      var from = square + step
      if from & 0x88 != 0 { continue }
      if squares[from] == king { return true }
      while from & 0x88 == 0 {
        let piece = squares[from]
        if piece != 0 {
          if piece == queen || piece == (diagonal ? bishop : rook) { return true }
          break
        }
        from += step
      }
    }
    return false
  }

  var inCheck: Bool { isAttacked(kings[side], by: side ^ 1) }

  // MARK: - Move generation

  /// Writes pseudo-legal moves into `list` and returns how many were written. In
  /// `capturesOnly` mode it emits captures and queen promotions for quiescence search.
  func generateMoves(into list: UnsafeMutablePointer<EngineMove>, capturesOnly: Bool) -> Int {
    var count = 0
    let us = side
    let usBit = us << 3
    let themBit = usBit ^ EngineKind.blackBit
    let forward = us == 0 ? 16 : -16
    let startRank = us == 0 ? 1 : 6
    let lastRank = us == 0 ? 7 : 0

    @inline(__always)
    func addPawnMove(_ from: Int, _ to: Int, capture: Bool) {
      if to >> 4 == lastRank {
        list[count] = .pack(from, to, promotion: EngineKind.queen, capture: capture)
        count += 1
        if !capturesOnly || capture {
          list[count] = .pack(from, to, promotion: EngineKind.knight, capture: capture)
          list[count + 1] = .pack(from, to, promotion: EngineKind.rook, capture: capture)
          list[count + 2] = .pack(from, to, promotion: EngineKind.bishop, capture: capture)
          count += 3
        }
      } else if capture || !capturesOnly {
        list[count] = .pack(from, to, capture: capture)
        count += 1
      }
    }

    var from = 0
    while from < 128 {
      if from & 0x88 != 0 { from += 8; continue }
      let piece = squares[from]
      if piece == 0 || piece & EngineKind.blackBit != usBit { from += 1; continue }
      let kind = piece & 7
      if kind == EngineKind.pawn {
        let one = from + forward
        if one & 0x88 != 0 { from += 1; continue }
        if squares[one] == 0 {
          addPawnMove(from, one, capture: false)
          if !capturesOnly && from >> 4 == startRank && squares[one + forward] == 0 {
            list[count] = .pack(from, one + forward, flag: MoveFlag.doublePush)
            count += 1
          }
        }
        for to in stride(from: one - 1, through: one + 1, by: 2) where to & 0x88 == 0 {
          let target = squares[to]
          if target != 0 && target & EngineKind.blackBit == themBit {
            addPawnMove(from, to, capture: true)
          } else if to == enPassant {
            list[count] = .pack(from, to, flag: MoveFlag.enPassant, capture: true)
            count += 1
          }
        }
      } else {
        let slides =
          kind == EngineKind.bishop || kind == EngineKind.rook || kind == EngineKind.queen
        let first: Int, last: Int
        switch kind {
        case EngineKind.knight: first = 0; last = 8
        case EngineKind.bishop: first = 8; last = 12
        case EngineKind.rook: first = 12; last = 16
        default: first = 8; last = 16
        }
        for index in first..<last {
          let step = offsets[index]
          var to = from + step
          while to & 0x88 == 0 {
            let target = squares[to]
            guard target == 0 else {
              if target & EngineKind.blackBit == themBit {
                list[count] = .pack(from, to, capture: true)
                count += 1
              }
              break
            }
            if !capturesOnly {
              list[count] = .pack(from, to)
              count += 1
            }
            if !slides { break }
            to += step
          }
        }
        if kind == EngineKind.king && !capturesOnly {
          generateCastling(from: from, into: list, count: &count)
        }
      }
      from += 1
    }
    return count
  }

  private func generateCastling(
    from king: Int,
    into list: UnsafeMutablePointer<EngineMove>,
    count: inout Int
  ) {
    let home = side == 0 ? 0x00 : 0x70
    guard king == home + 4 else { return }
    let kingSide = side == 0 ? 1 : 4
    let queenSide = side == 0 ? 2 : 8
    guard castling & (kingSide | queenSide) != 0 else { return }
    let rook = EngineKind.rook | side << 3
    let them = side ^ 1
    if isAttacked(king, by: them) { return }
    if castling & kingSide != 0, squares[home + 5] == 0, squares[home + 6] == 0,
      squares[home + 7] == rook,
      !isAttacked(home + 5, by: them)
    {
      list[count] = .pack(king, home + 6, flag: MoveFlag.castle)
      count += 1
    }
    if castling & queenSide != 0, squares[home + 1] == 0, squares[home + 2] == 0,
      squares[home + 3] == 0,
      squares[home] == rook, !isAttacked(home + 3, by: them)
    {
      list[count] = .pack(king, home + 2, flag: MoveFlag.castle)
      count += 1
    }
  }

  // MARK: - Make / unmake

  /// Plays a pseudo-legal move. Returns `false` and restores the board when the move
  /// would leave the mover's king in check.
  @discardableResult
  mutating func make(_ move: EngineMove) -> Bool {
    let from = move.from, to = move.to, flag = move.flag
    let us = side
    let piece = squares[from]
    let captured = flag == MoveFlag.enPassant ? (EngineKind.pawn | (us ^ 1) << 3) : squares[to]
    undoStack[undoCount] = EngineUndo(
      move: move,
      captured: captured,
      castling: castling,
      enPassant: enPassant,
      halfmove: halfmove,
      hash: hash,
      middlegame: middlegame,
      endgame: endgame,
      phase: phase
    )
    undoCount += 1

    if enPassant >= 0 { hash ^= zobrist[EngineTables.enPassantKeyBase + (enPassant & 7)] }
    enPassant = -1

    if flag == MoveFlag.enPassant {
      remove(at: us == 0 ? to - 16 : to + 16)
    } else if captured != 0 {
      remove(at: to)
    }
    remove(at: from)
    let promotion = move.promotion
    place(promotion != 0 ? promotion | us << 3 : piece, at: to)
    if flag == MoveFlag.castle {
      if to > from {
        let rook = squares[from + 3]
        remove(at: from + 3)
        place(rook, at: from + 1)
      } else {
        let rook = squares[from - 4]
        remove(at: from - 4)
        place(rook, at: from - 1)
      }
    }

    hash ^= zobrist[EngineTables.castleKeyBase + castling]
    castling &= castleMask[from] & castleMask[to]
    hash ^= zobrist[EngineTables.castleKeyBase + castling]

    halfmove = (piece & 7 == EngineKind.pawn || captured != 0) ? 0 : halfmove + 1
    side = us ^ 1
    hash ^= zobrist[EngineTables.sideKeyIndex]
    if flag == MoveFlag.doublePush { setEnPassantIfCapturable((from + to) / 2) }

    hashHistory[historyCount] = hash
    historyCount += 1

    if isAttacked(kings[us], by: us ^ 1) {
      unmake()
      return false
    }
    return true
  }

  mutating func unmake() {
    undoCount -= 1
    historyCount -= 1
    let undo = undoStack[undoCount]
    let move = undo.move
    let from = move.from, to = move.to, flag = move.flag
    side ^= 1
    let us = side
    let moved = squares[to]
    if move.promotion != 0 {
      counts[moved] -= 1
      counts[EngineKind.pawn | us << 3] += 1
      squares[from] = EngineKind.pawn | us << 3
    } else {
      squares[from] = moved
    }
    if moved & 7 == EngineKind.king { kings[us] = from }
    if flag == MoveFlag.enPassant {
      squares[to] = 0
      squares[us == 0 ? to - 16 : to + 16] = undo.captured
    } else {
      squares[to] = undo.captured
    }
    if undo.captured != 0 { counts[undo.captured] += 1 }
    if flag == MoveFlag.castle {
      if to > from {
        squares[from + 3] = squares[from + 1]
        squares[from + 1] = 0
      } else {
        squares[from - 4] = squares[from - 1]
        squares[from - 1] = 0
      }
    }
    castling = undo.castling
    enPassant = undo.enPassant
    halfmove = undo.halfmove
    hash = undo.hash
    middlegame = undo.middlegame
    endgame = undo.endgame
    phase = undo.phase
  }

  /// Passes the turn (null-move pruning). The halfmove clock is reset so repetition
  /// detection never looks across a null move.
  mutating func makeNull() {
    undoStack[undoCount] = EngineUndo(
      move: 0,
      captured: 0,
      castling: castling,
      enPassant: enPassant,
      halfmove: halfmove,
      hash: hash,
      middlegame: middlegame,
      endgame: endgame,
      phase: phase
    )
    undoCount += 1
    if enPassant >= 0 { hash ^= zobrist[EngineTables.enPassantKeyBase + (enPassant & 7)] }
    enPassant = -1
    halfmove = 0
    side ^= 1
    hash ^= zobrist[EngineTables.sideKeyIndex]
    hashHistory[historyCount] = hash
    historyCount += 1
  }

  mutating func unmakeNull() {
    undoCount -= 1
    historyCount -= 1
    let undo = undoStack[undoCount]
    side ^= 1
    enPassant = undo.enPassant
    halfmove = undo.halfmove
    hash = undo.hash
  }

  // MARK: - Draw detection

  /// True when the current position already occurred since the last irreversible move,
  /// either earlier in the game history or earlier in the search line.
  var isRepetition: Bool {
    let current = historyCount - 1
    let limit = max(0, current - halfmove)
    var index = current - 2
    while index >= limit {
      if hashHistory[index] == hash { return true }
      index -= 2
    }
    return false
  }

  /// Bare kings, or a single minor piece against a bare king.
  var hasInsufficientMaterial: Bool {
    let black = EngineKind.blackBit
    let heavy =
      counts[EngineKind.pawn] + counts[EngineKind.pawn | black]
      + counts[EngineKind.rook] + counts[EngineKind.rook | black]
      + counts[EngineKind.queen] + counts[EngineKind.queen | black]
    if heavy != 0 { return false }
    let minors =
      counts[EngineKind.knight] + counts[EngineKind.knight | black]
      + counts[EngineKind.bishop] + counts[EngineKind.bishop | black]
    return minors <= 1
  }

  /// Whether `color` has any piece besides pawns and king (null-move safety).
  func hasNonPawnMaterial(_ color: Int) -> Bool {
    let bit = color << 3
    return counts[EngineKind.knight | bit] + counts[EngineKind.bishop | bit]
      + counts[EngineKind.rook | bit] + counts[EngineKind.queen | bit] > 0
  }

  // MARK: - Utilities

  /// Hash recomputed from scratch; used to validate incremental hashing in tests.
  func computeHash() -> UInt64 {
    var value: UInt64 = 0
    var square = 0
    while square < 128 {
      if square & 0x88 != 0 { square += 8; continue }
      if squares[square] != 0 { value ^= zobrist[squares[square] * 128 + square] }
      square += 1
    }
    if side == 1 { value ^= zobrist[EngineTables.sideKeyIndex] }
    value ^= zobrist[EngineTables.castleKeyBase + castling]
    if enPassant >= 0 { value ^= zobrist[EngineTables.enPassantKeyBase + (enPassant & 7)] }
    return value
  }

  /// Legal moves at the current node.
  mutating func legalMoves() -> [EngineMove] {
    let buffer = UnsafeMutablePointer<EngineMove>.allocate(capacity: 256)
    defer { buffer.deallocate() }
    let count = generateMoves(into: buffer, capturesOnly: false)
    var result: [EngineMove] = []
    for index in 0..<count where make(buffer[index]) {
      unmake()
      result.append(buffer[index])
    }
    return result
  }

  /// Finds the internal move matching a public move, if it is legal here.
  mutating func engineMove(for move: ChessMove) -> EngineMove? {
    legalMoves().first { $0.chessMove == move }
  }

  /// Counts leaf nodes of the legal move tree to `depth` (move generator validation).
  mutating func perft(_ depth: Int) -> Int {
    let buffer = UnsafeMutablePointer<EngineMove>.allocate(capacity: 256 * max(depth, 1))
    defer { buffer.deallocate() }
    return perft(depth, buffer: buffer)
  }

  private mutating func perft(_ depth: Int, buffer: UnsafeMutablePointer<EngineMove>) -> Int {
    let count = generateMoves(into: buffer, capturesOnly: false)
    var nodes = 0
    for index in 0..<count where make(buffer[index]) {
      nodes += depth <= 1 ? 1 : perft(depth - 1, buffer: buffer + 256)
      unmake()
    }
    return nodes
  }
}
