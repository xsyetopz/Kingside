import ChessContent
import ChessCore
import ChessPlay
import Foundation
import SpriteKit

/// One invisible accessibility element per board square. Activating it selects the square.
final class SquareAccessibilityNode: SKNode {
  let square: Square
  var onActivate: ((Square) -> Void)?
  /// What the label was last built from, so unchanged squares keep their label.
  private(set) var labelState: SquareLabelState?

  init(square: Square) {
    self.square = square
    super.init()
    isAccessibilityElement = true
    #if os(macOS)
      accessibilityRole = NSAccessibility.Role.button.rawValue
    #else
      accessibilityTraits = .button
    #endif
  }

  required init?(coder aDecoder: NSCoder) { nil }

  func updateLabel(_ state: SquareLabelState, using labels: SquareLabels) {
    guard state != labelState else { return }
    labelState = state
    accessibilityLabel = labels.label(for: square, state)
  }

  #if os(macOS)
    @objc
    func accessibilityPerformPress() -> Bool {
      onActivate?(square)
      return true
    }
  #else
    override func accessibilityActivate() -> Bool {
      onActivate?(square)
      return true
    }
  #endif
}

struct SquareLabelState: Equatable {
  var piece: Piece?
  var isSelected: Bool
  var isLegalTarget: Bool
  var isCheck: Bool
  var badge: SquareBadge.Kind?
}

/// Localized parts of the square labels, looked up once per scene.
struct SquareLabels {
  private let localization: Localization
  private let pieceNames: [Piece: String]
  private let empty: String
  private let selected: String
  private let legalTarget: String
  private let check: String
  private let badges: [SquareBadge.Kind: String]

  init(localization: Localization) {
    self.localization = localization
    var names: [Piece: String] = [:]
    for color in PieceColor.allCases {
      for type in PieceType.allCases {
        names[Piece(type: type, color: color)] = localization.string(
          "board.piece.\(color.rawValue).\(type.rawValue)"
        )
      }
    }
    pieceNames = names
    empty = localization.string("board.square.empty")
    selected = localization.string("board.square.selected")
    legalTarget = localization.string("board.square.legalTarget")
    check = localization.string("board.square.check")
    badges = [
      .correct: localization.string("board.square.badge.correct"),
      .incorrect: localization.string("board.square.badge.incorrect"),
    ]
  }

  /// Such as "e4, white knight, selected".
  func label(for square: Square, _ state: SquareLabelState) -> String {
    let content = state.piece.flatMap { pieceNames[$0] } ?? empty
    var label = localization.string("board.square.label", square.algebraic, content)
    let badge = state.badge.flatMap { badges[$0] }
    for (flag, word) in [
      (state.isSelected, selected), (state.isLegalTarget, legalTarget), (state.isCheck, check),
      (badge != nil, badge ?? ""),
    ] where flag {
      label = localization.string("board.square.state", label, word)
    }
    return label
  }
}
