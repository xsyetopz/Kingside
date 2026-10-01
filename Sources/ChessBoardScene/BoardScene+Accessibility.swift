import ChessCore
import ChessPlay
import SpriteKit

// One accessibility element per square, labeled from the applied snapshot.
extension BoardScene {
  /// The spoken description of `square` in `snapshot`, such as "e4, white knight, selected".
  /// Takes the snapshot rather than using the applied one: a view builds its label before it
  /// applies a new snapshot to the scene.
  public func accessibilityLabel(for square: Square, in snapshot: BoardSnapshot) -> String {
    labels.label(for: square, labelState(of: square, in: snapshot))
  }

  private func labelState(of square: Square, in snapshot: BoardSnapshot?) -> SquareLabelState {
    SquareLabelState(
      piece: snapshot?.pieces[square],
      isSelected: snapshot?.selectedSquare == square,
      isLegalTarget: snapshot?.legalTargets.contains(square) ?? false,
      isCheck: snapshot?.checkSquare == square,
      badge: snapshot?.badge?.square == square ? snapshot?.badge?.kind : nil
    )
  }

  func updateAccessibilityLabels() {
    for case let node as SquareAccessibilityNode in squareAccessibilityNodes {
      node.updateLabel(labelState(of: node.square, in: snapshot), using: labels)
    }
  }

  /// Accessibility frames are in screen coordinates, so they need the view.
  func updateAccessibilityFrames() {
    for case let node as SquareAccessibilityNode in squareAccessibilityNodes {
      let rect = geometry.rect(of: node.square)
      node.position = CGPoint(x: rect.midX, y: rect.midY)
      guard let view else { continue }
      let corner = convertPoint(toView: CGPoint(x: rect.minX, y: rect.minY))
      let opposite = convertPoint(toView: CGPoint(x: rect.maxX, y: rect.maxY))
      let viewRect = CGRect(
        x: min(corner.x, opposite.x),
        y: min(corner.y, opposite.y),
        width: abs(opposite.x - corner.x),
        height: abs(opposite.y - corner.y)
      )
      #if os(macOS)
        node.accessibilityFrame =
          view.window?.convertToScreen(view.convert(viewRect, to: nil)) ?? viewRect
      #else
        node.accessibilityFrame = UIAccessibility.convertToScreenCoordinates(viewRect, in: view)
      #endif
    }
  }
}
