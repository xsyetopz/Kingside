import SwiftUI

struct PuzzleLibraryView: View {
    @StateObject private var viewModel = PuzzleViewModel()
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var showsPuzzleMenu = false

    var body: some View {
        ZStack {
            HStack(spacing: 55) {
                ChessBoardView(
                    position: viewModel.position,
                    interaction: viewModel.board,
                    showLegalMoves: settings.value.showLegalMoves,
                    showCoordinates: settings.value.showCoordinates,
                    animateMoves: settings.value.moveAnimation,
                    boardTheme: settings.value.boardTheme,
                    pieceTheme: settings.value.pieceTheme,
                    isInputEnabled: !showsPuzzleMenu,
                    onSelect: viewModel.select,
                    onCancel: handleBack
                )
                .frame(maxWidth: 820, maxHeight: 820)
                VStack(alignment: .leading, spacing: 25) {
                    Text("Puzzle \(viewModel.index + 1)").font(.headline).foregroundStyle(ChessTheme.accent)
                    Text(viewModel.title).font(.largeTitle.bold())
                    Text("\(viewModel.sideToMove) to move").font(.title2)
                    Text(viewModel.feedback)
                        .font(.title2.bold())
                        .foregroundStyle(viewModel.isSolved ? ChessTheme.legal : .white)
                    if viewModel.isSolved {
                        Button("Next Puzzle", action: viewModel.next).buttonStyle(.borderedProminent)
                    } else {
                        Button("Retry", action: viewModel.retry).buttonStyle(.bordered)
                    }
                    Spacer()
                    Text("Move with the directional pad. Press Select to choose a piece and destination.")
                        .font(.headline).foregroundStyle(.secondary)
                    Label("Press Back for Puzzle Menu", systemImage: "menucard")
                        .font(.headline)
                        .foregroundStyle(ChessTheme.accent)
                }
                .frame(width: 430, alignment: .leading)
            }
            .padding(60)

            if showsPuzzleMenu {
                PuzzleMenuOverlay(
                    onResume: { showsPuzzleMenu = false },
                    onRetry: {
                        viewModel.retry()
                        showsPuzzleMenu = false
                    },
                    onExit: { dismiss() }
                )
            }
        }
        .navigationTitle("Puzzles")
        .chessScreen()
        .onAppear(perform: viewModel.load)
    }

    private func handleBack() {
        if viewModel.board.selectedSquare != nil {
            viewModel.board.cancelSelection()
        } else {
            showsPuzzleMenu = true
        }
    }
}

private struct PuzzleMenuOverlay: View {
    let onResume: () -> Void
    let onRetry: () -> Void
    let onExit: () -> Void
    @FocusState private var focusedAction: Int?

    var body: some View {
        VStack(spacing: 20) {
            Text("Puzzle Menu").font(.largeTitle.bold())
            Button("Resume", action: onResume)
                .focused($focusedAction, equals: 0)
            Button("Retry Puzzle", action: onRetry)
                .focused($focusedAction, equals: 1)
            Button("Exit Puzzles", action: onExit)
                .focused($focusedAction, equals: 2)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(50)
        .frame(width: 430)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(ChessTheme.accent, lineWidth: 2)
        }
        .onAppear { focusedAction = 0 }
        .onExitCommand(perform: onResume)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Puzzle menu")
    }
}
