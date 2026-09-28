import Foundation
import ChessCore

struct GameConfiguration: Hashable, Sendable {
    var difficulty: EngineDifficulty = .medium
    var humanColor: PieceColor = .white
    var initialTime: TimeInterval = 300
    var increment: TimeInterval = 0
}
