import Foundation

public extension ChessPosition {
  init(fen: String) throws {
    let fields = fen.split(separator: " ")
    guard (4...6).contains(fields.count) else { throw ChessRuleError.invalidFEN }
    let rows = fields[0].split(separator: "/")
    guard rows.count == 8 else { throw ChessRuleError.invalidFEN }
    var board: [Square: Piece] = [:]
    for (rowIndex, row) in rows.enumerated() {
      var file = 0
      var previousWasDigit = false
      for character in row {
        if let empty = character.asciiValue.flatMap(Self.emptyRun(fromFEN:)) {
          guard !previousWasDigit else { throw ChessRuleError.invalidFEN }
          file += empty
          previousWasDigit = true
          continue
        }
        previousWasDigit = false
        guard file < 8, let piece = Self.piece(fromFEN: character) else {
          throw ChessRuleError.invalidFEN
        }
        board[Square(file: file, rank: 7 - rowIndex)] = piece
        file += 1
      }
      guard file == 8 else { throw ChessRuleError.invalidFEN }
    }
    guard let side = PieceColor(fen: String(fields[1])) else { throw ChessRuleError.invalidFEN }
    guard let rights = Self.castlingRights(fromFEN: fields[2]) else {
      throw ChessRuleError.invalidFEN
    }
    let ep: Square?
    if fields[3] == "-" {
      ep = nil
    } else {
      guard let parsed = Square(algebraic: String(fields[3])),
        Self.isEnPassantTarget(parsed, sideToMove: side, board: board)
      else {
        throw ChessRuleError.invalidFEN
      }
      ep = parsed
    }
    var halfmove = 0
    if fields.count > 4 {
      guard let clock = Self.clock(fromFEN: fields[4]) else { throw ChessRuleError.invalidFEN }
      halfmove = clock
    }
    var fullmove = 1
    if fields.count > 5 {
      guard let number = Self.clock(fromFEN: fields[5]) else { throw ChessRuleError.invalidFEN }
      fullmove = number
    }
    self.init(
      board: board,
      sideToMove: side,
      castlingRights: rights,
      enPassantTarget: ep,
      halfmoveClock: halfmove,
      fullmoveNumber: fullmove
    )
    guard isSupportedByEngine else { throw ChessRuleError.invalidFEN }
  }

  /// Whether the engine can load and search this position: either clock must survive adding 1,
  /// and the engine's board must support it (`EngineBoard.isSupported`).
  var isSupportedByEngine: Bool {
    (0..<Int.max).contains(halfmoveClock) && (1..<Int.max).contains(fullmoveNumber)
      && EngineBoard(self, plyCapacity: 1).isSupported
  }

  var fen: String {
    var rows: [String] = []
    for rank in stride(from: 7, through: 0, by: -1) {
      var row = ""
      var empty = 0
      for file in 0..<8 {
        if let piece = self[Square(file: file, rank: rank)] {
          if empty > 0 { row += String(empty); empty = 0 }
          row.append(piece.fenCharacter)
        } else {
          empty += 1
        }
      }
      if empty > 0 { row += String(empty) }
      rows.append(row)
    }
    var castling = ""
    if castlingRights.contains(.whiteKingSide) { castling += "K" }
    if castlingRights.contains(.whiteQueenSide) { castling += "Q" }
    if castlingRights.contains(.blackKingSide) { castling += "k" }
    if castlingRights.contains(.blackQueenSide) { castling += "q" }
    if castling.isEmpty { castling = "-" }
    let placement = rows.joined(separator: "/")
    let side = sideToMove == .white ? "w" : "b"
    let enPassant = enPassantTarget?.algebraic ?? "-"
    return "\(placement) \(side) \(castling) \(enPassant) \(halfmoveClock) \(fullmoveNumber)"
  }

  /// `-`, or a non-empty subsequence of `KQkq` in that order.
  private static func castlingRights(fromFEN field: Substring) -> CastlingRights? {
    if field == "-" { return [] }
    let order: [(Character, CastlingRights)] = [
      ("K", .whiteKingSide), ("Q", .whiteQueenSide), ("k", .blackKingSide), ("q", .blackQueenSide),
    ]
    var rights: CastlingRights = []
    var next = order.startIndex
    for character in field {
      guard let match = order[next...].firstIndex(where: { $0.0 == character }) else { return nil }
      rights.insert(order[match].1)
      next = match + 1
    }
    return rights.isEmpty ? nil : rights
  }

  /// The length of an empty run written as one ASCII digit 1-8.
  private static func emptyRun(fromFEN ascii: UInt8) -> Int? {
    (0x31...0x38).contains(ascii) ? Int(ascii - 0x30) : nil
  }

  /// The target is empty, the pawn that just double-pushed stands in front of it (an opponent of
  /// the side to move), and the square that pawn came from is empty.
  private static func isEnPassantTarget(
    _ target: Square,
    sideToMove: PieceColor,
    board: [Square: Piece]
  ) -> Bool {
    let pushDirection = sideToMove.opponent.pawnDirection
    guard target.rank == (sideToMove == .white ? 5 : 2) else { return false }
    let pawn = Square(file: target.file, rank: target.rank + pushDirection)
    let origin = Square(file: target.file, rank: target.rank - pushDirection)
    return board[target] == nil && board[origin] == nil
      && board[pawn] == Piece(type: .pawn, color: sideToMove.opponent)
  }

  /// A non-negative decimal number written with ASCII digits only.
  private static func clock(fromFEN field: Substring) -> Int? {
    guard field.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }) else { return nil }
    return Int(field)
  }

  private static func piece(fromFEN character: Character) -> Piece? {
    guard character.isASCII else { return nil }
    let type: PieceType
    switch character.lowercased() {
    case "p": type = .pawn
    case "n": type = .knight
    case "b": type = .bishop
    case "r": type = .rook
    case "q": type = .queen
    case "k": type = .king
    default: return nil
    }
    return Piece(type: type, color: character.isUppercase ? .white : .black)
  }
}

private extension PieceColor {
  init?(fen: String) {
    if fen == "w" { self = .white } else if fen == "b" { self = .black } else { return nil }
  }
}

private extension Piece {
  var fenCharacter: Character {
    let character: Character
    switch type {
    case .pawn: character = "p"
    case .knight: character = "n"
    case .bishop: character = "b"
    case .rook: character = "r"
    case .queen: character = "q"
    case .king: character = "k"
    }
    return color == .white ? Character(character.uppercased()) : character
  }
}
