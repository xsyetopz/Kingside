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
  /// The bits of a piece code that hold its kind; `blackBit` is the only other bit.
  static let mask = 7
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
  let offsets: UnsafePointer<Int>
  /// Zobrist keys: 16 * 128 piece-square keys, then 16 castling keys, 8 en-passant file keys, 1
  /// side key.
  let zobrist: UnsafePointer<UInt64>
  /// Middlegame / endgame value (material + placement) indexed by piece * 128 + square.
  let middlegame: UnsafePointer<Int>
  let endgame: UnsafePointer<Int>
  /// Castling rights kept after a move touches a square.
  let castleMask: UnsafePointer<Int>

  static let castleKeyBase = 16 * 128
  /// One key per `CastlingRights.rawValue`.
  static let castleKeyCount = 16
  static let enPassantKeyBase = castleKeyBase + castleKeyCount
  static let sideKeyIndex = enPassantKeyBase + 8

  private init() {
    let (middlegame, endgame) = Self.makePieceSquareTables()
    offsets = UnsafePointer(Self.makeOffsets())
    zobrist = UnsafePointer(Self.makeZobrist())
    self.middlegame = UnsafePointer(middlegame)
    self.endgame = UnsafePointer(endgame)
    castleMask = UnsafePointer(Self.makeCastleMask())
  }

  private static func makeOffsets() -> UnsafeMutablePointer<Int> {
    let offsets = UnsafeMutablePointer<Int>.allocate(capacity: 16)
    for (index, offset) in [-33, -31, -18, -14, 14, 18, 31, 33, -17, -15, 15, 17, -16, -1, 1, 16]
      .enumerated()
    {
      offsets[index] = offset
    }
    return offsets
  }

  private static func makeZobrist() -> UnsafeMutablePointer<UInt64> {
    let zobrist = UnsafeMutablePointer<UInt64>.allocate(capacity: Self.sideKeyIndex + 1)
    var seed: UInt64 = 0x5EED_C0DE_1234_5678
    for index in 0...Self.sideKeyIndex {
      // SplitMix64 gives well-distributed, deterministic keys.
      seed &+= 0x9E37_79B9_7F4A_7C15
      var value = seed
      value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
      value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
      zobrist[index] = value ^ (value >> 31)
    }
    return zobrist
  }

  private static func makePieceSquareTables() -> (
    middlegame: UnsafeMutablePointer<Int>, endgame: UnsafeMutablePointer<Int>
  ) {
    let middlegame = UnsafeMutablePointer<Int>.allocate(capacity: 16 * 128)
    let endgame = UnsafeMutablePointer<Int>.allocate(capacity: 16 * 128)
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
    return (middlegame, endgame)
  }

  /// Rights kept when a move starts or ends on each square: all of them, except on the king and
  /// rook home squares, where moving or capturing loses the matching rights.
  private static func makeCastleMask() -> UnsafeMutablePointer<Int> {
    let castleMask = UnsafeMutablePointer<Int>.allocate(capacity: 128)
    castleMask.initialize(repeating: CastlingRights.all.rawValue, count: 128)
    let losses: [(square: Int, lost: CastlingRights)] = [
      (0x00, .whiteQueenSide),  // a1
      (0x07, .whiteKingSide),  // h1
      (0x04, [.whiteKingSide, .whiteQueenSide]),  // e1
      (0x70, .blackQueenSide),  // a8
      (0x77, .blackKingSide),  // h8
      (0x74, [.blackKingSide, .blackQueenSide]),  // e8
    ]
    for (square, lost) in losses {
      castleMask[square] = CastlingRights.all.subtracting(lost).rawValue
    }
    return castleMask
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

/// Mutable 0x88 board with make/unmake. Owns its buffers and frees them in `deinit`.
struct EngineBoard: ~Copyable {
  static let maxGamePly = 2048
  /// Room for the pseudo-legal moves of one position. Enough for every supported position,
  /// because `isSupported` rejects more promoted pieces than missing pawns.
  static let moveListCapacity = 256

  let squares: UnsafeMutablePointer<Int>
  /// Number of pieces on the board per piece code (0..<16).
  let counts: UnsafeMutablePointer<Int>
  /// King square per side (0 white, 1 black).
  let kings: UnsafeMutablePointer<Int>
  /// Most moves that can be made at once: `undoStack` and the tail of `hashHistory` hold no more.
  let plyCapacity: Int
  let undoStack: UnsafeMutablePointer<EngineUndo>
  /// Hash of every position from the start of the known game history to the current node.
  let hashHistory: UnsafeMutablePointer<UInt64>

  let offsets: UnsafePointer<Int>
  let zobrist: UnsafePointer<UInt64>
  let pstMiddlegame: UnsafePointer<Int>
  let pstEndgame: UnsafePointer<Int>
  let castleMask: UnsafePointer<Int>

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
  /// Whether the loaded position is one the move generator can index safely: one king per side,
  /// no pawn on a back rank, no more promoted pieces than missing pawns, and no king capturable.
  /// When false, `legalMoves()` and `perft` find nothing.
  private(set) var isSupported = false

  /// A board with room for a whole game of moves, for search.
  init(_ position: ChessPosition, history: [ChessPosition] = []) {
    self.init(position, history: history, plyCapacity: Self.maxGamePly)
  }

  /// A board for rules queries such as `legalMoves()`: it can hold `plyCapacity` made moves
  /// (at least `depth` for `perft(depth)`), so it does not allocate search-size buffers.
  init(_ position: ChessPosition, history: [ChessPosition] = [], plyCapacity: Int) {
    let earlierHashes = history.map(\.engineHash)
    self.init(plyCapacity: plyCapacity, historyCapacity: earlierHashes.count + 1 + plyCapacity)
    position.copyEngineState(into: &self, earlierHashes: earlierHashes)
  }

  /// A board at the given position with no earlier history, holding `plyCapacity` made moves.
  /// Pieces on off-board squares are dropped.
  init(
    board: [Square: Piece],
    sideToMove: PieceColor,
    castlingRights: CastlingRights,
    enPassantTarget: Square?,
    halfmoveClock: Int,
    plyCapacity: Int
  ) {
    self.init(plyCapacity: plyCapacity, historyCapacity: 1 + plyCapacity)
    load(
      board: board,
      sideToMove: sideToMove,
      castlingRights: castlingRights,
      enPassantTarget: enPassantTarget,
      halfmoveClock: halfmoveClock
    )
    hashHistory[0] = hash
    historyCount = 1
  }

  /// Allocates the buffers; the caller fills the position.
  private init(plyCapacity: Int, historyCapacity: Int) {
    precondition(plyCapacity >= 1, "a board must hold at least one made move")
    let tables = EngineTables.shared
    offsets = tables.offsets
    zobrist = tables.zobrist
    pstMiddlegame = tables.middlegame
    pstEndgame = tables.endgame
    castleMask = tables.castleMask
    squares = .allocate(capacity: 128)
    counts = .allocate(capacity: 16)
    kings = .allocate(capacity: 2)
    self.plyCapacity = plyCapacity
    undoStack = .allocate(capacity: plyCapacity)
    hashHistory = .allocate(capacity: historyCapacity)
  }

  /// A board at the current position with no made moves, holding `plyCapacity` made moves, whose
  /// repetition history is `earlierHashes` (oldest first) followed by the current position.
  func copy(plyCapacity: Int, earlierHashes: [UInt64] = []) -> Self {
    var board = Self(
      plyCapacity: plyCapacity,
      historyCapacity: earlierHashes.count + 1 + plyCapacity
    )
    board.copyState(from: self, earlierHashes: earlierHashes)
    return board
  }

  /// Sets this board, which has no made moves and no history, to `source`'s current position
  /// with `earlierHashes` as its repetition history; its buffers must hold that history.
  mutating func copyState(from source: borrowing Self, earlierHashes: [UInt64]) {
    precondition(undoCount == 0 && historyCount == 0, "copyState needs a board with no moves")
    squares.initialize(from: source.squares, count: 128)
    counts.initialize(from: source.counts, count: 16)
    kings.initialize(from: source.kings, count: 2)
    side = source.side
    castling = source.castling
    enPassant = source.enPassant
    halfmove = clampedClock(source.halfmove)
    hash = source.hash
    middlegame = source.middlegame
    endgame = source.endgame
    phase = source.phase
    isSupported = source.isSupported
    for earlier in earlierHashes {
      hashHistory[historyCount] = earlier
      historyCount += 1
    }
    hashHistory[historyCount] = hash
    historyCount += 1
  }

  deinit {
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

  private mutating func load(
    board: [Square: Piece],
    sideToMove: PieceColor,
    castlingRights: CastlingRights,
    enPassantTarget: Square?,
    halfmoveClock: Int
  ) {
    squares.initialize(repeating: 0, count: 128)
    counts.initialize(repeating: 0, count: 16)
    // A missing king leaves a valid square here, never uninitialized memory.
    kings.initialize(repeating: 0, count: 2)
    hash = 0
    middlegame = 0
    endgame = 0
    phase = 0
    for (square, piece) in board where square.isValid {
      place(Self.code(piece), at: Self.index(square))
    }
    side = sideToMove == .white ? 0 : 1
    if side == 1 { hash ^= zobrist[EngineTables.sideKeyIndex] }
    castling = castlingRights.intersection(.all).rawValue
    hash ^= zobrist[EngineTables.castleKeyBase + castling]
    enPassant = -1
    if let target = enPassantTarget, target.isValid,
      isSkippedSquare(Self.index(target))
    {
      setEnPassantIfCapturable(Self.index(target))
    }
    halfmove = clampedClock(halfmoveClock)
    undoCount = 0
    isSupported = computeIsSupported()
  }

  /// Whether `target` is the square an opponent pawn just skipped with a double push: it is on
  /// the skipped rank, it and the pawn's starting square are empty, and the pawn stands beyond it.
  private func isSkippedSquare(_ target: Int) -> Bool {
    let forward = side == 0 ? 16 : -16
    let opponentPawn = EngineKind.pawn | (side ^ 1) << 3
    return target >> 4 == (side == 0 ? 5 : 2) && squares[target] == 0
      && squares[target + forward] == 0 && squares[target - forward] == opponentPawn
  }

  private func computeIsSupported() -> Bool {
    let black = EngineKind.blackBit
    guard counts[EngineKind.king] == 1, counts[EngineKind.king | black] == 1 else { return false }
    for file in 0..<8
    where squares[file] & EngineKind.mask == EngineKind.pawn
      || squares[0x70 + file] & EngineKind.mask == EngineKind.pawn
    {
      return false
    }
    for colorBit in [0, black]
    where promotedPieces(colorBit) > 8 - counts[EngineKind.pawn | colorBit] {
      return false
    }
    return !isAttacked(kings[side ^ 1], by: side)
  }

  /// `clock`, lowered so that `make` can add 1 once per made move the board holds without
  /// overflow. The engine only compares the clock with 100 and with the length of its repetition
  /// history, both far below the bound, so the lowered clock gives the same results.
  private func clampedClock(_ clock: Int) -> Int { min(clock, Int.max - plyCapacity) }

  /// Pieces of one color beyond the starting count of their kind, which only promotion makes.
  private func promotedPieces(_ colorBit: Int) -> Int {
    max(0, counts[EngineKind.knight | colorBit] - 2)
      + max(0, counts[EngineKind.bishop | colorBit] - 2)
      + max(0, counts[EngineKind.rook | colorBit] - 2)
      + max(0, counts[EngineKind.queen | colorBit] - 1)
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
    phase += EngineEvaluation.phaseWeight(piece & EngineKind.mask)
    if piece & EngineKind.mask == EngineKind.king { kings[piece >> 3] = square }
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
    phase -= EngineEvaluation.phaseWeight(piece & EngineKind.mask)
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
    return isAttackedByPawn(square, colorBit: colorBit)
      || isAttackedByKnight(square, colorBit: colorBit)
      || isAttackedByKingOrSlider(square, colorBit: colorBit)
  }

  @inline(__always)
  private func isAttackedByPawn(_ square: Int, colorBit: Int) -> Bool {
    let pawn = EngineKind.pawn | colorBit
    let pawnFrom = colorBit == 0 ? square - 16 : square + 16
    if (pawnFrom - 1) & 0x88 == 0 && squares[pawnFrom - 1] == pawn { return true }
    return (pawnFrom + 1) & 0x88 == 0 && squares[pawnFrom + 1] == pawn
  }

  @inline(__always)
  private func isAttackedByKnight(_ square: Int, colorBit: Int) -> Bool {
    let knight = EngineKind.knight | colorBit
    for index in 0..<8 {
      let from = square + offsets[index]
      if from & 0x88 == 0 && squares[from] == knight { return true }
    }
    return false
  }

  @inline(__always)
  private func isAttackedByKingOrSlider(_ square: Int, colorBit: Int) -> Bool {
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
    let usBit = side << 3
    var from = 0
    while from < 128 {
      if from & 0x88 != 0 { from += 8; continue }
      let piece = squares[from]
      guard piece != 0 && piece & EngineKind.blackBit == usBit else { from += 1; continue }
      let kind = piece & EngineKind.mask
      if kind == EngineKind.pawn {
        generatePawnMoves(from: from, into: list, count: &count, capturesOnly: capturesOnly)
      } else {
        generatePieceMoves(kind, from: from, into: list, count: &count, capturesOnly: capturesOnly)
      }
      from += 1
    }
    return count
  }

  @inline(__always)
  private func generatePawnMoves(
    from: Int,
    into list: UnsafeMutablePointer<EngineMove>,
    count: inout Int,
    capturesOnly: Bool
  ) {
    let forward = side == 0 ? 16 : -16
    let one = from + forward
    guard one & 0x88 == 0 else { return }
    if squares[one] == 0 {
      addPawnMove(from, one, capture: false, into: list, count: &count, capturesOnly: capturesOnly)
      let startRank = side == 0 ? 1 : 6
      if !capturesOnly && from >> 4 == startRank && squares[one + forward] == 0 {
        list[count] = .pack(from, one + forward, flag: MoveFlag.doublePush)
        count += 1
      }
    }
    addPawnCaptures(from: from, one: one, into: list, count: &count, capturesOnly: capturesOnly)
  }

  /// Adds the diagonal captures, including en passant, of the pawn on `from` whose one-step
  /// push square is `one`.
  @inline(__always)
  private func addPawnCaptures(
    from: Int,
    one: Int,
    into list: UnsafeMutablePointer<EngineMove>,
    count: inout Int,
    capturesOnly: Bool
  ) {
    let themBit = (side ^ 1) << 3
    for to in stride(from: one - 1, through: one + 1, by: 2) where to & 0x88 == 0 {
      let target = squares[to]
      if target != 0 && target & EngineKind.blackBit == themBit {
        addPawnMove(from, to, capture: true, into: list, count: &count, capturesOnly: capturesOnly)
      } else if to == enPassant {
        list[count] = .pack(from, to, flag: MoveFlag.enPassant, capture: true)
        count += 1
      }
    }
  }

  /// Adds a pawn move to `to`, as four promotions on the last rank. In `capturesOnly` mode only
  /// captures and the queen promotion of a push are added.
  @inline(__always)
  private func addPawnMove(
    _ from: Int,
    _ to: Int,
    capture: Bool,
    into list: UnsafeMutablePointer<EngineMove>,
    count: inout Int,
    capturesOnly: Bool
  ) {
    let lastRank = side == 0 ? 7 : 0
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

  @inline(__always)
  private func generatePieceMoves(
    _ kind: Int,
    from: Int,
    into list: UnsafeMutablePointer<EngineMove>,
    count: inout Int,
    capturesOnly: Bool
  ) {
    let slides = kind == EngineKind.bishop || kind == EngineKind.rook || kind == EngineKind.queen
    let first: Int, last: Int
    switch kind {
    case EngineKind.knight: first = 0; last = 8
    case EngineKind.bishop: first = 8; last = 12
    case EngineKind.rook: first = 12; last = 16
    default: first = 8; last = 16
    }
    for index in first..<last {
      addStepMoves(
        from: from,
        step: offsets[index],
        slides: slides,
        into: list,
        count: &count,
        capturesOnly: capturesOnly
      )
    }
    if kind == EngineKind.king && !capturesOnly {
      generateCastling(from: from, into: list, count: &count)
    }
  }

  /// Adds moves along one direction: a single step, or every step up to a blocker for a slider.
  @inline(__always)
  private func addStepMoves(
    from: Int,
    step: Int,
    slides: Bool,
    into list: UnsafeMutablePointer<EngineMove>,
    count: inout Int,
    capturesOnly: Bool
  ) {
    let themBit = (side ^ 1) << 3
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

  private func generateCastling(
    from king: Int,
    into list: UnsafeMutablePointer<EngineMove>,
    count: inout Int
  ) {
    let home = side == 0 ? 0x00 : 0x70
    guard king == home + 4 else { return }
    let kingSide = (side == 0 ? CastlingRights.whiteKingSide : .blackKingSide).rawValue
    let queenSide = (side == 0 ? CastlingRights.whiteQueenSide : .blackQueenSide).rawValue
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
    // FEN validation guarantees the side not to move is not in check, so no king is capturable.
    assert(captured & EngineKind.mask != EngineKind.king, "pseudo-legal move captures a king")
    pushUndo(move: move, captured: captured)
    clearEnPassant()

    removeCaptured(captured, to: to, flag: flag)
    remove(at: from)
    let promotion = move.promotion
    place(promotion != 0 ? promotion | us << 3 : piece, at: to)
    if flag == MoveFlag.castle { moveCastlingRook(kingFrom: from, kingTo: to) }
    updateCastlingRights(from: from, to: to)

    halfmove = (piece & EngineKind.mask == EngineKind.pawn || captured != 0) ? 0 : halfmove + 1
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

  /// Saves the state that `unmake` and `unmakeNull` cannot recompute.
  @inline(__always)
  private mutating func pushUndo(move: EngineMove, captured: Int) {
    assert(undoCount < plyCapacity, "more made moves than plyCapacity")
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
  }

  /// Takes the piece captured by the mover's move to `to` off the board, if there is one. An en
  /// passant capture takes the pawn behind `to`. Call it before `side` changes.
  @inline(__always)
  private mutating func removeCaptured(_ captured: Int, to: Int, flag: Int) {
    if flag == MoveFlag.enPassant {
      remove(at: side == 0 ? to - 16 : to + 16)
    } else if captured != 0 {
      remove(at: to)
    }
  }

  @inline(__always)
  private mutating func clearEnPassant() {
    if enPassant >= 0 { hash ^= zobrist[EngineTables.enPassantKeyBase + (enPassant & 7)] }
    enPassant = -1
  }

  /// Moves the rook of a castling move whose king went from `kingFrom` to `kingTo`.
  @inline(__always)
  private mutating func moveCastlingRook(kingFrom: Int, kingTo: Int) {
    let (rookFrom, rookTo) = Self.castlingRookSquares(kingFrom: kingFrom, kingTo: kingTo)
    let rook = squares[rookFrom]
    remove(at: rookFrom)
    place(rook, at: rookTo)
  }

  /// The rook's start and end squares for a castling king move from `kingFrom` to `kingTo`.
  @inline(__always)
  private static func castlingRookSquares(kingFrom: Int, kingTo: Int) -> (from: Int, to: Int) {
    kingTo > kingFrom ? (kingFrom + 3, kingFrom + 1) : (kingFrom - 4, kingFrom - 1)
  }

  /// Drops the castling rights that a move between `from` and `to` loses.
  @inline(__always)
  private mutating func updateCastlingRights(from: Int, to: Int) {
    hash ^= zobrist[EngineTables.castleKeyBase + castling]
    castling &= castleMask[from] & castleMask[to]
    hash ^= zobrist[EngineTables.castleKeyBase + castling]
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
    if moved & EngineKind.mask == EngineKind.king { kings[us] = from }
    if flag == MoveFlag.enPassant {
      squares[to] = 0
      squares[us == 0 ? to - 16 : to + 16] = undo.captured
    } else {
      squares[to] = undo.captured
    }
    if undo.captured != 0 { counts[undo.captured] += 1 }
    if flag == MoveFlag.castle { restoreCastlingRook(kingFrom: from, kingTo: to) }
    castling = undo.castling
    enPassant = undo.enPassant
    halfmove = undo.halfmove
    hash = undo.hash
    middlegame = undo.middlegame
    endgame = undo.endgame
    phase = undo.phase
  }

  /// Puts back the rook of a castling move. Only `squares` changes: `unmake` restores the
  /// incremental sums from the undo record.
  @inline(__always)
  private func restoreCastlingRook(kingFrom: Int, kingTo: Int) {
    let (rookFrom, rookTo) = Self.castlingRookSquares(kingFrom: kingFrom, kingTo: kingTo)
    squares[rookFrom] = squares[rookTo]
    squares[rookTo] = 0
  }

  /// Passes the turn (null-move pruning). The halfmove clock is reset so repetition
  /// detection never looks across a null move.
  mutating func makeNull() {
    pushUndo(move: 0, captured: 0)
    clearEnPassant()
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

  /// Bare kings, a single minor piece against a bare king, or one bishop each on squares of
  /// the same color.
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
    if minors <= 1 { return true }
    return minors == 2 && counts[EngineKind.bishop] == 1 && counts[EngineKind.bishop | black] == 1
      && bishopsShareSquareColor
  }

  /// Whether the two bishops (one per side) stand on squares of one color.
  private var bishopsShareSquareColor: Bool {
    var parity = 0
    var square = 0
    while square < 128 {
      if square & 0x88 != 0 { square += 8; continue }
      if squares[square] & EngineKind.mask == EngineKind.bishop {
        parity ^= ((square >> 4) + square) & 1
      }
      square += 1
    }
    return parity == 0
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

  /// The piece on `square`, or nil when it is empty or off the board.
  func piece(at square: Square) -> Piece? {
    guard square.isValid else { return nil }
    let code = squares[Self.index(square)]
    let type: PieceType
    switch code & EngineKind.mask {
    case EngineKind.pawn: type = .pawn
    case EngineKind.knight: type = .knight
    case EngineKind.bishop: type = .bishop
    case EngineKind.rook: type = .rook
    case EngineKind.queen: type = .queen
    case EngineKind.king: type = .king
    default: return nil
    }
    return Piece(type: type, color: code & EngineKind.blackBit == 0 ? .white : .black)
  }

  /// Whether the king of `color` (0 white, 1 black) is attacked; false when it has no king.
  func isKingAttacked(_ color: Int) -> Bool {
    counts[EngineKind.king | color << 3] > 0 && isAttacked(kings[color], by: color ^ 1)
  }

  /// Whether both boards hold the same pieces on the same squares.
  func hasSamePieces(as other: borrowing Self) -> Bool {
    for square in 0..<128 where squares[square] != other.squares[square] { return false }
    return true
  }

  /// Legal moves at the current node.
  mutating func legalMoves() -> [EngineMove] {
    guard isSupported else { return [] }
    let buffer = UnsafeMutablePointer<EngineMove>.allocate(capacity: Self.moveListCapacity)
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

  /// Plays a legal move for good: the board forgets its undo and repetition history, so it keeps
  /// playing moves at any `plyCapacity`. Returns false, leaving the board unchanged, when the move
  /// is not legal here. The board must have no outstanding `make`: play stops the program
  /// otherwise, because its own `make` could write past the undo stack.
  mutating func play(_ move: ChessMove) -> Bool {
    precondition(undoCount == 0, "play with an outstanding make")
    guard isSupported else { return false }
    let buffer = UnsafeMutablePointer<EngineMove>.allocate(capacity: Self.moveListCapacity)
    defer { buffer.deallocate() }
    let count = generateMoves(into: buffer, capturesOnly: false)
    guard let index = (0..<count).first(where: { buffer[$0].chessMove == move }),
      make(buffer[index])
    else { return false }
    undoCount = 0
    hashHistory[0] = hash
    historyCount = 1
    halfmove = clampedClock(halfmove)
    return true
  }

  /// Counts leaf nodes of the legal move tree to `depth` (move generator validation).
  mutating func perft(_ depth: Int) -> Int {
    guard isSupported else { return 0 }
    // Depth 0 still makes one move per legal move, like depth 1.
    precondition(undoCount + max(depth, 1) <= plyCapacity, "perft depth exceeds plyCapacity")
    let buffer = UnsafeMutablePointer<EngineMove>.allocate(
      capacity: Self.moveListCapacity * max(depth, 1)
    )
    defer { buffer.deallocate() }
    return perft(depth, buffer: buffer)
  }

  private mutating func perft(_ depth: Int, buffer: UnsafeMutablePointer<EngineMove>) -> Int {
    let count = generateMoves(into: buffer, capturesOnly: false)
    var nodes = 0
    for index in 0..<count where make(buffer[index]) {
      nodes += depth <= 1 ? 1 : perft(depth - 1, buffer: buffer + Self.moveListCapacity)
      unmake()
    }
    return nodes
  }
}
