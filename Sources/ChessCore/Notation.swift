import Foundation

public enum ChessNotation {
  public static func san(for move: ChessMove, in position: ChessPosition) throws -> String {
    try san(for: move, in: position, legalMoves: position.legalMoves())
  }

  public static func move(fromSAN san: String, in position: ChessPosition) -> ChessMove? {
    let normalized = normalize(san)
    let legalMoves = position.legalMoves()
    return legalMoves.first { move in
      guard let generated = try? self.san(for: move, in: position, legalMoves: legalMoves) else {
        return false
      }
      return normalize(generated) == normalized
    }
  }

  /// `legalMoves` are the legal moves of `position`.
  private static func san(
    for move: ChessMove,
    in position: ChessPosition,
    legalMoves: [ChessMove]
  ) throws -> String {
    guard let piece = position[move.from], legalMoves.contains(move) else {
      throw ChessRuleError.illegalMove
    }
    if let castling = castlingSAN(for: move, by: piece) {
      return try suffix(castling, after: move, in: position)
    }
    // A pawn changing file always captures; the target square is empty only en passant.
    let isCapture =
      position[move.to] != nil || (piece.type == .pawn && move.from.file != move.to.file)
    var result = piece.type.sanLetter
    result += disambiguation(
      for: move,
      by: piece,
      isCapture: isCapture,
      in: position,
      legalMoves: legalMoves
    )
    if isCapture { result += "x" }
    result += move.to.algebraic
    if let promotion = move.promotion { result += "=\(promotion.sanLetter)" }
    return try suffix(result, after: move, in: position)
  }

  /// `O-O` or `O-O-O` when the move is a castling king move, `nil` otherwise.
  private static func castlingSAN(for move: ChessMove, by piece: Piece) -> String? {
    guard piece.type == .king, abs(move.to.file - move.from.file) == 2 else { return nil }
    return move.to.file == 6 ? "O-O" : "O-O-O"
  }

  /// The origin written before the target: a capturing pawn's file, or for another piece the
  /// file, rank, or square that tells it apart from same-type pieces reaching the same target.
  private static func disambiguation(
    for move: ChessMove,
    by piece: Piece,
    isCapture: Bool,
    in position: ChessPosition,
    legalMoves: [ChessMove]
  ) -> String {
    if piece.type == .pawn { return isCapture ? fileName(move.from.file) : "" }
    let competitors = legalMoves.filter {
      $0.to == move.to && $0.from != move.from && position[$0.from] == piece
    }
    if competitors.isEmpty { return "" }
    if competitors.allSatisfy({ $0.from.file != move.from.file }) {
      return fileName(move.from.file)
    }
    if competitors.allSatisfy({ $0.from.rank != move.from.rank }) {
      return String(move.from.rank + 1)
    }
    return move.from.algebraic
  }

  private static func suffix(
    _ base: String,
    after move: ChessMove,
    in position: ChessPosition
  ) throws -> String {
    let next = try position.applying(move)
    switch next.outcome {
    case .checkmate: return base + "#"
    default: return next.isInCheck(next.sideToMove) ? base + "+" : base
    }
  }

  private static func normalize(_ san: String) -> String {
    san.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "0-0-0", with: "O-O-O")
      .replacingOccurrences(of: "0-0", with: "O-O")
      .replacingOccurrences(of: "+", with: "")
      .replacingOccurrences(of: "#", with: "")
      .replacingOccurrences(of: "!", with: "")
      .replacingOccurrences(of: "?", with: "")
  }

  private static func fileName(_ file: Int) -> String {
    guard let scalar = UnicodeScalar(file + 97) else { return "?" }
    return String(Character(scalar))
  }
}
