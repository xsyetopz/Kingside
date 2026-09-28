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
