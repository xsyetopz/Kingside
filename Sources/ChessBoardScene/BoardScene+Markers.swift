import ChessContent
import ChessCore
import ChessPlay
import SpriteKit

// Square tints and the overlays drawn on top of the squares: legal-move markers, the check glow,
// the cursor ring, the hint arrow, and the correct or incorrect move badge.
extension BoardScene {
  /// Squares drawn with a tint instead of their plain color.
  static func tintedSquares(_ snapshot: BoardSnapshot?) -> Set<Square> {
    guard let snapshot else { return [] }
    return Set(
      [snapshot.lastMove?.from, snapshot.lastMove?.to, snapshot.selectedSquare].compactMap { $0 }
    )
  }

  func updateSquareColors(_ squares: Set<Square>) {
    for square in squares {
      guard let node = squareNodes[square] else { continue }
      let colors: SquareColors
      if square == snapshot?.selectedSquare {
        colors = theme.selection
      } else if let move = snapshot?.lastMove, square == move.from || square == move.to {
        colors = theme.lastMove
      } else {
        colors = theme.squares
      }
      node.color = colors.color(isLight: square.isLight).skColor
    }
  }

  /// Dots on empty legal targets, rings around capturable pieces.
  func updateLegalMarkers(_ squares: Set<Square>) {
    for square in squares {
      var kind: LegalMarkerNode.Kind?
      if let snapshot, snapshot.legalTargets.contains(square) {
        kind = snapshot.pieces[square] == nil ? .dot : .ring
      }
      if legalMarkers[square]?.kind == kind { continue }
      legalMarkers.removeValue(forKey: square)?.removeFromParent()
      guard let kind, let path = legalMarkerPaths[kind] else { continue }
      let marker = LegalMarkerNode(
        kind: kind,
        path: path,
        squareSize: squareSize,
        style: style,
        color: theme.legalMove.skColor
      )
      marker.position = geometry.center(of: square)
      legalMarkers[square] = marker
      addChild(marker)
    }
  }

  func updateCheckShape() {
    checkNode.path = .circle(diameter: squareSize * style.markers.check)
    checkNode.fillColor = theme.check.skColor
    checkNode.strokeColor = .clear
    checkNode.lineWidth = 0
  }

  func updateCheck() {
    guard let square = snapshot?.checkSquare else {
      checkNode.isHidden = true
      return
    }
    checkNode.position = geometry.center(of: square)
    checkNode.isHidden = false
  }

  func updateFocusShape() {
    let width = max(style.focusRing.minimumWidth, squareSize * style.focusRing.widthRatio)
    let side = max(0, squareSize - width)
    focusNode.path = CGPath(
      rect: CGRect(x: -side / 2, y: -side / 2, width: side, height: side),
      transform: nil
    )
    focusNode.lineWidth = width
    focusNode.strokeColor = style.focusRing.color.skColor
    focusNode.fillColor = .clear
  }

  func updateFocus(animated: Bool) {
    guard showsFocusRing, let square = snapshot?.focusedSquare else {
      focusNode.isHidden = true
      return
    }
    let target = geometry.center(of: square)
    focusNode.removeAllActions()
    if animated && !focusNode.isHidden && focusNode.position != target {
      focusNode.run(.move(to: target, duration: style.animation.focusSeconds))
    } else {
      focusNode.position = target
    }
    focusNode.isHidden = false
  }

  func updateHint() {
    guard let hint = snapshot?.hint, hint.from != hint.to else {
      hintNode.isHidden = true
      return
    }
    let start = geometry.center(of: hint.from)
    let tip = geometry.center(of: hint.to)
    let length = hypot(tip.x - start.x, tip.y - start.y)
    let direction = CGPoint(x: (tip.x - start.x) / length, y: (tip.y - start.y) / length)
    let normal = CGPoint(x: -direction.y, y: direction.x)
    let markers = style.markers
    let shaftStart = squareSize * markers.arrowStartInset
    let headBase = max(shaftStart, length - squareSize * markers.arrowHeadLength)
    func point(along distance: CGFloat, across offset: CGFloat) -> CGPoint {
      CGPoint(
        x: start.x + direction.x * distance + normal.x * offset,
        y: start.y + direction.y * distance + normal.y * offset
      )
    }
    let shaft = squareSize * markers.arrowShaftWidth / 2
    let head = squareSize * markers.arrowHeadWidth / 2
    let path = CGMutablePath()
    path.addLines(between: [
      point(along: shaftStart, across: shaft), point(along: headBase, across: shaft),
      point(along: headBase, across: head), point(along: length, across: 0),
      point(along: headBase, across: -head), point(along: headBase, across: -shaft),
      point(along: shaftStart, across: -shaft),
    ])
    path.closeSubpath()
    hintNode.path = path
    hintNode.fillColor = style.hintArrowColor.skColor
    hintNode.strokeColor = .clear
    hintNode.lineWidth = 0
    hintNode.isHidden = false
  }

  /// A colored disc with a check mark or cross on the top-right corner of the badge's square.
  func updateBadge() {
    guard let badge = snapshot?.badge, squareSize > 0 else {
      badgeNode.isHidden = true
      return
    }
    let style = style.badge
    let diameter = squareSize * style.diameterRatio
    let rect = geometry.rect(of: badge.square)
    let inset = squareSize * style.cornerInsetRatio
    badgeNode.position = CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
    badgeNode.path = .circle(diameter: diameter)
    badgeNode.fillColor =
      (badge.kind == .correct ? style.correctColor : style.incorrectColor).skColor
    badgeNode.strokeColor = .clear
    badgeNode.lineWidth = 0
    let half = diameter * style.glyphRatio / 2
    let glyph = CGMutablePath()
    switch badge.kind {
    case .correct:
      glyph.addLines(between: [
        CGPoint(x: -half, y: 0), CGPoint(x: -half / 3, y: -half * 0.7),
        CGPoint(x: half, y: half * 0.7),
      ])
    case .incorrect:
      glyph.addLines(between: [
        CGPoint(x: -half * 0.7, y: -half * 0.7), CGPoint(x: half * 0.7, y: half * 0.7),
      ])
      glyph.addLines(between: [
        CGPoint(x: -half * 0.7, y: half * 0.7), CGPoint(x: half * 0.7, y: -half * 0.7),
      ])
    }
    badgeGlyphNode.path = glyph
    badgeGlyphNode.strokeColor = style.glyphColor.skColor
    badgeGlyphNode.fillColor = .clear
    badgeGlyphNode.lineWidth = diameter * style.glyphLineRatio
    badgeGlyphNode.lineCap = .round
    badgeGlyphNode.lineJoin = .round
    badgeNode.isHidden = false
  }
}

/// A legal-move marker: a dot on an empty square or a ring around a capturable piece.
final class LegalMarkerNode: SKShapeNode {
  enum Kind { case dot, ring }

  private(set) var kind: Kind = .dot

  /// The circle of each kind at `squareSize`. Built once per layout and shared by every marker.
  static func paths(squareSize: CGFloat, style: BoardStyle) -> [Kind: CGPath] {
    let markers = style.markers
    let ringDiameter =
      squareSize * markers.captureRing - lineWidth(of: .ring, squareSize: squareSize, style: style)
    return [
      .dot: .circle(diameter: squareSize * markers.legalDot),
      .ring: .circle(diameter: ringDiameter),
    ]
  }

  private static func lineWidth(of kind: Kind, squareSize: CGFloat, style: BoardStyle) -> CGFloat {
    kind == .ring ? squareSize * style.markers.captureRingWidth : 0
  }

  convenience init(
    kind: Kind,
    path: CGPath,
    squareSize: CGFloat,
    style: BoardStyle,
    color: SKColor
  ) {
    self.init()
    self.kind = kind
    self.path = path
    lineWidth = Self.lineWidth(of: kind, squareSize: squareSize, style: style)
    fillColor = kind == .dot ? color : .clear
    strokeColor = kind == .ring ? color : .clear
    zPosition = style.zPositions.legalMarkers
  }
}

private extension CGPath {
  /// A circle of `diameter` centered on the origin.
  static func circle(diameter: CGFloat) -> CGPath {
    CGPath(
      ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter),
      transform: nil
    )
  }
}
