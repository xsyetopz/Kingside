import ChessContent
import ChessCore
import ChessPlay
import Foundation
import SpriteKit

/// The SpriteKit chess board. It draws a `BoardSnapshot` and turns pointer input and
/// accessibility activation into `BoardIntent`s; it never changes chess state.
///
/// Remote and game-controller input is mapped to intents outside the scene (`ChessFeedback`).
/// Nodes are kept between snapshots: `apply(_:animated:)` diffs the old snapshot against the
/// new one and updates only what changed.
public final class BoardScene: SKScene {
  public private(set) var snapshot: BoardSnapshot?
  public private(set) var theme: BoardTheme
  public private(set) var pieceSet: PieceSet
  public let style: BoardStyle
  /// Pixels per point of the view showing the scene; piece art is rasterized at this density.
  public var displayScale: CGFloat {
    didSet { if displayScale != oldValue { updatePieceTextures() } }
  }

  let onIntent: (BoardIntent) -> Void
  private let textures: PieceTextureCache
  private let labels: SquareLabels

  private(set) var geometry: BoardGeometry
  private(set) var squareNodes: [Square: SKSpriteNode] = [:]
  private(set) var pieceNodes: [Square: PieceNode] = [:]
  private(set) var legalMarkers: [Square: LegalMarkerNode] = [:]
  private var coordinateNodes: [SKLabelNode] = []
  let checkNode = SKShapeNode()
  let focusNode = SKShapeNode()
  let hintNode = SKShapeNode()
  /// The correct or incorrect move marker; hidden without a badge.
  let badgeNode = SKShapeNode()
  private let badgeGlyphNode = SKShapeNode()
  /// One per square, in `Square.all` order (a1, b1, …, h8).
  public private(set) var squareAccessibilityNodes: [SKNode] = []
  /// Whether the cursor ring is drawn. Off for pointer and touch input, on for the remote,
  /// keyboard, and controllers.
  public var showsFocusRing = true {
    didSet { if showsFocusRing != oldValue { updateFocus(animated: false) } }
  }
  var drag: PieceDrag?

  public init(
    size: CGSize,
    theme: BoardTheme,
    pieceSet: PieceSet,
    style: BoardStyle,
    localization: Localization,
    displayScale: CGFloat,
    bundle: Bundle = Localization.moduleBundle,
    onIntent: @escaping (BoardIntent) -> Void
  ) {
    self.theme = theme
    self.pieceSet = pieceSet
    self.style = style
    self.displayScale = displayScale
    self.onIntent = onIntent
    textures = PieceTextureCache(bundle: bundle)
    labels = SquareLabels(localization: localization)
    geometry = BoardGeometry(sceneSize: size, orientation: .white)
    super.init(size: size)
    scaleMode = .resizeFill
    anchorPoint = .zero
    backgroundColor = .clear

    for square in Square.all {
      let node = SKSpriteNode(color: .clear, size: .zero)
      node.zPosition = style.zPositions.squares
      squareNodes[square] = node
      addChild(node)
    }
    checkNode.zPosition = style.zPositions.check
    hintNode.zPosition = style.zPositions.hintArrow
    badgeNode.zPosition = style.zPositions.badge
    badgeNode.addChild(badgeGlyphNode)
    focusNode.zPosition = style.zPositions.focusRing
    for node in [checkNode, hintNode, badgeNode, focusNode] {
      node.isHidden = true
      addChild(node)
    }
    let accessibilityNodes = Square.all.map(SquareAccessibilityNode.init)
    for node in accessibilityNodes {
      node.onActivate = { [weak self] in self?.onIntent(.select($0)) }
      addChild(node)
    }
    squareAccessibilityNodes = accessibilityNodes
    isAccessibilityElement = false
    #if os(macOS)
      accessibilityChildren = accessibilityNodes
    #else
      accessibilityElements = accessibilityNodes
    #endif
    layoutBoard()
  }

  required init?(coder aDecoder: NSCoder) { nil }

  // MARK: Public API

  /// Draws `snapshot`. With `animated`, pieces slide, captured pieces fade, and the focus ring
  /// glides.
  public func apply(_ snapshot: BoardSnapshot, animated: Bool) {
    let old = self.snapshot
    self.snapshot = snapshot
    if old?.orientation != snapshot.orientation {
      updatePieces(from: old?.pieces ?? [:], lastMove: snapshot.lastMove, animated: false)
      layoutBoard()
      return
    }
    updatePieces(from: old?.pieces ?? [:], lastMove: snapshot.lastMove, animated: animated)
    updateSquareColors(Self.tintedSquares(old).union(Self.tintedSquares(snapshot)))
    updateLegalMarkers(Set(old?.legalTargets ?? []).union(snapshot.legalTargets))
    updateCheck()
    updateFocus(animated: animated)
    if old?.hint != snapshot.hint { updateHint() }
    if old?.badge != snapshot.badge { updateBadge() }
    updateAccessibilityLabels()
  }

  public func setTheme(_ theme: BoardTheme) {
    self.theme = theme
    layoutBoard()
  }

  public func setPieceSet(_ pieceSet: PieceSet) {
    self.pieceSet = pieceSet
    updatePieceTextures()
  }

  /// The square under a point in scene coordinates; nil outside the board.
  public func square(at point: CGPoint) -> Square? {
    geometry.square(at: point)
  }

  override public func didChangeSize(_ oldSize: CGSize) {
    super.didChangeSize(oldSize)
    // `SKScene.init(size:)` calls this before the stored properties exist.
    guard !squareAccessibilityNodes.isEmpty, size != oldSize else { return }
    layoutBoard()
  }

  override public func didMove(to view: SKView) {
    super.didMove(to: view)
    updateAccessibilityFrames()
  }

  // MARK: Layout

  private var squareSize: CGFloat { geometry.squareSize }

  /// Recomputes the geometry and redraws everything at the new size, orientation, or theme.
  private func layoutBoard() {
    drag = nil
    geometry = BoardGeometry(sceneSize: size, orientation: snapshot?.orientation ?? .white)
    let squareSide = CGSize(width: squareSize, height: squareSize)
    for (square, node) in squareNodes {
      node.size = squareSide
      node.position = geometry.center(of: square)
    }
    updateSquareColors(Set(Square.all))
    layoutCoordinates()
    for (square, node) in pieceNodes {
      node.removeAllActions()
      node.zPosition = style.zPositions.pieces
      node.position = geometry.center(of: square)
    }
    updatePieceTextures()
    for marker in legalMarkers.values { marker.removeFromParent() }
    legalMarkers = [:]
    updateLegalMarkers(snapshot?.legalTargets ?? [])
    updateCheckShape()
    updateCheck()
    updateFocusShape()
    updateFocus(animated: false)
    updateHint()
    updateBadge()
    updateAccessibilityLabels()
    updateAccessibilityFrames()
  }

  /// File letters along the bottom row and rank digits along the left column.
  private func layoutCoordinates() {
    for node in coordinateNodes { node.removeFromParent() }
    coordinateNodes = []
    guard squareSize > 0 else { return }
    let inset = squareSize * style.markers.coordinateInset
    func addLabel(
      _ text: String,
      on square: Square,
      alignment: SKLabelHorizontalAlignmentMode,
      at point: CGPoint
    ) {
      let label = SKLabelNode(fontNamed: style.coordinateFontName)
      label.text = text
      label.fontSize = squareSize * style.markers.coordinateFont
      label.fontColor = theme.coordinates.color(isLight: square.isLight).skColor
      label.horizontalAlignmentMode = alignment
      label.verticalAlignmentMode = alignment == .right ? .bottom : .top
      label.position = point
      label.zPosition = style.zPositions.coordinates
      coordinateNodes.append(label)
      addChild(label)
    }
    for index in 0..<8 {
      let bottom = geometry.square(column: index, row: 0)
      let bottomRect = geometry.rect(of: bottom)
      addLabel(
        String(bottom.algebraic.prefix(1)),
        on: bottom,
        alignment: .right,
        at: CGPoint(x: bottomRect.maxX - inset, y: bottomRect.minY + inset)
      )
      let left = geometry.square(column: 0, row: index)
      let leftRect = geometry.rect(of: left)
      addLabel(
        String(left.algebraic.suffix(1)),
        on: left,
        alignment: .left,
        at: CGPoint(x: leftRect.minX + inset, y: leftRect.maxY - inset)
      )
    }
  }

  // MARK: Squares and markers

  /// Squares drawn with a tint instead of their plain color.
  private static func tintedSquares(_ snapshot: BoardSnapshot?) -> Set<Square> {
    guard let snapshot else { return [] }
    return Set(
      [snapshot.lastMove?.from, snapshot.lastMove?.to, snapshot.selectedSquare].compactMap { $0 }
    )
  }

  private func updateSquareColors(_ squares: Set<Square>) {
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
  private func updateLegalMarkers(_ squares: Set<Square>) {
    for square in squares {
      var kind: LegalMarkerNode.Kind?
      if let snapshot, snapshot.legalTargets.contains(square) {
        kind = snapshot.pieces[square] == nil ? .dot : .ring
      }
      if legalMarkers[square]?.kind == kind { continue }
      legalMarkers.removeValue(forKey: square)?.removeFromParent()
      guard let kind else { continue }
      let marker = LegalMarkerNode(
        kind: kind,
        squareSize: squareSize,
        style: style,
        color: theme.legalMove.skColor
      )
      marker.position = geometry.center(of: square)
      legalMarkers[square] = marker
      addChild(marker)
    }
  }

  private func updateCheckShape() {
    let diameter = squareSize * style.markers.check
    checkNode.path = CGPath(
      ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter),
      transform: nil
    )
    checkNode.fillColor = theme.check.skColor
    checkNode.strokeColor = .clear
    checkNode.lineWidth = 0
  }

  private func updateCheck() {
    guard let square = snapshot?.checkSquare else {
      checkNode.isHidden = true
      return
    }
    checkNode.position = geometry.center(of: square)
    checkNode.isHidden = false
  }

  private func updateFocusShape() {
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

  private func updateFocus(animated: Bool) {
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

  private func updateHint() {
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
  private func updateBadge() {
    guard let badge = snapshot?.badge, squareSize > 0 else {
      badgeNode.isHidden = true
      return
    }
    let style = style.badge
    let diameter = squareSize * style.diameterRatio
    let rect = geometry.rect(of: badge.square)
    let inset = squareSize * style.cornerInsetRatio
    badgeNode.position = CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
    badgeNode.path = CGPath(
      ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter),
      transform: nil
    )
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

  // MARK: Pieces

  /// Moves, adds, and removes piece nodes so they match the snapshot. A node that leaves a
  /// square slides to a square where the same piece appears: the last move first (which may
  /// promote), then the nearest match, so castling moves both king and rook.
  private func updatePieces(from old: [Square: Piece], lastMove: ChessMove?, animated: Bool) {
    let new = snapshot?.pieces ?? [:]
    var vacated: [Square: PieceNode] = [:]
    for (square, piece) in old where new[square] != piece {
      vacated[square] = pieceNodes.removeValue(forKey: square)
    }
    var appeared = new.keys.filter { old[$0] != new[$0] }.sorted()
    var moves: [(node: PieceNode, to: Square)] = []
    if let move = lastMove, let index = appeared.firstIndex(of: move.to),
      let node = vacated[move.from],
      node.piece.color == new[move.to]?.color
    {
      vacated[move.from] = nil
      appeared.remove(at: index)
      moves.append((node, move.to))
    }
    for square in appeared {
      let piece = new[square]
      let match = vacated.filter { $0.value.piece == piece }.min { lhs, rhs in
        let (left, right) = (Self.distance(lhs.key, square), Self.distance(rhs.key, square))
        return left != right ? left < right : lhs.key < rhs.key
      }
      if let match {
        vacated[match.key] = nil
        moves.append((match.value, square))
      } else if let piece {
        let node = PieceNode(piece: piece)
        node.zPosition = style.zPositions.pieces
        node.position = geometry.center(of: square)
        setTexture(of: node)
        pieceNodes[square] = node
        addChild(node)
      }
    }
    for (node, square) in moves {
      if let piece = new[square], piece != node.piece {
        node.piece = piece
        setTexture(of: node)
      }
      pieceNodes[square] = node
      let target = geometry.center(of: square)
      node.removeAllActions()
      if animated {
        node.zPosition = style.zPositions.movingPiece
        let restZ = style.zPositions.pieces
        node.run(
          .sequence([
            .move(to: target, duration: style.animation.moveSeconds),
            .run { [weak node] in node?.zPosition = restZ },
          ])
        )
      } else {
        node.zPosition = style.zPositions.pieces
        node.position = target
      }
    }
    for node in vacated.values {
      node.removeAllActions()
      if animated {
        node.run(
          .sequence([
            .fadeOut(withDuration: style.animation.captureFadeSeconds), .removeFromParent(),
          ])
        )
      } else {
        node.removeFromParent()
      }
    }
  }

  private static func distance(_ lhs: Square, _ rhs: Square) -> Int {
    max(abs(lhs.file - rhs.file), abs(lhs.rank - rhs.rank))
  }

  /// Side of the piece art in pixels at the current square size and display scale.
  var piecePixelSize: Int {
    Int((squareSize * style.markers.piece * displayScale).rounded())
  }

  private func setTexture(of node: PieceNode) {
    let side = squareSize * style.markers.piece
    node.texture = textures.texture(for: node.piece, in: pieceSet, pixelSize: piecePixelSize)
    node.size = CGSize(width: side, height: side)
  }

  private func updatePieceTextures() {
    for node in pieceNodes.values { setTexture(of: node) }
  }

  // MARK: Accessibility

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

  private func updateAccessibilityLabels() {
    for case let node as SquareAccessibilityNode in squareAccessibilityNodes {
      node.updateLabel(labelState(of: node.square, in: snapshot), using: labels)
    }
  }

  /// Accessibility frames are in screen coordinates, so they need the view.
  private func updateAccessibilityFrames() {
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

  #if os(iOS)
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let touch = touches.first else { return }
      pointerDown(at: touch.location(in: self))
    }

    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let touch = touches.first else { return }
      pointerMoved(to: touch.location(in: self))
    }

    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let touch = touches.first else { return }
      pointerUp(at: touch.location(in: self))
    }

    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
      guard let drag else { return }
      pointerUp(at: geometry.center(of: drag.from))
    }
  #elseif os(macOS)
    override public func mouseDown(with event: NSEvent) {
      pointerDown(at: event.location(in: self))
    }

    override public func mouseDragged(with event: NSEvent) {
      pointerMoved(to: event.location(in: self))
    }

    override public func mouseUp(with event: NSEvent) {
      pointerUp(at: event.location(in: self))
    }
  #endif
}

/// A piece sprite; it keeps its piece so a move can match it to the square it lands on.
final class PieceNode: SKSpriteNode {
  var piece: Piece

  init(piece: Piece) {
    self.piece = piece
    super.init(texture: nil, color: .clear, size: .zero)
  }

  required init?(coder aDecoder: NSCoder) { nil }
}

/// A legal-move marker: a dot on an empty square or a ring around a capturable piece.
final class LegalMarkerNode: SKShapeNode {
  enum Kind { case dot, ring }

  private(set) var kind: Kind = .dot

  convenience init(kind: Kind, squareSize: CGFloat, style: BoardStyle, color: SKColor) {
    let markers = style.markers
    let lineWidth = kind == .ring ? squareSize * markers.captureRingWidth : 0
    let diameter =
      kind == .ring ? squareSize * markers.captureRing - lineWidth : squareSize * markers.legalDot
    self.init()
    self.kind = kind
    path = CGPath(
      ellipseIn: CGRect(x: -diameter / 2, y: -diameter / 2, width: diameter, height: diameter),
      transform: nil
    )
    self.lineWidth = lineWidth
    fillColor = kind == .dot ? color : .clear
    strokeColor = kind == .ring ? color : .clear
    zPosition = style.zPositions.legalMarkers
  }
}
