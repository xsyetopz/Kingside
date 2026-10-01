import Foundation

public struct PGNGame: Codable, Equatable, Sendable {
  public var tags: [String: String]
  public var moves: [String]
  public var result: String

  public init(tags: [String: String] = [:], moves: [String] = [], result: String = "*") {
    self.tags = tags
    self.moves = moves
    self.result = result
  }
}

public enum PGNError: Error, Equatable {
  case malformedTag
  case illegalMove(String, ply: Int)
}

public struct PGNParser: Sendable {
  public init() {}

  public func parse(_ text: String) throws -> PGNGame {
    var tags: [String: String] = [:]
    var moveTextLines: [String] = []
    for line in text.components(separatedBy: .newlines) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("[") {
        guard trimmed.hasSuffix("]"), let space = trimmed.firstIndex(of: " ") else {
          throw PGNError.malformedTag
        }
        let key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<space])
        let valuePart = trimmed[
          trimmed.index(after: space)..<trimmed.index(before: trimmed.endIndex)
        ]
        guard valuePart.first == "\"", valuePart.last == "\"" else { throw PGNError.malformedTag }
        tags[key] = unescapedTagValue(valuePart.dropFirst().dropLast())
      } else if !trimmed.isEmpty {
        moveTextLines.append(trimmed)
      }
    }
    let cleaned = stripCommentsAndVariations(moveTextLines.joined(separator: "\n"))
    var moves: [String] = []
    var result = "*"
    for raw in cleaned.split(whereSeparator: { $0.isWhitespace }) {
      let token = String(raw)
      if ["1-0", "0-1", "1/2-1/2", "*"].contains(token) { result = token; continue }
      if token.hasPrefix("$") { continue }
      let withoutNumber = token.replacingOccurrences(
        of: #"^\d+\.(\.\.)?"#,
        with: "",
        options: .regularExpression
      )
      if !withoutNumber.isEmpty { moves.append(withoutNumber) }
    }
    return PGNGame(tags: tags, moves: moves, result: result)
  }

  public func chessGame(from pgn: PGNGame) throws -> ChessGame {
    let start = try pgn.tags["FEN"].map(ChessPosition.init(fen:)) ?? .initial
    var game = ChessGame(position: start)
    for (index, san) in pgn.moves.enumerated() {
      guard let move = ChessNotation.move(fromSAN: san, in: game.position) else {
        throw PGNError.illegalMove(san, ply: index + 1)
      }
      try game.makeMove(move)
    }
    return game
  }

  private func unescapedTagValue(_ escaped: Substring) -> String {
    var value = ""
    var characters = escaped.makeIterator()
    while let character = characters.next() {
      guard character == "\\" else {
        value.append(character)
        continue
      }
      guard let escapedCharacter = characters.next() else {
        value.append(character)
        break
      }
      // A backslash before anything but `"` or `\` is not an escape; keep it literally.
      if escapedCharacter != "\"" && escapedCharacter != "\\" { value.append(character) }
      value.append(escapedCharacter)
    }
    return value
  }

  private func stripCommentsAndVariations(_ text: String) -> String {
    stripVariations(stripComments(text))
  }

  /// Removes `;` comments up to the line break and `{}` comments. A `;` starts a line comment
  /// even inside braces, and a `}` inside that line comment does not close the brace.
  private func stripComments(_ text: String) -> String {
    var result = ""
    var braceDepth = 0
    var inLineComment = false
    for character in text {
      if character == "\n" { inLineComment = false }
      if inLineComment { continue }
      if character == ";" { inLineComment = true; continue }
      if character == "{" { braceDepth += 1; continue }
      if character == "}" { braceDepth = max(0, braceDepth - 1); continue }
      if braceDepth == 0 { result.append(character) }
    }
    return result
  }

  /// Removes `()` variations, nested to any depth.
  private func stripVariations(_ text: String) -> String {
    var result = ""
    var variationDepth = 0
    for character in text {
      if character == "(" { variationDepth += 1; continue }
      if character == ")" { variationDepth = max(0, variationDepth - 1); continue }
      if variationDepth == 0 { result.append(character) }
    }
    return result
  }
}

public struct PGNExporter: Sendable {
  public init() {}

  public func export(game: ChessGame, tags: [String: String] = [:], result: String? = nil) -> String
  {
    var allTags = tags
    let finalResult = result ?? resultString(for: game.outcome)
    allTags["Result"] = finalResult
    if game.initialPosition != .initial {
      allTags["SetUp"] = "1"
      allTags["FEN"] = game.initialPosition.fen
    }
    let headers = allTags.keys.sorted().map { key in
      let value = allTags[key] ?? ""
      return "[\(key) \"\(escapedTagValue(value))\"]"
    }.joined(separator: "\n")
    let blackMovesFirst = game.initialPosition.sideToMove == .black
    var tokens: [String] = []
    for (index, played) in game.moves.enumerated() {
      let ply = blackMovesFirst ? index + 1 : index
      let moveNumber = game.initialPosition.fullmoveNumber + ply / 2
      if ply.isMultiple(of: 2) {
        tokens.append("\(moveNumber).")
      } else if index == 0 {
        tokens.append("\(moveNumber)...")
      }
      tokens.append(played.san)
    }
    tokens.append(finalResult)
    return headers + "\n\n" + tokens.joined(separator: " ")
  }

  private func escapedTagValue(_ value: String) -> String {
    // PGN string tokens cannot contain line breaks, so each one becomes a space.
    String(value.map { $0.isNewline ? " " : $0 })
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }

  private func resultString(for outcome: GameOutcome) -> String {
    switch outcome {
    case .checkmate(winner: .white): "1-0"
    case .checkmate(winner: .black): "0-1"
    case .stalemate, .drawFiftyMove, .drawThreefoldRepetition, .drawInsufficientMaterial: "1/2-1/2"
    case .ongoing: "*"
    }
  }
}
