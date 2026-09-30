import Foundation

public enum ChessNotation {
  public static func san(for move: ChessMove, in position: ChessPosition) throws -> String {
    guard let piece = position[move.from], position.legalMoves().contains(move) else {
      throw ChessRuleError.illegalMove
    }
    if piece.type == .king && abs(move.to.file - move.from.file) == 2 {
      return try suffix(move.to.file == 6 ? "O-O" : "O-O-O", after: move, in: position)
    }
    let isEnPassant =
      piece.type == .pawn && position[move.to] == nil && move.from.file != move.to.file
    let isCapture = position[move.to] != nil || isEnPassant
    var result = piece.type.sanLetter
    if piece.type == .pawn {
      if isCapture { result += fileName(move.from.file) }
    } else {
      let competitors = position.legalMoves().filter {
        $0.to == move.to && $0.from != move.from && position[$0.from]?.type == piece.type
      }
      if !competitors.isEmpty {
        if competitors.allSatisfy({ $0.from.file != move.from.file }) {
          result += fileName(move.from.file)
        } else if competitors.allSatisfy({ $0.from.rank != move.from.rank }) {
          result += String(move.from.rank + 1)
        } else {
          result += move.from.algebraic
        }
      }
    }
    if isCapture { result += "x" }
    result += move.to.algebraic
    if let promotion = move.promotion { result += "=\(promotion.sanLetter)" }
    return try suffix(result, after: move, in: position)
  }

  public static func move(fromSAN san: String, in position: ChessPosition) -> ChessMove? {
    let normalized = normalize(san)
    return position.legalMoves().first { move in
      guard let generated = try? self.san(for: move, in: position) else { return false }
      return normalize(generated) == normalized
    }
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
