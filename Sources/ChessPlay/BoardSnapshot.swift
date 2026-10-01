import ChessCore
import Foundation

/// Everything the board scene draws, as ids and values. The scene resolves colors and assets
/// from `ChessContent` and the settings; it never changes chess state and sends `BoardInput`s.
/// Sessions build it through `MoveInput.snapshot(of:canMove:hint:badge:)`.
public struct BoardSnapshot: Equatable, Sendable {
  public var pieces: [Square: Piece]
  /// The color at the bottom of the board.
  public var orientation: PieceColor
  public var focusedSquare: Square
  public var selectedSquare: Square?
  /// Destinations of the selected piece; empty without a selection.
  public var legalTargets: Set<Square>
  public var lastMove: ChessMove?
  /// The king of the side to move when it is in check.
  public var checkSquare: Square?
  /// The suggested move from a `.requestHint` action.
  public var hint: BoardArrow?
  /// Set while the player picks a promotion piece.
  public var pendingPromotion: PendingPromotion?
  /// False while the player may not move, such as on the bot's turn, while the promotion
  /// picker or a draw offer is open, or after the game ended.
  public var isInputEnabled: Bool
  /// Puzzles: the correct or incorrect marker on the square of the solver's last move.
  public var badge: SquareBadge?

  public init(
    pieces: [Square: Piece],
    orientation: PieceColor,
    focusedSquare: Square,
    selectedSquare: Square?,
    legalTargets: Set<Square>,
    lastMove: ChessMove?,
    checkSquare: Square?,
    hint: BoardArrow?,
    pendingPromotion: PendingPromotion?,
    isInputEnabled: Bool,
    badge: SquareBadge? = nil
  ) {
    self.pieces = pieces
    self.orientation = orientation
    self.focusedSquare = focusedSquare
    self.selectedSquare = selectedSquare
    self.legalTargets = legalTargets
    self.lastMove = lastMove
    self.checkSquare = checkSquare
    self.hint = hint
    self.pendingPromotion = pendingPromotion
    self.isInputEnabled = isInputEnabled
    self.badge = badge
  }
}

/// A correct or incorrect marker drawn on a square's corner.
public struct SquareBadge: Hashable, Sendable {
  public enum Kind: Hashable, Sendable { case correct, incorrect }

  public var square: Square
  public var kind: Kind

  public init(square: Square, kind: Kind) {
    self.square = square
    self.kind = kind
  }
}

/// An arrow from one square to another; its color comes from the theme.
public struct BoardArrow: Hashable, Sendable {
  public var from: Square
  public var to: Square

  public init(from: Square, to: Square) {
    self.from = from
    self.to = to
  }
}

/// A pawn move waiting for the promotion piece.
public struct PendingPromotion: Equatable, Sendable {
  public var from: Square
  public var to: Square
  public var color: PieceColor
  /// Pieces offered by the picker, in the order of the legal moves.
  public var choices: [PieceType]

  public init(from: Square, to: Square, color: PieceColor, choices: [PieceType]) {
    self.from = from
    self.to = to
    self.color = color
    self.choices = choices
  }
}

/// Input from the board: pointer, keyboard, controller and accessibility. Each session takes it
/// through `apply(_:)`.
public enum BoardInput: Equatable, Sendable {
  /// Moves the cursor one square in a screen direction.
  case moveFocus(BoardDirection)
  /// Puts the cursor on a square, such as under a pointer.
  case focus(Square)
  /// Selects the square under the cursor: picks up a piece or moves the selected piece there.
  case selectFocused
  /// Selects a square directly, such as a tapped or clicked one.
  case select(Square)
  /// Closes the promotion picker or drops the selection.
  case cancel
  case promote(PieceType)
}

/// A game command from a button or menu, taken by each session's `apply(_:)`. With
/// `GameSession.apply(_:)` and `BoardInput`, the only way a game changes. `PuzzleBoardSession`
/// handles `.requestHint` and `.flipBoard` and ignores the rest.
public enum GameAction: Equatable, Sendable {
  case requestHint
  /// Bot games: back to the player's previous turn (1 or 2 plies). Pass-and-play: 1 ply.
  case takeback
  /// Bot games: the bot answers through `DrawOfferTuning.botAccepts`. Pass-and-play: waits
  /// for the other side's `.acceptDraw` or `.declineDraw`.
  case offerDraw
  case acceptDraw
  case declineDraw
  /// The human resigns in a bot game; the side to move resigns in pass-and-play.
  case resign
  case flipBoard
  /// A new game with the same players and colors swapped.
  case rematch
  case dismissBotMessage
}
