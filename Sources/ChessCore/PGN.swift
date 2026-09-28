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
                guard trimmed.hasSuffix("]"), let space = trimmed.firstIndex(of: " ") else { throw PGNError.malformedTag }
                let key = String(trimmed[trimmed.index(after: trimmed.startIndex)..<space])
                let valuePart = trimmed[trimmed.index(after: space)..<trimmed.index(before: trimmed.endIndex)]
                guard valuePart.first == "\"", valuePart.last == "\"" else { throw PGNError.malformedTag }
                tags[key] = String(valuePart.dropFirst().dropLast())
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
            let withoutNumber = token.replacingOccurrences(of: #"^\d+\.(\.\.)?"#, with: "", options: .regularExpression)
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

    private func stripCommentsAndVariations(_ text: String) -> String {
        var result = ""
        var braceDepth = 0
        var variationDepth = 0
        var inLineComment = false
        for character in text {
            if character == "\n" { inLineComment = false }
            if inLineComment { continue }
            if character == ";" { inLineComment = true; continue }
            if character == "{" { braceDepth += 1; continue }
            if character == "}" { braceDepth = max(0, braceDepth - 1); continue }
            if braceDepth > 0 { continue }
            if character == "(" { variationDepth += 1; continue }
            if character == ")" { variationDepth = max(0, variationDepth - 1); continue }
            if variationDepth == 0 { result.append(character) }
        }
        return result
    }
}

public struct PGNExporter: Sendable {
    public init() {}

    public func export(game: ChessGame, tags: [String: String] = [:], result: String? = nil) -> String {
        var allTags = tags
        let finalResult = result ?? resultString(for: game.position.outcome)
        allTags["Result"] = finalResult
        if game.initialPosition != .initial {
            allTags["SetUp"] = "1"
            allTags["FEN"] = game.initialPosition.fen
        }
        let headers = allTags.keys.sorted().map { key in
            let value = allTags[key] ?? ""
            return "[\(key) \"\(value)\"]"
        }.joined(separator: "\n")
        var tokens: [String] = []
        for (index, played) in game.moves.enumerated() {
            if index.isMultiple(of: 2) { tokens.append("\(index / 2 + 1).") }
            tokens.append(played.san)
        }
        tokens.append(finalResult)
        return headers + "\n\n" + tokens.joined(separator: " ")
    }

    private func resultString(for outcome: GameOutcome) -> String {
        switch outcome {
        case .checkmate(winner: .white): "1-0"
        case .checkmate(winner: .black): "0-1"
        case .stalemate, .drawFiftyMove: "1/2-1/2"
        case .ongoing: "*"
        }
    }
}

public struct GameReplay: Sendable {
    public let positions: [ChessPosition]
    public private(set) var index: Int

    public init(game: ChessGame) {
        var positions = game.moves.map(\.positionBefore)
        positions.append(game.position)
        self.positions = positions.isEmpty ? [game.position] : positions
        self.index = self.positions.count - 1
    }

    public var position: ChessPosition { positions[index] }
    public var canGoBack: Bool { index > 0 }
    public var canGoForward: Bool { index + 1 < positions.count }
    public mutating func previous() { if canGoBack { index -= 1 } }
    public mutating func next() { if canGoForward { index += 1 } }
    public mutating func goToStart() { index = 0 }
    public mutating func goToEnd() { index = positions.count - 1 }
}
