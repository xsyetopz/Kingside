import SwiftUI
import ChessCore

// Shared pieces of the puzzle screens:
// - `PuzzleBoardArea`: the interactive board with promotion picker, wired to `PuzzleBoardModel`.
//   A swipe off the right edge calls `onExitRight`; Back with nothing selected calls `onBack`.
// - `PuzzleStatusHeader`: the colored "White to Move" / "Correct" / "Incorrect" / "Solved" bar.
// - `PuzzleScreenLayout`: board on the left, a fixed-width panel on the right.

struct PuzzleBoardArea: View {
    @ObservedObject var model: PuzzleBoardModel
    let onExitRight: () -> Void
    let onBack: () -> Void
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ChessBoardView(
            position: model.position,
            interaction: model.board,
            showLegalMoves: settings.value.showLegalMoves,
            showCoordinates: settings.value.showCoordinates,
            highlightLastMove: settings.value.highlightLastMove,
            animateMoves: settings.value.moveAnimation,
            boardTheme: settings.value.boardTheme,
            pieceSet: settings.value.pieceSet,
            badges: model.badges,
            isInputEnabled: model.pendingPromotion.isEmpty,
            onSelect: model.select,
            onCancel: {
                if !model.cancelSelection() { onBack() }
            },
            onMoveOffEdge: { direction in
                guard direction == .right else { return false }
                onExitRight()
                return true
            }
        )
        .overlay {
            if let move = model.pendingPromotion.first {
                PromotionPickerOverlay(
                    square: move.to,
                    color: model.solverColor,
                    isFlipped: model.board.isFlipped,
                    onPick: model.choosePromotion,
                    onCancel: { _ = model.cancelSelection() }
                )
            }
        }
    }
}

struct PuzzleScreenLayout<Panel: View>: View {
    let board: PuzzleBoardArea
    @ViewBuilder let panel: () -> Panel

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            board.frame(width: 900, height: 900)
            VStack(alignment: .leading, spacing: 24, content: panel)
                .frame(width: 640, alignment: .topLeading)
                .frame(maxHeight: .infinity, alignment: .top)
                .chessPanel()
                .focusSection()
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
        .chessScreen()
    }
}

struct PuzzleStatusHeader: View {
    let phase: PuzzleSession.Phase
    let solverColor: PieceColor

    var body: some View {
        HStack(spacing: 16) {
            if phase == .intro || phase == .solverToMove {
                // The solver's king on a tile of the other color: a black disc vanishes on the black bar.
                PieceSet.cburnett.image(for: Piece(type: .king, color: solverColor))
                    .resizable()
                    .scaledToFit()
                    .padding(4)
                    .frame(width: 48, height: 48)
                    .background(
                        solverColor == .white ? Color(hex: 0x1B1A18) : Color(hex: 0xEEEED2),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
            } else {
                Image(systemName: icon).font(.system(size: 34, weight: .bold))
            }
            Text(title).font(ChessFont.heading)
            Spacer(minLength: 0)
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .background(background, in: RoundedRectangle(cornerRadius: ChessTheme.cornerRadius, style: .continuous))
    }

    private var toMove: String { solverColor == .white ? "White to Move" : "Black to Move" }

    private var title: String {
        switch phase {
        case .intro, .solverToMove: toMove
        case .opponentToMove: "Correct!"
        case .solved: "Solved!"
        case .failed: "Incorrect"
        case .revealing, .revealed: "Solution"
        }
    }

    private var icon: String {
        switch phase {
        case .intro, .solverToMove, .opponentToMove, .solved: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .revealing, .revealed: "eye.fill"
        }
    }

    private var background: Color {
        switch phase {
        case .intro, .solverToMove: solverColor == .white ? .white : Color(hex: 0x1B1A18)
        case .opponentToMove, .solved: ChessTheme.win
        case .failed: ChessTheme.loss
        case .revealing, .revealed: ChessTheme.raised
        }
    }

    private var foreground: Color {
        switch phase {
        case .intro, .solverToMove: solverColor == .white ? ChessTheme.clockActiveText : .white
        default: .white
        }
    }
}

/// Label/value row used in the puzzle panels.
struct PuzzleStatRow: View {
    let label: String
    let value: String
    var valueColor: Color = ChessTheme.textPrimary

    var body: some View {
        HStack {
            Text(label).font(ChessFont.body).foregroundStyle(ChessTheme.textSecondary)
            Spacer()
            Text(value).font(ChessFont.subheading).foregroundStyle(valueColor).monospacedDigit()
        }
    }
}
