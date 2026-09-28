import SwiftUI
import ChessCore

struct GameView: View {
    @ObservedObject var viewModel: GameViewModel
    let onExit: () -> Void
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        ZStack {
            HStack(spacing: 48) {
                ChessBoardView(
                    position: viewModel.game.position,
                    interaction: viewModel.board,
                    showLegalMoves: settings.value.showLegalMoves,
                    showCoordinates: settings.value.showCoordinates,
                    animateMoves: settings.value.moveAnimation,
                    boardTheme: settings.value.boardTheme,
                    pieceTheme: settings.value.pieceTheme,
                    isInputEnabled: viewModel.pendingPromotion.isEmpty && !viewModel.showsGameMenu,
                    onSelect: viewModel.selectSquare,
                    onCancel: viewModel.cancelSelection
                )
                .frame(maxWidth: 860, maxHeight: 860)

                VStack(alignment: .leading, spacing: 24) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("CHESS").font(.title.bold())
                            Text("LOCAL • VS COMPUTER")
                                .font(.caption.bold())
                                .tracking(2.2)
                                .foregroundStyle(ChessTheme.accent)
                        }
                        Spacer()
                        if viewModel.isThinking { ProgressView().tint(ChessTheme.accent) }
                    }
                    ClockView(color: .black, seconds: viewModel.blackTime, active: viewModel.game.position.sideToMove == .black, enabled: viewModel.configuration.initialTime > 0)
                    ClockView(color: .white, seconds: viewModel.whiteTime, active: viewModel.game.position.sideToMove == .white, enabled: viewModel.configuration.initialTime > 0)
                    Text(viewModel.statusText)
                        .font(.title3.bold())
                        .foregroundStyle(viewModel.game.position.isInCheck(viewModel.game.position.sideToMove) ? ChessTheme.danger : .white)
                        .accessibilityLabel("Game status: \(viewModel.statusText)")
                    MoveListView(moves: viewModel.game.moves)
                    Label("Press Back for Game Menu", systemImage: "menucard")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Press Back for game menu")
                }
                .padding(26)
                .frame(width: 470)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                }
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 34)

            if !viewModel.pendingPromotion.isEmpty { PromotionOverlay(viewModel: viewModel) }
            if viewModel.showsGameMenu { GameMenuOverlay(viewModel: viewModel, onExit: onExit) }
        }
        .chessScreen()
        .alert("CHESS", isPresented: Binding(get: { viewModel.message != nil }, set: { if !$0 { viewModel.message = nil } })) {
            Button("OK", role: .cancel) { viewModel.message = nil }
        } message: { Text(viewModel.message ?? "") }
    }
}

private struct ClockView: View {
    let color: PieceColor
    let seconds: TimeInterval
    let active: Bool
    let enabled: Bool

    var body: some View {
        HStack {
            Circle().fill(color == .white ? Color.white : Color.black).frame(width: 22, height: 22)
                .overlay { Circle().stroke(.white.opacity(0.35), lineWidth: 1) }
            Text(color.rawValue.capitalized).font(.headline)
            Spacer()
            Text(formatted)
                .font(.system(size: 42, weight: .bold, design: .monospaced))
                .monospacedDigit()
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 15)
        .background(active ? ChessTheme.surfaceRaised : ChessTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(active ? ChessTheme.accent : .clear, lineWidth: 3) }
        .accessibilityLabel("\(color.rawValue) clock, \(formatted)")
    }

    private var formatted: String {
        if !enabled { return "∞" }
        return String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct MoveListView: View {
    let moves: [PlayedMove]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 9) {
                    ForEach(Array(stride(from: 0, to: moves.count, by: 2)), id: \.self) { index in
                        HStack {
                            Text("\(index / 2 + 1).")
                                .foregroundStyle(.secondary)
                                .frame(width: 45, alignment: .trailing)
                            Text(moves[index].san).frame(maxWidth: .infinity, alignment: .leading)
                            Text(index + 1 < moves.count ? moves[index + 1].san : "")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(.title3.monospaced())
                        .id(index)
                    }
                }
            }
            .onChange(of: moves.count) { _, count in
                if count > 0 { withAnimation { proxy.scrollTo((count - 1) / 2 * 2, anchor: .bottom) } }
            }
        }
        .frame(maxHeight: 330)
        .padding(18)
        .background(.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 18))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Move list")
    }
}

private struct PromotionOverlay: View {
    @ObservedObject var viewModel: GameViewModel
    @FocusState private var focused: PieceType?
    private let types: [PieceType] = [.queen, .rook, .bishop, .knight]

    var body: some View {
        VStack(spacing: 26) {
            Text("Choose promotion").font(.largeTitle.bold())
            HStack(spacing: 22) {
                ForEach(types, id: \.self) { type in
                    Button(type.rawValue.capitalized) { viewModel.choosePromotion(type) }
                        .focused($focused, equals: type)
                        .buttonStyle(.borderedProminent)
                }
            }
            Button("Cancel", role: .cancel, action: viewModel.cancelSelection)
        }
        .padding(48)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(ChessTheme.accent, lineWidth: 3) }
        .onAppear { focused = .queen }
    }
}

private struct GameMenuOverlay: View {
    @ObservedObject var viewModel: GameViewModel
    let onExit: () -> Void
    @FocusState private var focused: Int?

    var body: some View {
        VStack(spacing: 20) {
            Text("Game Menu").font(.largeTitle.bold())
            Button("Resume") { viewModel.showsGameMenu = false }.focused($focused, equals: 0)
            Button("Undo Move") { viewModel.undo(); viewModel.showsGameMenu = false }
                .disabled(viewModel.game.moves.isEmpty || viewModel.isThinking)
                .focused($focused, equals: 1)
            Button("Flip Board") { viewModel.flipBoard(); viewModel.showsGameMenu = false }.focused($focused, equals: 2)
            Button("Restart Game", role: .destructive) { viewModel.restart(); viewModel.showsGameMenu = false }.focused($focused, equals: 3)
            Button("Exit to Home") { viewModel.showsGameMenu = false; onExit() }.focused($focused, equals: 4)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .padding(50)
        .frame(width: 430)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
        .onAppear { focused = 0 }
        .onExitCommand { viewModel.showsGameMenu = false }
    }
}
