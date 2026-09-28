import SwiftUI
import ChessCore

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Form {
            Section("Board") {
                Picker("Board Theme", selection: binding(\.boardTheme)) {
                    ForEach(BoardTheme.allCases) { Text($0.title).tag($0) }
                }
                Picker("Piece Theme", selection: binding(\.pieceTheme)) {
                    ForEach(PieceTheme.allCases) { Text($0.title).tag($0) }
                }
                Picker("Board Orientation", selection: binding(\.orientation)) {
                    ForEach(BoardOrientation.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show Legal Moves", isOn: binding(\.showLegalMoves))
                Toggle("Show Coordinates", isOn: binding(\.showCoordinates))
            }
            Section("Game") {
                Picker("Engine Difficulty", selection: binding(\.engineDifficulty)) {
                    ForEach(EngineDifficulty.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                Toggle("Sound Effects", isOn: binding(\.soundEffects))
                Toggle("Move Animation", isOn: binding(\.moveAnimation))
                Toggle("24-Hour Clock", isOn: binding(\.clockStyle24Hour))
            }
        }
        .navigationTitle("Settings")
        .chessScreen()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { settings.value[keyPath: keyPath] }, set: { settings.value[keyPath: keyPath] = $0 })
    }
}
