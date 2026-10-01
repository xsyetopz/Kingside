import Foundation

public struct PlayedMove: Codable, Equatable, Sendable, Identifiable {
  public let id: UUID
  public let move: ChessMove
  public let san: String
  public let positionBefore: ChessPosition

  public init(id: UUID = UUID(), move: ChessMove, san: String, positionBefore: ChessPosition) {
    self.id = id
    self.move = move
    self.san = san
    self.positionBefore = positionBefore
  }
}

public struct ChessGame: Codable, Equatable, Sendable {
  public private(set) var position: ChessPosition
  public private(set) var moves: [PlayedMove]
  public let initialPosition: ChessPosition

  public init(position: ChessPosition = .initial, moves: [PlayedMove] = []) {
    self.position = position
    self.moves = moves
    self.initialPosition = moves.first?.positionBefore ?? position
  }

  /// Position outcome plus draw by threefold repetition. Checkmate, stalemate and
  /// insufficient material take precedence over repetition.
  public var outcome: GameOutcome {
    let base = position.outcome
    if base != .ongoing { return base }
    let key = RepetitionKey(position)
    let occurrences = moves.filter { RepetitionKey($0.positionBefore) == key }.count + 1
    return occurrences >= 3 ? .drawThreefoldRepetition : .ongoing
  }

  @discardableResult
  public mutating func makeMove(_ move: ChessMove) throws -> PlayedMove {
    let san = try ChessNotation.san(for: move, in: position)
    let played = PlayedMove(move: move, san: san, positionBefore: position)
    position = try position.applying(move)
    moves.append(played)
    return played
  }

  @discardableResult
  public mutating func undo() -> PlayedMove? {
    guard let played = moves.popLast() else { return nil }
    position = played.positionBefore
    return played
  }

  public mutating func restart() {
    position = initialPosition
    moves.removeAll()
  }
}

/// Positions are the same when placement, side to move, castling rights and en-passant
/// availability match. The en-passant target only counts when an en-passant capture is legal.
private struct RepetitionKey: Equatable {
  let position: ChessPosition
  let enPassantTarget: Square?

  init(_ position: ChessPosition) {
    self.position = position
    enPassantTarget = Self.capturableEnPassantTarget(in: position)
  }

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.position.sideToMove == rhs.position.sideToMove
      && lhs.position.castlingRights == rhs.position.castlingRights
      && lhs.enPassantTarget == rhs.enPassantTarget
      && (0..<8).allSatisfy { rank in
        (0..<8).allSatisfy { file in
          let square = Square(file: file, rank: rank)
          return lhs.position[square] == rhs.position[square]
        }
      }
  }

  /// Only a pawn one rank behind the target, or two on its file, can move there, so a position
  /// without one skips move generation.
  private static func capturableEnPassantTarget(in position: ChessPosition) -> Square? {
    guard let target = position.enPassantTarget else { return nil }
    let pawn = Piece(type: .pawn, color: position.sideToMove)
    let behind = target.rank - position.sideToMove.pawnDirection
    let origins = [
      Square(file: target.file - 1, rank: behind),
      Square(file: target.file, rank: behind),
      Square(file: target.file + 1, rank: behind),
      Square(file: target.file, rank: behind - position.sideToMove.pawnDirection),
    ]
    guard origins.contains(where: { position[$0] == pawn }),
      position.legalMoves().contains(where: { $0.to == target && position[$0.from] == pawn })
    else { return nil }
    return target
  }
}
