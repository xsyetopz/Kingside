import SwiftUI
import ChessCore

// Interactive board for the Siri Remote: one focusable view with a square cursor.
//   ChessBoardView(position: game.position, interaction: controller,
//                  boardTheme: .green, arrows: [...], badges: [...],
//                  isInputEnabled: !menuShown, onSelect: vm.select, onCancel: vm.cancel)
// `BoardInteractionController` owns the cursor, selection, legal moves, last move and flip.
// D-pad/swipes move the cursor, Select calls `onSelect`, Menu/Back calls `onCancel`; game
// controllers are forwarded too. The cursor is shown only while the board has focus.
// `onMoveOffEdge` (optional) gets a D-pad move that would leave the board; return true to let
// focus go (for example to a side panel), false to keep the board focused.
// For a non-interactive board (review, thumbnails) use `ChessBoardDisplay`.

struct ChessBoardView: View {
    let position: ChessPosition
    @ObservedObject var interaction: BoardInteractionController
    var showLegalMoves = true
    var showCoordinates = true
    var highlightLastMove = true
    var animateMoves = true
    var boardTheme: BoardTheme = .green
    var pieceSet: PieceSet = .cburnett
    var arrows: [BoardArrow] = []
    var badges: [BoardBadge] = []
    var isInputEnabled = true
    let onSelect: () -> Void
    let onCancel: () -> Void
    var onMoveOffEdge: ((MoveCommandDirection) -> Bool)? = nil

    @FocusState private var boardHasFocus: Bool
    @StateObject private var controllerInput = GameControllerInput()
    @State private var acceptsControllerInput = true

    var body: some View {
        ChessBoardDisplay(
            position: position,
            lastMove: highlightLastMove ? interaction.lastMove : nil,
            isFlipped: interaction.isFlipped,
            theme: boardTheme,
            pieceSet: pieceSet,
            showCoordinates: showCoordinates,
            animateMoves: animateMoves,
            arrows: arrows,
            badges: badges,
            selectedSquare: interaction.selectedSquare,
            legalDestinations: showLegalMoves ? interaction.legalDestinations : [],
            cursorSquare: boardHasFocus ? interaction.focusedSquare : nil
        )
        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
        .contentShape(Rectangle())
        .focusable(isInputEnabled)
        .focused($boardHasFocus)
        .onMoveCommand { direction in
            guard isInputEnabled else { return }
            let previousSquare = interaction.focusedSquare
            interaction.moveFocus(direction)
            if interaction.focusedSquare == previousSquare, onMoveOffEdge?(direction) == true { return }
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
        }
        .onDisappear { controllerInput.stop() }
        .onChange(of: isInputEnabled) { _, enabled in
            acceptsControllerInput = enabled
            boardHasFocus = enabled
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
}
