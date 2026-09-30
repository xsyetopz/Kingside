import Foundation
import ChessCore

/// `puzzles.json` entry, from the Lichess puzzle database (CC0).
///
/// Lichess semantics: `fen` is the position before the opponent's move, and `moves[0]` is
/// that opponent move. The solver then plays `moves[1]`, `moves[3]`, ... and the opponent
/// replies with `moves[2]`, `moves[4]`, ... In the JSON, `moves` and `themes` are
/// space-separated strings to keep the file small.
public struct Puzzle: Decodable, Hashable, Identifiable, Sendable {
  public let id: String
  public let fen: String
  public let moves: [ChessMove]
  public let rating: Int
  public let themes: [String]

  private enum CodingKeys: String, CodingKey { case id, fen, moves, rating, themes }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    fen = try container.decode(String.self, forKey: .fen)
    rating = try container.decode(Int.self, forKey: .rating)
    themes = try container.decode(String.self, forKey: .themes).split(separator: " ").map(
      String.init
    )
    let uciMoves = try container.decode(String.self, forKey: .moves).split(separator: " ")
    moves = try uciMoves.map { uci in
      guard let move = ChessMove(uci: String(uci)) else {
        throw DecodingError.dataCorruptedError(
          forKey: .moves,
          in: container,
          debugDescription: "Bad UCI move \(uci)"
        )
      }
      return move
    }
  }

  /// The position before the opponent's first move.
  public func initialPosition() throws -> ChessPosition { try ChessPosition(fen: fen) }
}
