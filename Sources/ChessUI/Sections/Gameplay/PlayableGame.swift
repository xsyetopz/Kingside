import ChessCore
import ChessPlay
import Observation

/// What the shared game panels read and do, so a local and an online game use the same views.
/// Both sessions are `@Observable`, so a view that reads these members updates when they change.
@MainActor
protocol PlayableGame: AnyObject, Observable {
  func apply(_ boardInput: BoardInput)
  func apply(_ action: GameAction)

  var isGameOver: Bool { get }
  var resultTitle: String { get }
  var resultReason: String { get }
  var statusText: String { get }
  var clock: GameClock { get }
  var activeClockColor: PieceColor? { get }
  var materialAdvantage: [PieceColor: Int] { get }
  func isLowTime(_ color: PieceColor) -> Bool

  /// The side whose draw offer the local player has to answer, if any.
  var pendingDrawOffer: PieceColor? { get }
  /// Whether Offer Draw can be sent now.
  var canOfferDraw: Bool { get }
  var canMove: Bool { get }

  /// Whether the game has hints; without them the Hint button and menu item are not shown.
  var supportsHint: Bool { get }
  var isLoadingHint: Bool { get }
  /// Whether the game has takebacks; without them the Takeback button and menu item are not shown.
  var supportsTakeback: Bool { get }
  var canTakeback: Bool { get }
  /// Whether a finished game can be replayed at once; without it Rematch is not shown.
  var supportsRematch: Bool { get }
  /// The bot's latest chat line. Games without a bot have none.
  var botMessage: String? { get }
}

extension PlayableGame {
  var botMessage: String? { nil }
}

extension GameSession: PlayableGame {
  var canOfferDraw: Bool { !isGameOver && pendingDrawOffer == nil }
  var supportsHint: Bool { true }
  var supportsTakeback: Bool { true }
  var supportsRematch: Bool { true }
}

extension OnlineGameSession: PlayableGame {
  var canOfferDraw: Bool {
    start != nil && !isGameOver && pendingDrawOffer == nil && !myDrawOfferPending
  }
  var supportsHint: Bool { false }
  var isLoadingHint: Bool { false }
  var supportsTakeback: Bool { false }
  var canTakeback: Bool { false }
  var supportsRematch: Bool { false }
}
