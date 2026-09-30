import ChessCore
import Foundation

public struct ChessComImportedGame: Equatable, Sendable {
    public var source: ChessComGame
    public var pgn: PGNGame
    public var game: ChessGame
}

public enum ChessComImportResult: Equatable, Sendable {
    case imported(ChessComImportedGame)
    /// The game uses `rules` other than standard chess, which `ChessCore` cannot replay.
    case skipped(ChessComGame)
}

public struct ChessComGameImporter: Sendable {
    public init() {}

    /// Throws the `PGNParser` error when a standard game's PGN cannot be parsed or replayed.
    public func importGame(_ source: ChessComGame) throws -> ChessComImportResult {
        guard source.rules.lowercased() == "chess" else { return .skipped(source) }
        let parser = PGNParser()
        let pgn = try parser.parse(source.pgn)
        let game = try parser.chessGame(from: pgn)
        return .imported(ChessComImportedGame(source: source, pgn: pgn, game: game))
    }
}
