import SwiftUI
import ChessCore

struct ChessBoardView: View {
    let position: ChessPosition
    @ObservedObject var interaction: BoardInteractionController
    let showLegalMoves: Bool
    let showCoordinates: Bool
    let animateMoves: Bool
    var boardTheme: BoardTheme = .midnight
    var pieceTheme: PieceTheme = .modern
    var isInputEnabled = true
    let onSelect: () -> Void
    let onCancel: () -> Void

    @FocusState private var boardHasFocus: Bool
    @StateObject private var controllerInput = GameControllerInput()
    @State private var renderedPieces: [RenderedPiece] = []
    @State private var acceptsControllerInput = true
    @State private var highlightPulse = false
    @State private var bouncingPieceID: UUID?
    @State private var bounceToken = UUID()

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let squareSize = side / 8
            ZStack(alignment: .topLeading) {
                boardSquares(squareSize: squareSize)
                lastMoveHighlights(squareSize: squareSize)
                legalMoveMarkers(squareSize: squareSize)
                pieces(squareSize: squareSize)
                focusOverlay(squareSize: squareSize)
                if showCoordinates { coordinates(squareSize: squareSize) }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(boardTheme.edgeColor, lineWidth: 10)
                        .padding(5)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(boardHasFocus ? .white : .white.opacity(0.20), lineWidth: boardHasFocus ? 5 : 2)
                }
            }
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [boardTheme.edgeColor.opacity(0.95), .black.opacity(0.92)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .offset(y: 18)
                    .shadow(color: .black.opacity(0.8), radius: 18, y: 18)
            }
            .shadow(color: boardHasFocus ? ChessTheme.accent.opacity(0.16) : .clear, radius: 30)
            .shadow(color: .black.opacity(0.62), radius: 30, y: 18)
            .scaleEffect(0.965)
            .rotation3DEffect(
                .degrees(5.5),
                axis: (x: 1, y: 0, z: 0),
                anchor: .center,
                perspective: 0.16
            )
            .rotation3DEffect(
                .degrees((Double(interaction.focusedSquare.file) - 3.5) * 0.28),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                perspective: 0.10
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: interaction.focusedSquare)
            .contentShape(Rectangle())
            .focusable(isInputEnabled)
            .focused($boardHasFocus)
            .onMoveCommand { direction in
                guard isInputEnabled else { return }
                interaction.moveFocus(direction)
                // Explicitly retain the board as the focus owner. This prevents
                // the tvOS focus engine from treating an edge move as navigation
                // to controls outside the board.
                boardHasFocus = true
            }
            .onTapGesture {
                guard isInputEnabled else { return }
                onSelect()
            }
            .onExitCommand {
                guard isInputEnabled else { return }
                onCancel()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier("chess-board")
            .accessibilityLabel(accessibilityDescription)
            .accessibilityHint("Use directional controls to move. Press Select to select or move. Press Back to cancel selection.")
            .accessibilityAddTraits(.isButton)
            .onAppear {
                acceptsControllerInput = isInputEnabled
                boardHasFocus = isInputEnabled
                renderedPieces = position.board.map { RenderedPiece(piece: $0.value, square: $0.key) }
                controllerInput.moveHandler = { direction in
                    guard acceptsControllerInput else { return }
                    interaction.moveFocus(direction)
                }
                controllerInput.primaryHandler = {
                    guard acceptsControllerInput else { return }
                    onSelect()
                }
                controllerInput.secondaryHandler = {
                    guard acceptsControllerInput else { return }
                    onCancel()
                }
                controllerInput.start()
                withAnimation(.easeInOut(duration: 1.05).repeatForever(autoreverses: true)) {
                    highlightPulse = true
                }
            }
            .onDisappear { controllerInput.stop() }
            .onChange(of: isInputEnabled) { _, enabled in
                acceptsControllerInput = enabled
                boardHasFocus = enabled
            }
            .onChange(of: position) { _, newPosition in updateRenderedPieces(to: newPosition) }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func lastMoveHighlights(squareSize: CGFloat) -> some View {
        if let move = interaction.lastMove {
            ForEach([move.from, move.to], id: \.self) { square in
                RoundedRectangle(cornerRadius: squareSize * 0.07)
                    .fill(ChessTheme.accentWarm.opacity(0.52))
                    .overlay {
                        RoundedRectangle(cornerRadius: squareSize * 0.07)
                            .stroke(ChessTheme.accentWarm.opacity(0.8), lineWidth: 2)
                    }
                    .frame(width: squareSize, height: squareSize)
                    .position(displayPoint(for: square, squareSize: squareSize))
            }
        }
    }

    @ViewBuilder
    private func boardSquares(squareSize: CGFloat) -> some View {
        ForEach(0..<64, id: \.self) { index in
            let square = Square(file: index % 8, rank: index / 8)
            let point = displayPoint(for: square, squareSize: squareSize)
            let color = squareColor(square)
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [color.opacity(0.96), color, color.opacity(0.88)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay { Rectangle().stroke(.black.opacity(0.055), lineWidth: 1) }
                .frame(width: squareSize, height: squareSize)
                .position(x: point.x, y: point.y)
        }
    }

    @ViewBuilder
    private func legalMoveMarkers(squareSize: CGFloat) -> some View {
        if showLegalMoves {
            ForEach(Array(interaction.legalDestinations), id: \.self) { square in
                let point = displayPoint(for: square, squareSize: squareSize)
                if position[square] == nil {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.94), ChessTheme.legal.opacity(0.92)],
                                center: .center,
                                startRadius: 0,
                                endRadius: squareSize * 0.14
                            )
                        )
                        .frame(width: squareSize * 0.22, height: squareSize * 0.22)
                        .overlay { Circle().stroke(.white.opacity(0.66), lineWidth: 2) }
                        .shadow(color: ChessTheme.legal.opacity(0.72), radius: highlightPulse ? 12 : 5)
                        .scaleEffect(highlightPulse ? 1.12 : 0.90)
                        .position(point)
                } else {
                    Circle()
                        .stroke(ChessTheme.legal.opacity(0.94), lineWidth: squareSize * 0.075)
                        .frame(width: squareSize * 0.80, height: squareSize * 0.80)
                        .shadow(color: ChessTheme.legal.opacity(0.72), radius: highlightPulse ? 12 : 5)
                        .scaleEffect(highlightPulse ? 1.04 : 0.92)
                        .position(point)
                }
            }
        }
    }

    @ViewBuilder
    private func pieces(squareSize: CGFloat) -> some View {
        ForEach(renderedPieces) { rendered in
            ChessPieceView(
                piece: rendered.piece,
                theme: pieceTheme,
                isSelected: interaction.selectedSquare == rendered.square,
                isFocused: interaction.focusedSquare == rendered.square,
                isLegalTarget: interaction.legalDestinations.contains(rendered.square),
                isMoving: bouncingPieceID == rendered.id,
                pulse: highlightPulse
            )
                .frame(width: squareSize * 0.92, height: squareSize * 0.92)
                .position(displayPoint(for: rendered.square, squareSize: squareSize))
        }
    }

    @ViewBuilder
    private func focusOverlay(squareSize: CGFloat) -> some View {
        let point = displayPoint(for: interaction.focusedSquare, squareSize: squareSize)
        ZStack {
            RoundedRectangle(cornerRadius: squareSize * 0.09)
                .fill(
                    RadialGradient(
                        colors: [ChessTheme.accent.opacity(0.20), .white.opacity(0.035)],
                        center: .center,
                        startRadius: 0,
                        endRadius: squareSize * 0.62
                    )
                )
            RoundedRectangle(cornerRadius: squareSize * 0.09)
                .stroke(.white.opacity(0.52), lineWidth: 1.5)
            FocusCornerReticle()
                .stroke(ChessTheme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                .padding(3)
        }
        .frame(width: squareSize - 8, height: squareSize - 8)
        .position(point)
        .shadow(color: ChessTheme.accent.opacity(0.64), radius: boardHasFocus ? 10 : 4)
        .animation(.easeOut(duration: 0.09), value: interaction.focusedSquare)
    }

    @ViewBuilder
    private func coordinates(squareSize: CGFloat) -> some View {
        ForEach(0..<8, id: \.self) { displayFile in
            let actualFile = interaction.isFlipped ? 7 - displayFile : displayFile
            Text(fileName(actualFile))
                .font(.caption2.bold())
                .foregroundStyle(coordinateColor(file: actualFile, rank: interaction.isFlipped ? 7 : 0))
                .position(x: CGFloat(displayFile) * squareSize + squareSize * 0.87, y: 8 * squareSize - 12)
        }
        ForEach(0..<8, id: \.self) { displayRank in
            let actualRank = interaction.isFlipped ? displayRank : 7 - displayRank
            Text("\(actualRank + 1)")
                .font(.caption2.bold())
                .foregroundStyle(coordinateColor(file: interaction.isFlipped ? 7 : 0, rank: actualRank))
                .position(x: 11, y: CGFloat(displayRank) * squareSize + 13)
        }
    }

    private func squareColor(_ square: Square) -> Color {
        if let king = position.board.first(where: { $0.value.type == .king && $0.value.color == position.sideToMove })?.key,
           king == square, position.isInCheck(position.sideToMove) { return ChessTheme.danger.opacity(0.9) }
        if interaction.selectedSquare == square { return ChessTheme.selected }
        return (square.file + square.rank).isMultiple(of: 2) ? boardTheme.darkSquareColor : boardTheme.lightSquareColor
    }

    private func coordinateColor(file: Int, rank: Int) -> Color {
        (file + rank).isMultiple(of: 2) ? .white.opacity(0.72) : .black.opacity(0.58)
    }

    private func displayPoint(for square: Square, squareSize: CGFloat) -> CGPoint {
        let column = interaction.isFlipped ? 7 - square.file : square.file
        let row = interaction.isFlipped ? square.rank : 7 - square.rank
        return CGPoint(x: (CGFloat(column) + 0.5) * squareSize, y: (CGFloat(row) + 0.5) * squareSize)
    }

    private func updateRenderedPieces(to newPosition: ChessPosition) {
        let movingPieceID = interaction.lastMove.flatMap { move in
            renderedPieces.first(where: { $0.square == move.from })?.id
        }
        let changes = {
            guard let move = interaction.lastMove else {
                renderedPieces = newPosition.board.map { RenderedPiece(piece: $0.value, square: $0.key) }
                return
            }
            let rookFrom = abs(move.to.file - move.from.file) == 2 && newPosition[move.to]?.type == .king
                ? Square(file: move.to.file == 6 ? 7 : 0, rank: move.from.rank)
                : nil
            renderedPieces.removeAll { rendered in
                rendered.square != move.from && rendered.square != rookFrom && newPosition[rendered.square] != rendered.piece
            }
            if let index = renderedPieces.firstIndex(where: { $0.square == move.from }), let finalPiece = newPosition[move.to] {
                renderedPieces[index].square = move.to
                renderedPieces[index].piece = finalPiece
            }
            if abs(move.to.file - move.from.file) == 2, newPosition[move.to]?.type == .king {
                let rookFrom = Square(file: move.to.file == 6 ? 7 : 0, rank: move.from.rank)
                let rookTo = Square(file: move.to.file == 6 ? 5 : 3, rank: move.from.rank)
                if let rookIndex = renderedPieces.firstIndex(where: { $0.square == rookFrom }) { renderedPieces[rookIndex].square = rookTo }
            }
            for (square, piece) in newPosition.board where !renderedPieces.contains(where: { $0.square == square }) {
                renderedPieces.append(RenderedPiece(piece: piece, square: square))
            }
        }
        if animateMoves, let movingPieceID {
            let token = UUID()
            bounceToken = token
            withAnimation(.easeInOut(duration: 0.30)) {
                bouncingPieceID = movingPieceID
                changes()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                guard bounceToken == token else { return }
                withAnimation(.interpolatingSpring(mass: 0.72, stiffness: 250, damping: 10, initialVelocity: 1.8)) {
                    bouncingPieceID = nil
                }
            }
        } else {
            bouncingPieceID = nil
            changes()
        }
    }

    private var accessibilityDescription: String {
        let square = interaction.focusedSquare
        let piece = position[square].map { "\($0.color.rawValue) \($0.type.rawValue)" } ?? "empty"
        let selection = interaction.selectedSquare.map { ", selected \($0.algebraic)" } ?? ""
        let legality = interaction.legalDestinations.contains(square) ? ", legal destination" : ""
        let check = position.isInCheck(position.sideToMove) ? ", \(position.sideToMove.rawValue) king is in check" : ""
        return "\(square.algebraic), \(piece)\(selection)\(legality)\(check)"
    }

    private func fileName(_ file: Int) -> String {
        String(Character(UnicodeScalar(file + 97)!))
    }
}

private struct RenderedPiece: Identifiable {
    let id = UUID()
    var piece: Piece
    var square: Square
}

private struct FocusCornerReticle: Shape {
    func path(in rect: CGRect) -> Path {
        let length = min(rect.width, rect.height) * 0.24
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))

        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))

        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))

        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}
