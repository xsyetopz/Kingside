import ChessContent
import ChessCore
import ChessPlay
import Foundation
import SpriteKit

/// The SpriteKit chess board. It draws a `BoardSnapshot` and turns pointer input and
/// accessibility activation into `BoardInput`s; it never changes chess state.
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

  let onIntent: (BoardInput) -> Void
  private let textures: PieceTextureCache
  let labels: SquareLabels

  private(set) var geometry: BoardGeometry
  private(set) var squareNodes: [Square: SKSpriteNode] = [:]
  private(set) var pieceNodes: [Square: PieceNode] = [:]
  var legalMarkers: [Square: LegalMarkerNode] = [:]
  /// Rebuilt with the layout; every legal marker of a kind shares its path.
  private(set) var legalMarkerPaths: [LegalMarkerNode.Kind: CGPath] = [:]
  private var coordinateNodes: [SKLabelNode] = []
  let checkNode = SKShapeNode()
  let focusNode = SKShapeNode()
  let hintNode = SKShapeNode()
  /// The correct or incorrect move marker; hidden without a badge.
  let badgeNode = SKShapeNode()
  let badgeGlyphNode = SKShapeNode()
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
    onIntent: @escaping (BoardInput) -> Void
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

  // MARK: Touch and mouse events, handled in BoardScene+Input.swift

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

  // MARK: Layout

  var squareSize: CGFloat { geometry.squareSize }

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
    legalMarkerPaths = LegalMarkerNode.paths(squareSize: squareSize, style: style)
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

  // MARK: Pieces

  /// Moves, adds, and removes piece nodes so they match the snapshot, as `PieceDiff` decides.
  private func updatePieces(from old: [Square: Piece], lastMove: ChessMove?, animated: Bool) {
    let diff = PieceDiff(old: old, new: snapshot?.pieces ?? [:], lastMove: lastMove)
    let moving = diff.moved.compactMap { move in
      pieceNodes.removeValue(forKey: move.from).map { (node: $0, move: move) }
    }
    let leaving = diff.removed.compactMap { pieceNodes.removeValue(forKey: $0) }
    for (square, piece) in diff.added.sorted(by: { $0.key < $1.key }) {
      let node = PieceNode(piece: piece)
      node.zPosition = style.zPositions.pieces
      node.position = geometry.center(of: square)
      setTexture(of: node)
      pieceNodes[square] = node
      addChild(node)
    }
    for (node, move) in moving {
      slide(node, to: move.to, becoming: move.piece, animated: animated)
    }
    for node in leaving {
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

  private func slide(_ node: PieceNode, to square: Square, becoming piece: Piece, animated: Bool) {
    if piece != node.piece {
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
