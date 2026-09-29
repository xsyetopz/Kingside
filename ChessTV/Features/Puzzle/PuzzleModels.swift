import Foundation
import ChessCore

// Puzzle data bundled in Resources/Puzzles.json (Lichess puzzle database, CC0).
// Lichess semantics: `fen` is the position BEFORE the opponent's move; `moves[0]` is that
// opponent move (auto-played), then the solver plays moves[1], moves[3], ... and the opponent
// replies with moves[2], moves[4], ...
// In the JSON, `moves` and `themes` are space-separated strings to keep the file small.

struct Puzzle: Identifiable, Hashable, Sendable {
    let id: String
    let fen: String
    let moves: [ChessMove]
    let rating: Int
    let themes: [String]

    /// Position before the opponent's first move, or nil when the FEN does not parse.
    var initialPosition: ChessPosition? { try? ChessPosition(fen: fen) }
}

extension Puzzle: Decodable {
    private enum CodingKeys: String, CodingKey { case id, fen, moves, rating, themes }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        fen = try container.decode(String.self, forKey: .fen)
        rating = try container.decode(Int.self, forKey: .rating)
        themes = try container.decode(String.self, forKey: .themes).split(separator: " ").map(String.init)
        let uciMoves = try container.decode(String.self, forKey: .moves).split(separator: " ")
        moves = try uciMoves.map { uci in
            guard let move = ChessMove(uci: String(uci)) else {
                throw DecodingError.dataCorruptedError(forKey: .moves, in: container, debugDescription: "Bad UCI move \(uci)")
            }
            return move
        }
    }
}

/// The bundled puzzle set, decoded once on first use and sorted by rating.
enum PuzzleLibrary {
    static let all: [Puzzle] = load(from: Bundle.main)

    static func load(from bundle: Bundle) -> [Puzzle] {
        guard let url = bundle.url(forResource: "Puzzles", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let puzzles = try? JSONDecoder().decode([Puzzle].self, from: data)
        else { return [] }
        return puzzles.sorted { $0.rating < $1.rating }
    }
}

enum PuzzleRushMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case threeMinutes, fiveMinutes, survival

    var id: String { rawValue }

    var title: String {
        switch self {
        case .threeMinutes: "3 Minutes"
        case .fiveMinutes: "5 Minutes"
        case .survival: "Survival"
        }
    }

    var icon: String {
        switch self {
        case .threeMinutes: "bolt.fill"
        case .fiveMinutes: "timer"
        case .survival: "heart.fill"
        }
    }

    /// Countdown length; nil for Survival (no clock).
    var timeLimit: TimeInterval? {
        switch self {
        case .threeMinutes: 180
        case .fiveMinutes: 300
        case .survival: nil
        }
    }
}
