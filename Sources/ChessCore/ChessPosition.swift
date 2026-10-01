import Foundation

/// A chess position backed by an `EngineBoard`, copied on write. The rules (move generation,
/// attacks, material) are the engine's; the position adds the FEN fields the engine does not keep
/// exactly: the en-passant target after any double push, and the unclamped clocks.
public struct ChessPosition: Equatable, Sendable {
  private final class Storage: @unchecked Sendable {
    var engine: EngineBoard
    var enPassantTarget: Square?
    var halfmoveClock: Int
    var fullmoveNumber: Int

    init(
      engine: consuming EngineBoard,
      enPassantTarget: Square?,
      halfmoveClock: Int,
      fullmoveNumber: Int
    ) {
      self.engine = engine
      self.enPassantTarget = enPassantTarget
      self.halfmoveClock = halfmoveClock
      self.fullmoveNumber = fullmoveNumber
    }

    func copy() -> Storage {
      Storage(
        engine: engine.copy(plyCapacity: 1),
        enPassantTarget: enPassantTarget,
        halfmoveClock: halfmoveClock,
        fullmoveNumber: fullmoveNumber
      )
    }
  }

  private var storage: Storage

  public init(
    board: [Square: Piece],
    sideToMove: PieceColor = .white,
    castlingRights: CastlingRights = [],
    enPassantTarget: Square? = nil,
    halfmoveClock: Int = 0,
    fullmoveNumber: Int = 1
  ) {
    storage = Storage(
      engine: EngineBoard(
        board: board,
        sideToMove: sideToMove,
        castlingRights: castlingRights,
        enPassantTarget: enPassantTarget,
        halfmoveClock: halfmoveClock,
        plyCapacity: 1
      ),
      enPassantTarget: enPassantTarget,
      halfmoveClock: halfmoveClock,
      fullmoveNumber: fullmoveNumber
    )
  }

  public static var initial: Self {
    var board: [Square: Piece] = [:]
    let backRank: [PieceType] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
    for file in 0..<8 {
      board[Square(file: file, rank: 0)] = Piece(type: backRank[file], color: .white)
      board[Square(file: file, rank: 1)] = Piece(type: .pawn, color: .white)
      board[Square(file: file, rank: 6)] = Piece(type: .pawn, color: .black)
      board[Square(file: file, rank: 7)] = Piece(type: backRank[file], color: .black)
    }
    return Self(board: board, castlingRights: .all)
  }

  public var board: [Square: Piece] {
    var board: [Square: Piece] = [:]
    for rank in 0..<8 {
      for file in 0..<8 {
        let square = Square(file: file, rank: rank)
        board[square] = storage.engine.piece(at: square)
      }
    }
    return board
  }

  public var sideToMove: PieceColor { storage.engine.side == 0 ? .white : .black }
  public var castlingRights: CastlingRights { CastlingRights(rawValue: storage.engine.castling) }
  public var enPassantTarget: Square? { storage.enPassantTarget }
  public var halfmoveClock: Int { storage.halfmoveClock }
  public var fullmoveNumber: Int { storage.fullmoveNumber }

  public subscript(square: Square) -> Piece? { storage.engine.piece(at: square) }

  public static func == (lhs: Self, rhs: Self) -> Bool {
    if lhs.storage === rhs.storage { return true }
    return lhs.storage.engine.hasSamePieces(as: rhs.storage.engine)
      && lhs.storage.engine.side == rhs.storage.engine.side
      && lhs.storage.engine.castling == rhs.storage.engine.castling
      && lhs.enPassantTarget == rhs.enPassantTarget
      && lhs.halfmoveClock == rhs.halfmoveClock
      && lhs.fullmoveNumber == rhs.fullmoveNumber
  }

  /// The legal moves of the side to move; none when the engine cannot index the position (for
  /// example a side without exactly one king).
  public func legalMoves() -> [ChessMove] {
    var engine = storage.engine.copy(plyCapacity: 1)
    return engine.legalMoves().map(\.chessMove)
  }

  public func legalMoves(from square: Square) -> [ChessMove] {
    guard self[square]?.color == sideToMove else { return [] }
    return legalMoves().filter { $0.from == square }
  }

  public func applying(_ move: ChessMove) throws -> Self {
    var copy = self
    try copy.apply(move)
    return copy
  }

  public mutating func apply(_ move: ChessMove) throws {
    guard let piece = self[move.from] else { throw ChessRuleError.illegalMove }
    let isCapture = self[move.to] != nil
    let movingColor = sideToMove
    if !isKnownUniquelyReferenced(&storage) { storage = storage.copy() }
    guard storage.engine.play(move) else { throw ChessRuleError.illegalMove }
    let isPawn = piece.type == .pawn
    if isPawn && abs(move.to.rank - move.from.rank) == 2 {
      storage.enPassantTarget = Square(
        file: move.from.file,
        rank: (move.from.rank + move.to.rank) / 2
      )
    } else {
      storage.enPassantTarget = nil
    }
    // FEN accepts clocks up to `Int.max - 1`, so the counters saturate instead of overflowing.
    storage.halfmoveClock =
      isPawn || isCapture ? 0 : Self.saturatingIncrement(storage.halfmoveClock)
    if movingColor == .black {
      storage.fullmoveNumber = Self.saturatingIncrement(storage.fullmoveNumber)
    }
  }

  private static func saturatingIncrement(_ value: Int) -> Int {
    value == .max ? value : value + 1
  }

  /// Whether the king of `color` is attacked; false when `color` has no king.
  public func isInCheck(_ color: PieceColor) -> Bool {
    storage.engine.isKingAttacked(color == .white ? 0 : 1)
  }

  public var outcome: GameOutcome {
    let moves = legalMoves()
    if moves.isEmpty {
      return isInCheck(sideToMove) ? .checkmate(winner: sideToMove.opponent) : .stalemate
    }
    if hasInsufficientMaterial { return .drawInsufficientMaterial }
    if halfmoveClock >= 100 { return .drawFiftyMove }
    return .ongoing
  }

  /// K v K, K+B v K, K+N v K, and K+B v K+B with both bishops on the same square color.
  var hasInsufficientMaterial: Bool { storage.engine.hasInsufficientMaterial }

  public func isSquareAttacked(_ target: Square, by color: PieceColor) -> Bool {
    guard target.isValid else { return false }
    return storage.engine.isAttacked(EngineBoard.index(target), by: color == .white ? 0 : 1)
  }

  /// The Zobrist hash the engine gives this position, for repetition history.
  var engineHash: UInt64 { storage.engine.hash }

  /// Sets `board`, which has no made moves and no history, to this position with
  /// `earlierHashes` as its repetition history.
  func copyEngineState(into board: inout EngineBoard, earlierHashes: [UInt64]) {
    board.copyState(from: storage.engine, earlierHashes: earlierHashes)
  }
}

extension ChessPosition: Codable {
  /// Decodes a position from its FEN string.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    let fen = try container.decode(String.self)
    do {
      try self.init(fen: fen)
    } catch {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid FEN: \(fen)"
      )
    }
  }

  /// Encodes the position as its FEN string.
  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(fen)
  }
}
