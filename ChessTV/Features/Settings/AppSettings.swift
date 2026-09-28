import Foundation
import ChessCore

enum BoardTheme: String, Codable, CaseIterable, Identifiable {
    case tournament, midnight, ocean, walnut
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum PieceTheme: String, Codable, CaseIterable, Identifiable {
    case classic, modern
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum BoardOrientation: String, Codable, CaseIterable, Identifiable {
    case white, black, automatic
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct AppSettings: Codable, Equatable {
    var boardTheme: BoardTheme = .tournament
    var pieceTheme: PieceTheme = .classic
    var orientation: BoardOrientation = .automatic
    var soundEffects = true
    var moveAnimation = true
    var showLegalMoves = true
    var showCoordinates = true
    var clockStyle24Hour = false
    var engineDifficulty: EngineDifficulty = .medium
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var value: AppSettings { didSet { save() } }
    private let defaults: UserDefaults
    private let key = "ChessTV.settings.v1"
    private let tournamentThemeMigrationKey = "ChessTV.settings.tournamentTheme.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            value = decoded
        } else { value = AppSettings() }
        if !defaults.bool(forKey: tournamentThemeMigrationKey) {
            value.boardTheme = .tournament
            value.pieceTheme = .classic
            defaults.set(true, forKey: tournamentThemeMigrationKey)
            save()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
