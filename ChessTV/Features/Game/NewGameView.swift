import SwiftUI
import ChessCore

struct NewGameView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.scenePhase) private var scenePhase
    @Binding var path: [AppRoute]
    let resumesSavedGame: Bool
    @State private var configuration = GameConfiguration()
    @State private var gameViewModel: GameViewModel?
    @FocusState private var startButtonFocused: Bool

    var body: some View {
        Group {
            if let gameViewModel {
                GameView(viewModel: gameViewModel) {
                    container.refreshSavedGame()
                    if !path.isEmpty { path.removeLast() }
                }
            } else {
                setup
            }
        }
        .navigationBarBackButtonHidden(gameViewModel != nil)
        .onAppear {
            guard resumesSavedGame, gameViewModel == nil, let saved = container.unfinishedGame else { return }
            let model = container.makeGameViewModel()
            model.restore(saved)
            gameViewModel = model
        }
        .onChange(of: scenePhase) { _, phase in
            guard let gameViewModel else { return }
            switch phase {
            case .active:
                gameViewModel.resumeAfterInterruption()
            case .inactive, .background:
                gameViewModel.suspendAndSave()
            @unknown default:
                gameViewModel.suspendAndSave()
            }
        }
    }

    private var setup: some View {
        VStack(spacing: 34) {
            Text("New Game").font(.system(size: 52, weight: .bold, design: .rounded))
            HStack(spacing: 28) {
                settingCard("Play as") {
                    Picker("Color", selection: $configuration.humanColor) {
                        Text("White").tag(PieceColor.white)
                        Text("Black").tag(PieceColor.black)
                    }.pickerStyle(.segmented)
                }
                settingCard("Difficulty") {
                    Picker("Difficulty", selection: $configuration.difficulty) {
                        ForEach(EngineDifficulty.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                    }.pickerStyle(.menu)
                }
                settingCard("Clock") {
                    Picker("Clock", selection: $configuration.initialTime) {
                        Text("3 min").tag(TimeInterval(180))
                        Text("5 min").tag(TimeInterval(300))
                        Text("10 min").tag(TimeInterval(600))
                        Text("No clock").tag(TimeInterval(0))
                    }.pickerStyle(.menu)
                }
            }
            Button("Start Game") {
                settings.value.engineDifficulty = configuration.difficulty
                let model = container.makeGameViewModel()
                model.start(configuration: configuration)
                gameViewModel = model
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .focused($startButtonFocused)
        }
        .padding(80)
        .chessScreen()
        .onAppear {
            // Give the most common action a deterministic entry focus. Players can
            // move up to customize the game, or press Select to accept the defaults.
            startButtonFocused = true
        }
    }

    private func settingCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title).font(.title2.bold())
            content()
        }
        .padding(30)
        .frame(maxWidth: 390, minHeight: 170)
        .background(ChessTheme.surface, in: RoundedRectangle(cornerRadius: 24))
    }
}
