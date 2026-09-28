import Foundation

public extension ChessPosition {
    init(fen: String) throws {
        let fields = fen.split(separator: " ")
        guard fields.count >= 4 else { throw ChessRuleError.invalidFEN }
        let rows = fields[0].split(separator: "/")
        guard rows.count == 8 else { throw ChessRuleError.invalidFEN }
        var board: [Square: Piece] = [:]
        for (rowIndex, row) in rows.enumerated() {
            var file = 0
            for character in row {
                if let empty = character.wholeNumberValue {
                    file += empty
                    continue
                }
                guard file < 8, let piece = Self.piece(fromFEN: character) else { throw ChessRuleError.invalidFEN }
                board[Square(file: file, rank: 7 - rowIndex)] = piece
                file += 1
            }
            guard file == 8 else { throw ChessRuleError.invalidFEN }
        }
        guard let side = PieceColor(fen: String(fields[1])) else { throw ChessRuleError.invalidFEN }
        var rights: CastlingRights = []
        if fields[2].contains("K") { rights.insert(.whiteKingSide) }
        if fields[2].contains("Q") { rights.insert(.whiteQueenSide) }
        if fields[2].contains("k") { rights.insert(.blackKingSide) }
        if fields[2].contains("q") { rights.insert(.blackQueenSide) }
        let ep: Square?
        if fields[3] == "-" { ep = nil }
        else {
            guard let parsed = Square(algebraic: String(fields[3])) else { throw ChessRuleError.invalidFEN }
            ep = parsed
        }
        let halfmove = fields.count > 4 ? Int(fields[4]) ?? 0 : 0
        let fullmove = fields.count > 5 ? Int(fields[5]) ?? 1 : 1
        self.init(board: board, sideToMove: side, castlingRights: rights, enPassantTarget: ep, halfmoveClock: halfmove, fullmoveNumber: fullmove)
    }

    var fen: String {
        var rows: [String] = []
        for rank in stride(from: 7, through: 0, by: -1) {
            var row = ""
            var empty = 0
            for file in 0..<8 {
                if let piece = board[Square(file: file, rank: rank)] {
                    if empty > 0 { row += String(empty); empty = 0 }
                    row.append(piece.fenCharacter)
                } else { empty += 1 }
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
        return "\(rows.joined(separator: "/")) \(sideToMove == .white ? "w" : "b") \(castling) \(enPassantTarget?.algebraic ?? "-") \(halfmoveClock) \(fullmoveNumber)"
    }

    private static func piece(fromFEN character: Character) -> Piece? {
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
        if fen == "w" { self = .white }
        else if fen == "b" { self = .black }
        else { return nil }
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
