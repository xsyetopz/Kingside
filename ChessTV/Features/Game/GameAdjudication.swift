import Foundation
import ChessCore

/// Pure game-end and draw-offer rules used by `GameViewModel`.
enum GameAdjudication {
    /// Result for a finished `GameOutcome`; nil while the game is ongoing.
    static func result(for outcome: GameOutcome) -> (GameResult, GameTermination)? {
        switch outcome {
        case .ongoing: nil
        case .checkmate(let winner): (.win(for: winner), .checkmate)
        case .stalemate: (.draw, .stalemate)
        case .drawFiftyMove: (.draw, .fiftyMoveRule)
        case .drawThreefoldRepetition: (.draw, .repetition)
        case .drawInsufficientMaterial: (.draw, .insufficientMaterial)
        }
    }

    /// `flagged` ran out of time: the opponent wins, unless the opponent cannot mate at all.
    static func timeout(flagged: PieceColor, in position: ChessPosition) -> (GameResult, GameTermination) {
        let opponent = flagged.opponent
        guard hasMatingMaterial(opponent, in: position) else { return (.draw, .timeoutVsInsufficientMaterial) }
        return (.win(for: opponent), .timeout)
    }

    /// False for a lone king, king and bishop, or king and knight.
    static func hasMatingMaterial(_ color: PieceColor, in position: ChessPosition) -> Bool {
        let pieces = position.board.values.filter { $0.color == color && $0.type != .king }
        if pieces.contains(where: { [.pawn, .rook, .queen].contains($0.type) }) { return true }
        return pieces.count >= 2
    }
}

/// Decides whether a bot accepts a draw offer.
enum DrawOfferPolicy {
    /// Bots accept from this ply on when they are not clearly better.
    static let minimumPly = 30
    /// Largest advantage, in centipawns from the bot's side, at which it still accepts.
    static let maximumAdvantage = 30
    /// "Near zero" for low-material positions.
    static let equalMargin = 50
    /// Total material of both sides (pawn 1, minor 3, rook 5, queen 9) counted as very low.
    static let lowMaterialLimit = 12

    /// `evaluation` is from White's point of view, as `ChessEngine.analyze` reports it.
    static func botAccepts(evaluation: Evaluation, botColor: PieceColor, plyCount: Int, position: ChessPosition) -> Bool {
        let botScore = score(evaluation, for: botColor)
        if plyCount >= minimumPly && botScore <= maximumAdvantage { return true }
        let material = Material.points(.white, in: position) + Material.points(.black, in: position)
        return material <= lowMaterialLimit && abs(botScore) <= equalMargin
    }

    /// Centipawns from `color`'s side; forced mates count as a decisive score.
    static func score(_ evaluation: Evaluation, for color: PieceColor) -> Int {
        let whiteScore: Int
        if let mate = evaluation.mateIn { whiteScore = mate > 0 ? 100_000 : -100_000 }
        else { whiteScore = evaluation.centipawns }
        return color == .white ? whiteScore : -whiteScore
    }
}

/// Material counting for player bars.
enum Material {
    static func value(_ type: PieceType) -> Int {
        switch type {
        case .pawn: 1
        case .knight, .bishop: 3
        case .rook: 5
        case .queen: 9
        case .king: 0
        }
    }

    private static let startingCounts: [PieceType: Int] = [.pawn: 8, .knight: 2, .bishop: 2, .rook: 2, .queen: 1]

    /// Material of `color` still on the board.
    static func points(_ color: PieceColor, in position: ChessPosition) -> Int {
        position.board.values.filter { $0.color == color }.reduce(0) { $0 + value($1.type) }
    }

    /// Pieces of `color` missing from a standard starting set (captured by the opponent).
    static func missing(_ color: PieceColor, in position: ChessPosition) -> [PieceType] {
        startingCounts.keys.sorted { value($0) < value($1) }.flatMap { type -> [PieceType] in
            let onBoard = position.board.values.filter { $0 == Piece(type: type, color: color) }.count
            return Array(repeating: type, count: max(0, startingCounts[type, default: 0] - onBoard))
        }
    }
}

/// Picks the sound for a played move: check, promotion, castling, capture, else a plain move.
enum MoveSound {
    static func effect(for move: ChessMove, before: ChessPosition, after: ChessPosition) -> SoundEffect {
        if after.isInCheck(after.sideToMove) { return .check }
        if move.promotion != nil { return .promote }
        if before[move.from]?.type == .king && abs(move.to.file - move.from.file) == 2 { return .castle }
        return isCapture(move, before: before) ? .capture : .move
    }

    /// True for normal captures and en passant (a pawn moving diagonally).
    static func isCapture(_ move: ChessMove, before: ChessPosition) -> Bool {
        let mover = before[move.from]
        return before[move.to] != nil || (mover?.type == .pawn && move.from.file != move.to.file)
    }
}
