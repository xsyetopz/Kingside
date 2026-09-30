import Foundation

public struct ChessPosition: Codable, Equatable, Sendable {
  public private(set) var board: [Square: Piece]
  public private(set) var sideToMove: PieceColor
  public private(set) var castlingRights: CastlingRights
  public private(set) var enPassantTarget: Square?
  public private(set) var halfmoveClock: Int
  public private(set) var fullmoveNumber: Int

  public init(
    board: [Square: Piece],
    sideToMove: PieceColor = .white,
    castlingRights: CastlingRights = [],
    enPassantTarget: Square? = nil,
    halfmoveClock: Int = 0,
    fullmoveNumber: Int = 1
  ) {
    self.board = board
    self.sideToMove = sideToMove
    self.castlingRights = castlingRights
    self.enPassantTarget = enPassantTarget
    self.halfmoveClock = halfmoveClock
    self.fullmoveNumber = fullmoveNumber
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

  public subscript(square: Square) -> Piece? { board[square] }

  public func legalMoves() -> [ChessMove] { legalMoves(for: sideToMove) }

  public func legalMoves(from square: Square) -> [ChessMove] {
    guard board[square]?.color == sideToMove else { return [] }
    return legalMoves().filter { $0.from == square }
  }

  public func legalMoves(for color: PieceColor) -> [ChessMove] {
    pseudoLegalMoves(for: color).filter { move in
      var next = self
      next.makeUnchecked(move, movingColor: color)
      return !next.isInCheck(color)
    }
  }

  public func applying(_ move: ChessMove) throws -> Self {
    guard legalMoves().contains(move) else { throw ChessRuleError.illegalMove }
    var copy = self
    copy.makeUnchecked(move, movingColor: sideToMove)
    return copy
  }

  public mutating func apply(_ move: ChessMove) throws {
    self = try applying(move)
  }

  public func isInCheck(_ color: PieceColor) -> Bool {
    guard let king = board.first(where: { $0.value == Piece(type: .king, color: color) })?.key
    else {
      return false
    }
    return isSquareAttacked(king, by: color.opponent)
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
  var hasInsufficientMaterial: Bool {
    let minors = board.filter { $0.value.type != .king }
    switch minors.count {
    case 0:
      return true
    case 1:
      return [.bishop, .knight].contains(minors.first?.value.type)
    case 2:
      let bishops = minors.filter { $0.value.type == .bishop }
      guard bishops.count == 2, bishops.values.map(\.color).contains(.white),
        bishops.values.map(\.color).contains(.black)
      else { return false }
      return Set(bishops.keys.map { ($0.file + $0.rank) % 2 }).count == 1
    default:
      return false
    }
  }

  public func isSquareAttacked(_ target: Square, by color: PieceColor) -> Bool {
    for (square, piece) in board where piece.color == color {
      let df = target.file - square.file
      let dr = target.rank - square.rank
      switch piece.type {
      case .pawn:
        if dr == color.pawnDirection && abs(df) == 1 { return true }
      case .knight:
        if (abs(df), abs(dr)) == (1, 2) || (abs(df), abs(dr)) == (2, 1) { return true }
      case .bishop:
        if abs(df) == abs(dr) && pathIsClear(from: square, to: target) { return true }
      case .rook:
        if (df == 0 || dr == 0) && pathIsClear(from: square, to: target) { return true }
      case .queen:
        if (df == 0 || dr == 0 || abs(df) == abs(dr)) && pathIsClear(from: square, to: target) {
          return true
        }
      case .king:
        if max(abs(df), abs(dr)) == 1 { return true }
      }
    }
    return false
  }

  private func pseudoLegalMoves(for color: PieceColor) -> [ChessMove] {
    var moves: [ChessMove] = []
    for (square, piece) in board.sorted(by: { $0.key < $1.key }) where piece.color == color {
      switch piece.type {
      case .pawn: moves += pawnMoves(from: square, color: color)
      case .knight:
        moves += jumpMoves(
          from: square,
          color: color,
          offsets: [(-2, -1), (-2, 1), (-1, -2), (-1, 2), (1, -2), (1, 2), (2, -1), (2, 1)]
        )
      case .bishop:
        moves += slidingMoves(
          from: square,
          color: color,
          directions: [(-1, -1), (-1, 1), (1, -1), (1, 1)]
        )
      case .rook:
        moves += slidingMoves(
          from: square,
          color: color,
          directions: [(-1, 0), (1, 0), (0, -1), (0, 1)]
        )
      case .queen:
        moves += slidingMoves(
          from: square,
          color: color,
          directions: [(-1, -1), (-1, 1), (1, -1), (1, 1), (-1, 0), (1, 0), (0, -1), (0, 1)]
        )
      case .king: moves += kingMoves(from: square, color: color)
      }
    }
    return moves
  }

  private func pawnMoves(from: Square, color: PieceColor) -> [ChessMove] {
    var moves: [ChessMove] = []
    let one = Square(file: from.file, rank: from.rank + color.pawnDirection)
    if one.isValid, board[one] == nil {
      addPawnMove(from: from, to: one, color: color, into: &moves)
      let two = Square(file: from.file, rank: from.rank + 2 * color.pawnDirection)
      if from.rank == color.pawnStartRank, board[two] == nil {
        moves.append(ChessMove(from: from, to: two))
      }
    }
    for deltaFile in [-1, 1] {
      let target = Square(file: from.file + deltaFile, rank: from.rank + color.pawnDirection)
      guard target.isValid else { continue }
      if let victim = board[target], victim.color != color, victim.type != .king {
        addPawnMove(from: from, to: target, color: color, into: &moves)
      } else if target == enPassantTarget {
        let victimSquare = Square(file: target.file, rank: from.rank)
        if board[victimSquare] == Piece(type: .pawn, color: color.opponent) {
          moves.append(ChessMove(from: from, to: target))
        }
      }
    }
    return moves
  }

  private func addPawnMove(
    from: Square,
    to: Square,
    color: PieceColor,
    into moves: inout [ChessMove]
  ) {
    if to.rank == color.promotionRank {
      for promotion in [PieceType.queen, .rook, .bishop, .knight] {
        moves.append(ChessMove(from: from, to: to, promotion: promotion))
      }
    } else {
      moves.append(ChessMove(from: from, to: to))
    }
  }

  private func jumpMoves(from: Square, color: PieceColor, offsets: [(Int, Int)]) -> [ChessMove] {
    offsets.compactMap { df, dr in
      let target = Square(file: from.file + df, rank: from.rank + dr)
      guard target.isValid else { return nil }
      guard board[target]?.color != color, board[target]?.type != .king else { return nil }
      return ChessMove(from: from, to: target)
    }
  }

  private func slidingMoves(
    from: Square,
    color: PieceColor,
    directions: [(Int, Int)]
  ) -> [ChessMove] {
    var moves: [ChessMove] = []
    for (df, dr) in directions {
      var target = Square(file: from.file + df, rank: from.rank + dr)
      while target.isValid {
        if let occupant = board[target] {
          if occupant.color != color && occupant.type != .king {
            moves.append(ChessMove(from: from, to: target))
          }
          break
        }
        moves.append(ChessMove(from: from, to: target))
        target = Square(file: target.file + df, rank: target.rank + dr)
      }
    }
    return moves
  }

  private func kingMoves(from: Square, color: PieceColor) -> [ChessMove] {
    var moves = jumpMoves(
      from: from,
      color: color,
      offsets: [(-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1)]
    )
    guard !isInCheck(color), from == Square(file: 4, rank: color.homeRank) else { return moves }
    let opponent = color.opponent
    let kingRight: CastlingRights = color == .white ? .whiteKingSide : .blackKingSide
    if castlingRights.contains(kingRight),
      board[Square(file: 5, rank: color.homeRank)] == nil,
      board[Square(file: 6, rank: color.homeRank)] == nil,
      board[Square(file: 7, rank: color.homeRank)] == Piece(type: .rook, color: color),
      !isSquareAttacked(Square(file: 5, rank: color.homeRank), by: opponent),
      !isSquareAttacked(Square(file: 6, rank: color.homeRank), by: opponent)
    {
      moves.append(ChessMove(from: from, to: Square(file: 6, rank: color.homeRank)))
    }
    let queenRight: CastlingRights = color == .white ? .whiteQueenSide : .blackQueenSide
    if castlingRights.contains(queenRight),
      board[Square(file: 1, rank: color.homeRank)] == nil,
      board[Square(file: 2, rank: color.homeRank)] == nil,
      board[Square(file: 3, rank: color.homeRank)] == nil,
      board[Square(file: 0, rank: color.homeRank)] == Piece(type: .rook, color: color),
      !isSquareAttacked(Square(file: 3, rank: color.homeRank), by: opponent),
      !isSquareAttacked(Square(file: 2, rank: color.homeRank), by: opponent)
    {
      moves.append(ChessMove(from: from, to: Square(file: 2, rank: color.homeRank)))
    }
    return moves
  }

  private func pathIsClear(from: Square, to: Square) -> Bool {
    let df = (to.file - from.file).signum()
    let dr = (to.rank - from.rank).signum()
    var cursor = Square(file: from.file + df, rank: from.rank + dr)
    while cursor != to {
      if board[cursor] != nil { return false }
      cursor = Square(file: cursor.file + df, rank: cursor.rank + dr)
    }
    return true
  }

  private mutating func makeUnchecked(_ move: ChessMove, movingColor: PieceColor) {
    guard var piece = board.removeValue(forKey: move.from) else { return }
    let wasPawn = piece.type == .pawn
    let captured = board[move.to]
    if wasPawn, move.to == enPassantTarget, captured == nil, move.from.file != move.to.file {
      board.removeValue(forKey: Square(file: move.to.file, rank: move.from.rank))
    }
    if piece.type == .king, abs(move.to.file - move.from.file) == 2 {
      let rookFrom = Square(file: move.to.file == 6 ? 7 : 0, rank: move.from.rank)
      let rookTo = Square(file: move.to.file == 6 ? 5 : 3, rank: move.from.rank)
      board[rookTo] = board.removeValue(forKey: rookFrom)
    }
    if let promotion = move.promotion, wasPawn {
      piece = Piece(type: promotion, color: piece.color)
    }
    board[move.to] = piece
    updateCastlingRights(for: move, piece: piece, captured: captured)
    if wasPawn && abs(move.to.rank - move.from.rank) == 2 {
      enPassantTarget = Square(file: move.from.file, rank: (move.from.rank + move.to.rank) / 2)
    } else {
      enPassantTarget = nil
    }
    halfmoveClock = wasPawn || captured != nil ? 0 : halfmoveClock + 1
    if movingColor == .black { fullmoveNumber += 1 }
    sideToMove = movingColor.opponent
  }

  private mutating func updateCastlingRights(for move: ChessMove, piece: Piece, captured: Piece?) {
    if piece.type == .king {
      if piece.color == .white {
        castlingRights.subtract([.whiteKingSide, .whiteQueenSide])
      } else {
        castlingRights.subtract([.blackKingSide, .blackQueenSide])
      }
    }
    removeRookRight(at: move.from)
    if captured?.type == .rook { removeRookRight(at: move.to) }
  }

  private mutating func removeRookRight(at square: Square) {
    switch square {
    case Square(file: 0, rank: 0): castlingRights.remove(.whiteQueenSide)
    case Square(file: 7, rank: 0): castlingRights.remove(.whiteKingSide)
    case Square(file: 0, rank: 7): castlingRights.remove(.blackQueenSide)
    case Square(file: 7, rank: 7): castlingRights.remove(.blackKingSide)
    default: break
    }
  }
}
