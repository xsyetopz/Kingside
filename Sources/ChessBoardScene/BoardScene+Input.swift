import ChessCore
import ChessPlay
import SpriteKit

/// A piece following the pointer.
struct PieceDrag {
  let from: Square
  let node: PieceNode
}

// Pointer input: press on a square focuses and selects it; dragging a piece and releasing it
// on another square selects that square, which the session turns into a move.
extension BoardScene {
  func pointerDown(at point: CGPoint) {
    drag = nil
    guard let square = square(at: point) else { return }
    onIntent(.focus(square))
    onIntent(.select(square))
    // The session may have answered with a new snapshot during the intents above.
    if snapshot?.isInputEnabled == true, snapshot?.selectedSquare == square,
      let node = pieceNodes[square]
    {
      drag = PieceDrag(from: square, node: node)
    }
  }

  func pointerMoved(to point: CGPoint) {
    guard let drag, pieceNodes[drag.from] === drag.node else { return }
    drag.node.removeAllActions()
    drag.node.zPosition = style.zPositions.movingPiece
    drag.node.position = point
  }

  func pointerUp(at point: CGPoint) {
    guard let drag else { return }
    self.drag = nil
    if let target = square(at: point), target != drag.from {
      onIntent(.select(target))
    }
    // Not moved by a new snapshot: return the piece to its square.
    if pieceNodes[drag.from] === drag.node {
      drag.node.zPosition = style.zPositions.pieces
      drag.node.run(
        .move(to: geometry.center(of: drag.from), duration: style.animation.moveSeconds)
      )
    }
  }
}
