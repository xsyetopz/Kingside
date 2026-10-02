import Foundation

public enum PieceColor: String, Codable, Sendable, CaseIterable {
  case white, black

  public var opponent: Self { self == .white ? .black : .white }
  var pawnDirection: Int { self == .white ? 1 : -1 }
}

public enum PieceType: String, Codable, Sendable, CaseIterable {
  case pawn, knight, bishop, rook, queen, king

  var sanLetter: String {
    switch self {
    case .pawn: ""
    case .knight: "N"
    case .bishop: "B"
    case .rook: "R"
    case .queen: "Q"
    case .king: "K"
    }
  }
}

public struct Piece: Codable, Equatable, Hashable, Sendable {
  public let type: PieceType
  public let color: PieceColor

  public init(type: PieceType, color: PieceColor) {
    self.type = type
    self.color = color
  }
}

public struct Square: Codable, Equatable, Hashable, Sendable, Comparable, CustomStringConvertible {
  public let file: Int
  public let rank: Int

  public init(file: Int, rank: Int) {
    self.file = file
    self.rank = rank
  }

  public init?(algebraic: String) {
    let characters = Array(algebraic.lowercased())
    guard characters.count == 2,
      let fileScalar = characters[0].asciiValue,
      let rank = Int(String(characters[1])),
      (97...104).contains(fileScalar), (1...8).contains(rank)
    else { return nil }
    self.init(file: Int(fileScalar - 97), rank: rank - 1)
  }

  var isValid: Bool { (0..<8).contains(file) && (0..<8).contains(rank) }
  public var algebraic: String {
    guard isValid, let scalar = UnicodeScalar(file + 97) else { return "??" }
    return "\(Character(scalar))\(rank + 1)"
  }
  public var description: String { algebraic }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rank == rhs.rank ? lhs.file < rhs.file : lhs.rank < rhs.rank
  }
}

public struct ChessMove: Codable, Equatable, Hashable, Sendable {
  public let from: Square
  public let to: Square
  public let promotion: PieceType?

  public init(from: Square, to: Square, promotion: PieceType? = nil) {
    self.from = from
    self.to = to
    self.promotion = promotion
  }

  public init?(uci: String) {
    guard uci.count == 4 || uci.count == 5 else { return nil }
    let chars = Array(uci)
    guard let from = Square(algebraic: String(chars[0...1])),
      let to = Square(algebraic: String(chars[2...3]))
    else { return nil }
    let promotion: PieceType?
    if chars.count == 5 {
      switch chars[4].lowercased() {
      case "q": promotion = .queen
      case "r": promotion = .rook
      case "b": promotion = .bishop
      case "n": promotion = .knight
      default: return nil
      }
    } else {
      promotion = nil
    }
    self.init(from: from, to: to, promotion: promotion)
  }

  public var uci: String {
    let suffix: String
    switch promotion {
    case .queen: suffix = "q"
    case .rook: suffix = "r"
    case .bishop: suffix = "b"
    case .knight: suffix = "n"
    default: suffix = ""
    }
    return from.algebraic + to.algebraic + suffix
  }
}

public struct CastlingRights: OptionSet, Codable, Hashable, Sendable {
  public let rawValue: Int
  public init(rawValue: Int) { self.rawValue = rawValue }

  public static let whiteKingSide = Self(rawValue: 1 << 0)
  public static let whiteQueenSide = Self(rawValue: 1 << 1)
  public static let blackKingSide = Self(rawValue: 1 << 2)
  public static let blackQueenSide = Self(rawValue: 1 << 3)
  public static let all: Self = [.whiteKingSide, .whiteQueenSide, .blackKingSide, .blackQueenSide]
}

public enum GameOutcome: Codable, Equatable, Sendable {
  case ongoing
  case checkmate(winner: PieceColor)
  case stalemate
  case drawFiftyMove
  case drawThreefoldRepetition
  case drawInsufficientMaterial

  public var isDraw: Bool {
    switch self {
    case .stalemate, .drawFiftyMove, .drawThreefoldRepetition, .drawInsufficientMaterial: true
    case .ongoing, .checkmate: false
    }
  }
}

public enum ChessRuleError: Error, Equatable, LocalizedError {
  case invalidFEN
  case illegalMove

  public var errorDescription: String? {
    switch self {
    case .invalidFEN: "The chess position is invalid."
    case .illegalMove: "That move is not legal."
    }
  }
}
