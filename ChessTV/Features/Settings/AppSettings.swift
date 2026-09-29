import Foundation
import ChessCore

enum BoardOrientation: String, Codable, CaseIterable, Identifiable {
    case white, black, automatic
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AppSettings: Codable, Equatable {
    var boardTheme: BoardTheme = .green
    var pieceSet: PieceSet = .cburnett
    var orientation: BoardOrientation = .automatic
    var soundEffects = true
    var moveAnimation = true
    var showLegalMoves = true
    var showCoordinates = true
    var highlightLastMove = true
    /// Promote straight to a queen instead of showing the promotion picker.
    var autoPromoteToQueen = false

    init() {}

    /// Missing keys and values this build does not know keep their defaults, so saved
    /// settings from older or newer builds never reset everything.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        let defaults = AppSettings()
        boardTheme = value(.boardTheme, defaults.boardTheme)
        pieceSet = value(.pieceSet, defaults.pieceSet)
        orientation = value(.orientation, defaults.orientation)
        soundEffects = value(.soundEffects, defaults.soundEffects)
        moveAnimation = value(.moveAnimation, defaults.moveAnimation)
        showLegalMoves = value(.showLegalMoves, defaults.showLegalMoves)
        showCoordinates = value(.showCoordinates, defaults.showCoordinates)
        highlightLastMove = value(.highlightLastMove, defaults.highlightLastMove)
        autoPromoteToQueen = value(.autoPromoteToQueen, defaults.autoPromoteToQueen)
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: AppSettings { didSet { save() } }
    private let defaults: UserDefaults
    private let key = "ChessTV.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = decoded
        } else { value = AppSettings() }
    }

    /// The sound effects switch; `AppContainer` applies it to `SoundEffects.shared`.
    var soundEnabled: Bool {
        get { value.soundEffects }
        set { value.soundEffects = newValue }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
