import Combine
import SwiftUI
import ChessCore

@main
struct ChessTVApp: App {
    @StateObject private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.settings)
                .preferredColorScheme(.dark)
        }
    }
}

@MainActor
final class AppContainer: ObservableObject {
    /// The in-progress game offered by Resume on Home; nil when there is none.
    @Published var unfinishedGame: SavedGame?

    let settings: SettingsStore
    let gameStore: GamePersistenceStore
    let engine: ChessEngine
    private var soundSubscription: AnyCancellable?

    init(engine: ChessEngine = ChessEngine()) {
        self.engine = engine
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            let identifier = "ChessTV.UITests.\(ProcessInfo.processInfo.processIdentifier)"
            settings = SettingsStore(defaults: UserDefaults(suiteName: identifier) ?? .standard)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(identifier, isDirectory: true)
            gameStore = GamePersistenceStore(directoryURL: directory)
        } else {
            settings = SettingsStore()
            gameStore = GamePersistenceStore()
        }
        SoundEffects.shared.isEnabled = settings.soundEnabled
        soundSubscription = settings.$value.map(\.soundEffects).removeDuplicates().sink { enabled in
            SoundEffects.shared.isEnabled = enabled
        }
        refreshSavedGame()
    }

    func makeGameViewModel(launch: GameLaunch) -> GameViewModel {
        GameViewModel(launch: launch, engine: engine, settings: settings, store: gameStore) { [weak self] in
            self?.refreshSavedGame()
        }
    }

    func refreshSavedGame() {
        Task { [weak self, gameStore = self.gameStore] in self?.unfinishedGame = await gameStore.unfinishedGame() }
    }
}
