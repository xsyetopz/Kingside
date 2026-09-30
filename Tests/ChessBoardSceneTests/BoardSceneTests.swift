import ChessContent
import ChessCore
import ChessPlay
import Foundation
import SpriteKit
import Testing

@testable import ChessBoardScene

@MainActor
@Suite struct BoardSceneTests {
    private static func square(_ name: String) -> Square { Square(algebraic: name)! }

    private static func snapshot(
        _ position: ChessPosition, orientation: PieceColor = .white, focus: String = "e2", selected: String? = nil,
        targets: [String] = [], lastMove: String? = nil, check: String? = nil, hint: BoardArrow? = nil,
        badge: SquareBadge? = nil
    ) -> BoardSnapshot {
        BoardSnapshot(
            pieces: position.board, orientation: orientation, focusedSquare: square(focus),
            selectedSquare: selected.map(square), legalTargets: Set(targets.map(square)),
            lastMove: lastMove.flatMap(ChessMove.init(uci:)), checkSquare: check.map(square), hint: hint,
            pendingPromotion: nil, isInputEnabled: true, badge: badge)
    }

    private static func position(_ fen: String) throws -> ChessPosition { try ChessPosition(fen: fen) }

    private static func after(_ uci: String, from position: ChessPosition = .initial) throws -> ChessPosition {
        try position.applying(try #require(ChessMove(uci: uci)))
    }

    private static func makeScene(
        size: CGSize = CGSize(width: 800, height: 800), onIntent: @escaping (BoardIntent) -> Void = { _ in }
    ) throws -> BoardScene {
        let catalog = try ContentCatalog.load()
        let theme = try #require(catalog.boardTheme(id: catalog.defaults.boardThemeID))
        let pieceSet = try #require(catalog.pieceSet(id: catalog.defaults.pieceSetID))
        return BoardScene(
            size: size, theme: theme, pieceSet: pieceSet, style: catalog.boardStyle,
            localization: Localization(preferredLanguages: ["en-US"]), displayScale: 2, onIntent: onIntent)
    }

    /// RGBA values, so colors compare across color-space representations.
    private static func components(_ color: SKColor?) -> [CGFloat] {
        (color?.cgColor.components ?? []).map { ($0 * 255).rounded() }
    }

    /// Node identity per square.
    private static func identities(_ scene: BoardScene) -> [Square: ObjectIdentifier] {
        scene.pieceNodes.mapValues(ObjectIdentifier.init)
    }

    /// Nodes that stand on a different square than before.
    private static func movedNodeCount(before: [Square: ObjectIdentifier], after: [Square: ObjectIdentifier]) -> Int {
        after.filter { square, id in before[square] != id && before.values.contains(id) }.count
    }

    @Test func startSnapshotCreatesAPieceNodeOnEveryOccupiedSquare() throws {
        let scene = try Self.makeScene()
        scene.apply(Self.snapshot(.initial), animated: false)

        #expect(scene.children.filter { $0 is PieceNode }.count == 32)
        #expect(scene.pieceNodes.count == 32)
        for (square, piece) in ChessPosition.initial.board {
            let node = try #require(scene.pieceNodes[square], "\(square)")
            #expect(node.piece == piece, "\(square)")
            #expect(node.position == scene.geometry.center(of: square), "\(square)")
            #expect(node.texture != nil, "\(square) has no art")
        }
    }

    @Test func aMoveSlidesExactlyOneNode() throws {
        let scene = try Self.makeScene()
        scene.apply(Self.snapshot(.initial), animated: false)
        let before = Self.identities(scene)

        scene.apply(Self.snapshot(try Self.after("e2e4"), lastMove: "e2e4"), animated: true)

        let after = Self.identities(scene)
        #expect(Self.movedNodeCount(before: before, after: after) == 1)
        #expect(after[Self.square("e4")] == before[Self.square("e2")])
        #expect(after.count == 32)
        #expect(scene.pieceNodes[Self.square("e4")]?.hasActions() == true)
    }

    @Test func castlingSlidesKingAndRook() throws {
        let start = try Self.position("r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1")
        let scene = try Self.makeScene()
        scene.apply(Self.snapshot(start), animated: false)
        let before = Self.identities(scene)

        scene.apply(Self.snapshot(try Self.after("e1g1", from: start), lastMove: "e1g1"), animated: false)

        let after = Self.identities(scene)
        #expect(Self.movedNodeCount(before: before, after: after) == 2)
        #expect(after[Self.square("g1")] == before[Self.square("e1")])
        #expect(after[Self.square("f1")] == before[Self.square("h1")])
        #expect(scene.pieceNodes[Self.square("f1")]?.position == scene.geometry.center(of: Self.square("f1")))
    }

    @Test func aCaptureRemovesTheCapturedNode() throws {
        let start = try Self.position("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1")
        let scene = try Self.makeScene()
        scene.apply(Self.snapshot(start), animated: false)
        let captured = try #require(scene.pieceNodes[Self.square("d5")])
        let capturer = try #require(scene.pieceNodes[Self.square("e4")])

        scene.apply(Self.snapshot(try Self.after("e4d5", from: start), lastMove: "e4d5"), animated: false)

        #expect(scene.pieceNodes.count == 3)
        #expect(scene.pieceNodes[Self.square("d5")] === capturer)
        #expect(captured.parent == nil)
        #expect(scene.children.filter { $0 is PieceNode }.count == 3)
    }

    @Test func markersFollowTheSnapshot() throws {
        let start = try Self.position("4k3/8/8/3p4/4P3/8/8/4K3 w - - 0 1")
        let scene = try Self.makeScene()
        scene.apply(
            Self.snapshot(start, selected: "e4", targets: ["e5", "d5"], lastMove: "e2e4", check: "e1"), animated: false)

        #expect(Set(scene.legalMarkers.keys) == [Self.square("e5"), Self.square("d5")])
        #expect(scene.legalMarkers[Self.square("e5")]?.kind == .dot)
        #expect(scene.legalMarkers[Self.square("d5")]?.kind == .ring)
        #expect(!scene.checkNode.isHidden && scene.checkNode.position == scene.geometry.center(of: Self.square("e1")))
        let theme = scene.theme
        #expect(Self.components(scene.squareNodes[Self.square("e2")]?.color) == Self.components(theme.lastMove.light.skColor))
        #expect(Self.components(scene.squareNodes[Self.square("e4")]?.color) == Self.components(theme.selection.light.skColor))
        #expect(Self.components(scene.squareNodes[Self.square("e3")]?.color) == Self.components(theme.squares.dark.skColor))

        scene.apply(Self.snapshot(start, focus: "d5", lastMove: nil), animated: false)

        #expect(scene.legalMarkers.isEmpty)
        #expect(scene.checkNode.isHidden)
        #expect(Self.components(scene.squareNodes[Self.square("e2")]?.color) == Self.components(theme.squares.light.skColor))
        #expect(scene.focusNode.position == scene.geometry.center(of: Self.square("d5")))
    }

    @Test func flippingTheOrientationMirrorsThePieces() throws {
        let size = CGSize(width: 900, height: 600)
        let scene = try Self.makeScene(size: size)
        scene.apply(Self.snapshot(.initial), animated: false)
        let white = scene.pieceNodes.mapValues(\.position)

        scene.apply(Self.snapshot(.initial, orientation: .black), animated: false)

        for (square, point) in white {
            let flipped = try #require(scene.pieceNodes[square]?.position, "\(square)")
            #expect(abs(flipped.x - (size.width - point.x)) < 0.001, "\(square)")
            #expect(abs(flipped.y - (size.height - point.y)) < 0.001, "\(square)")
        }
    }

    @Test func accessibilityElementsDescribeEverySquare() throws {
        var intents: [BoardIntent] = []
        let scene = try Self.makeScene { intents.append($0) }
        scene.apply(Self.snapshot(.initial, selected: "g1", targets: ["f3", "h3"]), animated: false)

        let nodes = scene.squareAccessibilityNodes
        #expect(nodes.count == 64)
        #expect(nodes.allSatisfy { $0.isAccessibilityElement })
        let labels = Dictionary(uniqueKeysWithValues: nodes.map { (($0 as! SquareAccessibilityNode).square, $0.accessibilityLabel ?? "") })
        #expect(labels[Self.square("e1")] == "e1, white king")
        #expect(labels[Self.square("d8")] == "d8, black queen")
        #expect(labels[Self.square("e4")] == "e4, empty")
        #expect(labels[Self.square("g1")] == "g1, white knight, selected")
        #expect(labels[Self.square("f3")] == "f3, empty, legal move")
        for (square, piece) in ChessPosition.initial.board {
            #expect(labels[square]?.hasPrefix("\(square), \(piece.color.rawValue) \(piece.type.rawValue)") == true, "\(square)")
        }

        scene.apply(Self.snapshot(try Self.position("4k3/8/8/8/8/8/8/4K2r w - - 0 1"), check: "e1"), animated: false)
        #expect(nodes[4].accessibilityLabel == "e1, white king, in check")

        #if os(macOS)
        let f3 = try #require(nodes.first { ($0 as? SquareAccessibilityNode)?.square == Self.square("f3") } as? SquareAccessibilityNode)
        #expect(f3.accessibilityPerformPress())
        #expect(intents == [.select(Self.square("f3"))])
        #endif
    }

    @Test func badgeAppearsOnTheSquareCornerAndDisappears() throws {
        let scene = try Self.makeScene()
        let style = scene.style.badge
        scene.apply(Self.snapshot(.initial), animated: false)
        #expect(scene.badgeNode.isHidden)

        let e4 = Self.square("e4")
        let position = try Self.after("e2e4")
        scene.apply(Self.snapshot(position, lastMove: "e2e4", badge: SquareBadge(square: e4, kind: .correct)), animated: false)

        let rect = scene.geometry.rect(of: e4)
        let inset = scene.geometry.squareSize * style.cornerInsetRatio
        #expect(!scene.badgeNode.isHidden)
        #expect(scene.badgeNode.position == CGPoint(x: rect.maxX - inset, y: rect.maxY - inset))
        #expect(abs(Double(scene.badgeNode.zPosition) - scene.style.zPositions.badge) < 0.001)
        #expect(Self.components(scene.badgeNode.fillColor) == Self.components(style.correctColor.skColor))
        #expect(abs(scene.badgeNode.frame.width - scene.geometry.squareSize * style.diameterRatio) < 0.001)
        let label = try #require(scene.squareAccessibilityNodes.compactMap { $0 as? SquareAccessibilityNode }.first { $0.square == e4 })
        #expect(label.accessibilityLabel == "e4, white pawn, correct move")

        scene.apply(Self.snapshot(position, lastMove: "e2e4", badge: SquareBadge(square: e4, kind: .incorrect)), animated: false)
        #expect(!scene.badgeNode.isHidden)
        #expect(Self.components(scene.badgeNode.fillColor) == Self.components(style.incorrectColor.skColor))
        #expect(label.accessibilityLabel == "e4, white pawn, incorrect move")

        scene.apply(Self.snapshot(position, lastMove: "e2e4"), animated: false)
        #expect(scene.badgeNode.isHidden)
        #expect(label.accessibilityLabel == "e4, white pawn")
    }

    @Test(arguments: [PieceColor.white, .black])
    func hitTestFindsTheSquareUnderAPoint(orientation: PieceColor) throws {
        var intents: [BoardIntent] = []
        let scene = try Self.makeScene(size: CGSize(width: 1000, height: 600)) { intents.append($0) }
        scene.apply(Self.snapshot(.initial, orientation: orientation), animated: false)

        // The 600-point board is centered: x 200...800, 75 points per square.
        let bottomLeft = orientation == .white ? "a1" : "h8"
        let topRight = orientation == .white ? "h8" : "a1"
        #expect(scene.square(at: CGPoint(x: 201, y: 1)) == Self.square(bottomLeft))
        #expect(scene.square(at: CGPoint(x: 799, y: 599)) == Self.square(topRight))
        #expect(scene.square(at: CGPoint(x: 200 + 75 * 4.5, y: 75 * 3.5)) == Self.square(orientation == .white ? "e4" : "d5"))
        #expect(scene.square(at: CGPoint(x: 199, y: 300)) == nil)
        #expect(scene.square(at: CGPoint(x: 801, y: 300)) == nil)
        for square in Square.all {
            #expect(scene.square(at: scene.geometry.center(of: square)) == square)
        }

        scene.pointerDown(at: scene.geometry.center(of: Self.square("e2")))
        #expect(intents == [.focus(Self.square("e2")), .select(Self.square("e2"))])
    }

    @Test func pdfPieceArtRasterizesToTheRequestedPixelSize() throws {
        let catalog = try ContentCatalog.load()
        let set = try #require(catalog.pieceSet(id: "cburnett"))
        let url = try #require(set.url(for: Piece(type: .knight, color: .white)))
        #expect(url.pathExtension == "pdf")

        let image = try #require(PieceTextureCache.rasterize(pdfAt: url, pixelSize: 97))
        #expect(image.width == 97 && image.height == 97)

        // The scene caches one texture per (set, piece, pixel size): 800 / 8 * 0.9 * 2 = 180.
        let scene = try Self.makeScene()
        scene.apply(Self.snapshot(.initial), animated: false)
        #expect(scene.piecePixelSize == 180)
        let texture = try #require(scene.pieceNodes[Self.square("g1")]?.texture)
        #expect(texture.cgImage().width == 180)
    }

    /// Q2: a snapshot update takes under 2 ms of main-thread time.
    @Test func applyingASnapshotTakesUnderTwoMilliseconds() throws {
        let scene = try Self.makeScene()
        let snapshots = [
            Self.snapshot(.initial, focus: "e2", selected: "e2", targets: ["e3", "e4"]),
            Self.snapshot(try Self.after("e2e4"), focus: "e4", lastMove: "e2e4"),
        ]
        scene.apply(snapshots[1], animated: false)
        let runs = 1_000
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for index in 0..<runs {
                scene.apply(snapshots[index % 2], animated: false)
            }
        }
        let meanMilliseconds = (Double(elapsed.components.seconds) * 1e3 + Double(elapsed.components.attoseconds) / 1e15)
            / Double(runs)
        print("Q2 BoardScene.apply mean: \(String(format: "%.4f", meanMilliseconds)) ms over \(runs) snapshots")
        #expect(meanMilliseconds < 2)
    }
}
