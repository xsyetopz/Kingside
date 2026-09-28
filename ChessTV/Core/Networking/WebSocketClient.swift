import Foundation
import ChessCore

protocol WebSocketClient: Sendable {
    func connect(to url: URL) async throws
    func send(_ data: Data) async throws
    func messages() -> AsyncThrowingStream<Data, Error>
    func disconnect() async
}

protocol GameService: Sendable {
    func createGame(configuration: GameConfiguration) async throws -> ChessGame
    func makeMove(_ move: ChessMove) async throws
    func observeGame() async throws -> AsyncStream<GameEvent>
}

enum GameEvent: Sendable {
    case position(ChessPosition)
    case move(ChessMove)
    case finished(GameOutcome)
}

actor LocalGameService: GameService {
    private var game = ChessGame()
    private var continuation: AsyncStream<GameEvent>.Continuation?

    func createGame(configuration: GameConfiguration) async throws -> ChessGame {
        game = ChessGame()
        return game
    }

    func makeMove(_ move: ChessMove) async throws {
        try game.makeMove(move)
        continuation?.yield(.move(move))
        continuation?.yield(.position(game.position))
        if game.position.outcome.isFinished { continuation?.yield(.finished(game.position.outcome)) }
    }

    func observeGame() async throws -> AsyncStream<GameEvent> {
        let pair = AsyncStream<GameEvent>.makeStream()
        continuation = pair.continuation
        pair.continuation.yield(.position(game.position))
        return pair.stream
    }
}
