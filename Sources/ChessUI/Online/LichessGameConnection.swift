import ChessContent
import ChessCore
import ChessPlay
import Foundation
import LichessLink

/// One Lichess game as an `OnlineGameConnection`: maps the Board API's game stream to
/// `OnlineGameEvent`s and the player's actions to Board API calls.
struct LichessGameConnection: OnlineGameConnection {
  /// The signed-in user is neither player of the game.
  struct NotAPlayer: Error, Equatable {}

  let client: LichessClient
  let gameID: String
  /// The signed-in user's Lichess id, which is the lowercased username.
  let userID: String
  var localization = Localization()

  var service: String { "lichess" }

  func events() -> AsyncThrowingStream<OnlineGameEvent, Error> {
    let (client, gameID, userID, localization) = (client, gameID, userID, localization)
    return AsyncThrowingStream { continuation in
      let task = Task {
        do {
          // A `gameState` does not say whether the game has a clock; the `gameFull` did.
          var timed = false
          for try await event in try await client.gameStream(id: gameID) {
            guard
              let mapped = try Self.map(
                event,
                userID: userID,
                timed: timed,
                localization: localization
              )
            else { continue }
            if case .started(let start) = mapped { timed = start.timeControl != nil }
            continuation.yield(mapped)
          }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func send(_ action: OnlineAction) async throws {
    switch action {
    case .move(let uci): try await client.move(gameID: gameID, uci: uci)
    case .resign: try await client.resign(gameID: gameID)
    case .abort: try await client.abort(gameID: gameID)
    case .claimVictory: try await client.claimVictory(gameID: gameID)
    // Lichess offers a draw and accepts an offer with the same call.
    case .offerDraw, .acceptDraw: try await client.draw(gameID: gameID, accept: true)
    case .declineDraw: try await client.draw(gameID: gameID, accept: false)
    case .chat(let text): try await client.chat(gameID: gameID, text: text)
    }
  }

  // MARK: - Mapping

  /// Maps one stream event; `timed` is whether the game has a clock. Nil for events the session
  /// does not use (spectator chat).
  /// Throws `NotAPlayer` when `userID` plays neither side of a `gameFull`.
  static func map(
    _ event: LichessGameEvent,
    userID: String,
    timed: Bool,
    localization: Localization
  ) throws -> OnlineGameEvent? {
    switch event {
    case .gameFull(let game):
      return .started(try start(game, userID: userID, localization: localization))
    case .gameState(let state):
      return .state(self.state(state, timed: timed))
    case .chatLine(let username, let text, let room):
      guard room == "player" else { return nil }
      return .chat(OnlineChatLine(username: username, text: text))
    case .opponentGone(let gone, let seconds):
      return gone ? .opponentGone(claimWinIn: seconds.map { .seconds($0) }) : .opponentBack
    }
  }

  static func start(
    _ game: LichessGameFull,
    userID: String,
    localization: Localization
  ) throws -> OnlineGameStart {
    let myColor: PieceColor
    if game.white.id == userID {
      myColor = .white
    } else if game.black.id == userID {
      myColor = .black
    } else {
      throw NotAPlayer()
    }
    return OnlineGameStart(
      gameID: game.id,
      initialFEN: game.initialFen == "startpos" ? nil : game.initialFen,
      white: player(game.white, localization: localization),
      black: player(game.black, localization: localization),
      myColor: myColor,
      timeControl: timeControl(game.clock),
      state: state(game.state, timed: game.clock != nil)
    )
  }

  static func player(_ player: LichessGamePlayer, localization: Localization) -> OnlinePlayer {
    // The AI has no name; Lichess shows it as "Stockfish level N".
    let name =
      player.name ?? player.aiLevel.map { localization.string("online.opponent.stockfish", $0) }
      ?? ""
    return OnlinePlayer(name: name, rating: player.rating)
  }

  /// Whole seconds; nil when the game has no clock (correspondence, unlimited).
  static func timeControl(_ clock: LichessGameClock?) -> TimeControl? {
    clock.map {
      TimeControl(
        initialSeconds: Int((Double($0.initial) / 1000).rounded()),
        incrementSeconds: Int((Double($0.increment) / 1000).rounded())
      )
    }
  }

  /// `timed` is false for games without a clock, whose `wtime` and `btime` mean nothing.
  static func state(_ state: LichessGameState, timed: Bool) -> OnlineGameState {
    OnlineGameState(
      uciMoves: state.moves.split(separator: " ").map(String.init),
      whiteTime: timed ? .milliseconds(state.wtime) : nil,
      blackTime: timed ? .milliseconds(state.btime) : nil,
      status: status(state.status),
      winner: state.winner.map { $0 == .white ? .white : .black },
      whiteOffersDraw: state.wdraw ?? false,
      blackOffersDraw: state.bdraw ?? false
    )
  }

  static func status(_ name: String) -> OnlineGameStatus {
    switch name {
    case "created": .created
    case "started": .started
    case "aborted": .aborted
    case "mate": .mate
    case "resign": .resign
    case "stalemate": .stalemate
    case "timeout": .timeout
    case "draw": .draw
    case "outoftime": .outoftime
    case "cheat": .cheat
    case "noStart": .noStart
    case "unknownFinish": .unknownFinish
    case "variantEnd": .variantEnd
    default: .other(name)
    }
  }
}
