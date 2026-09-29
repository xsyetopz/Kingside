import SwiftUI
import ChessCore

// Read-only, platform-neutral chess board. `ChessBoardView` wraps it with remote input and focus.
// Use it directly for review screens and thumbnails:
//   ChessBoardDisplay(position: pos, lastMove: move, isFlipped: false, theme: .green,
//                     arrows: [BoardArrow(from: e2, to: e4)], badges: [...])
//   ChessBoardDisplay.thumbnail(pos, size: 240)
// Draws: flat squares, in-square coordinates, last-move and selected tints, red check glow,
// legal-move dots/rings, pieces (slide on moves incl. castling rook and en passant; captures
// fade), the remote cursor (`cursorSquare`, nil hides it), arrows and badges.
// The view fills the largest square that fits its frame.

struct ChessBoardDisplay: View {
    let position: ChessPosition
    var lastMove: ChessMove?
    var isFlipped = false
    var theme: BoardTheme = .green
    var pieceSet: PieceSet = .cburnett
    var showCoordinates = true
    var animateMoves = true
    var arrows: [BoardArrow] = []
    var badges: [BoardBadge] = []
    /// Square of the piece picked up by the player; tinted with the theme's selected color.
    var selectedSquare: Square?
    /// Destinations to mark with a dot (empty square) or ring (capture).
    var legalDestinations: Set<Square> = []
    /// Square under the remote cursor; nil hides the cursor.
    var cursorSquare: Square?

    @State private var renderedPieces: [RenderedPiece]
    @State private var movingPieceID: UUID?

    init(
        position: ChessPosition,
        lastMove: ChessMove? = nil,
        isFlipped: Bool = false,
        theme: BoardTheme = .green,
        pieceSet: PieceSet = .cburnett,
        showCoordinates: Bool = true,
        animateMoves: Bool = true,
        arrows: [BoardArrow] = [],
        badges: [BoardBadge] = [],
        selectedSquare: Square? = nil,
        legalDestinations: Set<Square> = [],
        cursorSquare: Square? = nil
    ) {
        self.position = position
        self.lastMove = lastMove
        self.isFlipped = isFlipped
        self.theme = theme
        self.pieceSet = pieceSet
        self.showCoordinates = showCoordinates
        self.animateMoves = animateMoves
        self.arrows = arrows
        self.badges = badges
        self.selectedSquare = selectedSquare
        self.legalDestinations = legalDestinations
        self.cursorSquare = cursorSquare
        _renderedPieces = State(initialValue: RenderedPiece.all(in: position))
    }

    /// A small, static board (no coordinates, no animation) for lists and cards.
    static func thumbnail(
        _ position: ChessPosition,
        lastMove: ChessMove? = nil,
        isFlipped: Bool = false,
        theme: BoardTheme = .green,
        size: CGFloat = 240
    ) -> some View {
        ChessBoardDisplay(
            position: position,
            lastMove: lastMove,
            isFlipped: isFlipped,
            theme: theme,
            showCoordinates: false,
            animateMoves: false
        )
        .frame(width: size, height: size)
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let squareSize = side / 8
            ZStack(alignment: .topLeading) {
                ZStack(alignment: .topLeading) {
                    squares(squareSize: squareSize)
                    checkGlow(squareSize: squareSize)
                    legalMoveHints(squareSize: squareSize)
                    pieces(squareSize: squareSize)
                    cursor(squareSize: squareSize)
                }
                .frame(width: side, height: side)
                .clipShape(RoundedRectangle(cornerRadius: max(2, side * 0.005)))
                BoardArrowsLayer(arrows: arrows, squareSize: squareSize) { point(for: $0, squareSize: squareSize) }
                    .frame(width: side, height: side)
                BoardBadgesLayer(badges: badges, squareSize: squareSize) { point(for: $0, squareSize: squareSize) }
                    .frame(width: side, height: side)
            }
            .frame(width: side, height: side)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: position) { oldPosition, newPosition in
            updateRenderedPieces(from: oldPosition, to: newPosition)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Chess board")
    }

    // MARK: Layers

    private func squares(squareSize: CGFloat) -> some View {
        ForEach(0..<64, id: \.self) { index in
            let column = index % 8
            let row = index / 8
            let square = square(column: column, row: row)
            let isLight = square.isLight
            Rectangle()
                .fill(fill(for: square))
                .overlay(alignment: .topLeading) {
                    if showCoordinates && column == 0 {
                        coordinateLabel("\(square.rank + 1)", isLight: isLight, squareSize: squareSize)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    if showCoordinates && row == 7 {
                        coordinateLabel(fileName(square.file), isLight: isLight, squareSize: squareSize)
                    }
                }
                .frame(width: squareSize, height: squareSize)
                .offset(x: CGFloat(column) * squareSize, y: CGFloat(row) * squareSize)
        }
    }

    private func coordinateLabel(_ text: String, isLight: Bool, squareSize: CGFloat) -> some View {
        Text(text)
            .font(.system(size: max(8, squareSize * 0.19), weight: .bold))
            .foregroundStyle(theme.coordinateColor(isLight: isLight))
            .padding(.horizontal, squareSize * 0.05)
            .padding(.vertical, squareSize * 0.02)
    }

    @ViewBuilder
    private func checkGlow(squareSize: CGFloat) -> some View {
        if let king = checkedKingSquare {
            RadialGradient(
                colors: [Color(hex: 0xFF0000), Color(hex: 0xE70000, opacity: 0.85), Color(hex: 0xA90000, opacity: 0)],
                center: .center,
                startRadius: 0,
                endRadius: squareSize * 0.62
            )
            .frame(width: squareSize, height: squareSize)
            .position(point(for: king, squareSize: squareSize))
        }
    }

    private func legalMoveHints(squareSize: CGFloat) -> some View {
        ForEach(Array(legalDestinations), id: \.self) { square in
            Group {
                if position[square] == nil && !isEnPassantTarget(square) {
                    Circle()
                        .fill(.black.opacity(0.16))
                        .frame(width: squareSize * 0.33, height: squareSize * 0.33)
                } else {
                    Circle()
                        .strokeBorder(.black.opacity(0.16), lineWidth: squareSize * 0.09)
                        .frame(width: squareSize * 0.96, height: squareSize * 0.96)
                }
            }
            .position(point(for: square, squareSize: squareSize))
        }
    }

    private func pieces(squareSize: CGFloat) -> some View {
        ForEach(renderedPieces) { rendered in
            ChessPieceView(piece: rendered.piece, pieceSet: pieceSet)
                .frame(width: squareSize, height: squareSize)
                .position(point(for: rendered.square, squareSize: squareSize))
                .zIndex(rendered.id == movingPieceID ? 1 : 0)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private func cursor(squareSize: CGFloat) -> some View {
        if let cursorSquare {
            let width = max(3, squareSize * 0.055)
            ZStack {
                Rectangle().strokeBorder(.white, lineWidth: width)
                // Thin dark inner line keeps the cursor visible on light squares.
                Rectangle()
                    .strokeBorder(.black.opacity(0.35), lineWidth: max(1, width * 0.3))
                    .padding(width)
            }
            .frame(width: squareSize, height: squareSize)
            .position(point(for: cursorSquare, squareSize: squareSize))
            .animation(.easeOut(duration: 0.1), value: cursorSquare)
            .allowsHitTesting(false)
        }
    }

    // MARK: Geometry and colors

    private func square(column: Int, row: Int) -> Square {
        isFlipped ? Square(file: 7 - column, rank: row) : Square(file: column, rank: 7 - row)
    }

    private func point(for square: Square, squareSize: CGFloat) -> CGPoint {
        let column = isFlipped ? 7 - square.file : square.file
        let row = isFlipped ? square.rank : 7 - square.rank
        return CGPoint(x: (CGFloat(column) + 0.5) * squareSize, y: (CGFloat(row) + 0.5) * squareSize)
    }

    private func fill(for square: Square) -> Color {
        if square == selectedSquare { return theme.selected(light: square.isLight) }
        if let lastMove, square == lastMove.from || square == lastMove.to { return theme.lastMove(light: square.isLight) }
        return theme.squareColor(isLight: square.isLight)
    }

    private var checkedKingSquare: Square? {
        let side = position.sideToMove
        guard position.isInCheck(side) else { return nil }
        return position.board.first { $0.value == Piece(type: .king, color: side) }?.key
    }

    private func isEnPassantTarget(_ square: Square) -> Bool {
        guard let selectedSquare, position[selectedSquare]?.type == .pawn else { return false }
        return square == position.enPassantTarget
    }

    private func fileName(_ file: Int) -> String {
        String(UnicodeScalar(UInt8(97 + file)))
    }

    // MARK: Piece animation

    private func updateRenderedPieces(from oldPosition: ChessPosition, to newPosition: ChessPosition) {
        // Slide only when the new position is exactly `lastMove` played from the old one;
        // anything else (undo, jumps in review) reconciles in place and fades changes.
        let playedMove = lastMove.flatMap { move in
            (try? oldPosition.applying(move))?.board == newPosition.board ? move : nil
        }
        let movingID = playedMove.flatMap { move in renderedPieces.first { $0.square == move.from }?.id }
        let changes = {
            if let move = playedMove { slide(move, in: newPosition) }
            reconcile(with: newPosition)
        }
        guard animateMoves else {
            movingPieceID = nil
            changes()
            return
        }
        movingPieceID = movingID
        withAnimation(.easeInOut(duration: 0.22)) { changes() }
    }

    private func slide(_ move: ChessMove, in newPosition: ChessPosition) {
        guard let mover = renderedPieces.first(where: { $0.square == move.from }),
              let finalPiece = newPosition[move.to] else { return }
        // Remove the captured piece first (on the target square, or behind it for en passant).
        renderedPieces.removeAll { $0.square == move.to }
        if mover.piece.type == .pawn, move.from.file != move.to.file {
            let passedPawn = Square(file: move.to.file, rank: move.from.rank)
            if newPosition[passedPawn] == nil { renderedPieces.removeAll { $0.square == passedPawn } }
        }
        guard let index = renderedPieces.firstIndex(where: { $0.square == move.from }) else { return }
        renderedPieces[index].square = move.to
        renderedPieces[index].piece = finalPiece
        if finalPiece.type == .king, abs(move.to.file - move.from.file) == 2 {
            let rookFrom = Square(file: move.to.file == 6 ? 7 : 0, rank: move.from.rank)
            let rookTo = Square(file: move.to.file == 6 ? 5 : 3, rank: move.from.rank)
            if let rookIndex = renderedPieces.firstIndex(where: { $0.square == rookFrom }) {
                renderedPieces[rookIndex].square = rookTo
            }
        }
    }

    /// Makes `renderedPieces` match `newPosition`, keeping the identity of unchanged pieces.
    private func reconcile(with newPosition: ChessPosition) {
        var seen = Set<Square>()
        renderedPieces.removeAll { rendered in
            newPosition[rendered.square] != rendered.piece || !seen.insert(rendered.square).inserted
        }
        for (square, piece) in newPosition.board where !seen.contains(square) {
            renderedPieces.append(RenderedPiece(piece: piece, square: square))
        }
    }
}

private struct RenderedPiece: Identifiable {
    let id = UUID()
    var piece: Piece
    var square: Square

    static func all(in position: ChessPosition) -> [RenderedPiece] {
        position.board
            .sorted { $0.key < $1.key }
            .map { RenderedPiece(piece: $0.value, square: $0.key) }
    }
}
