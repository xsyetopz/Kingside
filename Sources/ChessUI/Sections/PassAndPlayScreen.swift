import ChessContent
import ChessPlay
import SwiftUI

/// Two people on one device: pick a time control, then start.
struct PassAndPlayScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization
    @State private var presetID: String?
    @State private var autoFlip = false
    @State private var launch: GameLaunch?

    var body: some View {
        let timeControls = model.catalog.timeControls
        let entries = PlaySetup.presetsByCategory(timeControls)
        WidthAdaptive {
            List {
                Section { autoFlipToggle }
                ForEach(entries, id: \.category.id) { entry in
                    Section(localization(entry.category.nameKey)) {
                        ForEach(entry.presets) { preset in
                            SetupRow(
                                title: localization(preset.labelKey), isSelected: preset.id == selectedPreset?.id
                            ) {
                                presetID = preset.id
                            } leading: {
                                Image(systemName: entry.category.symbol).foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
            .startBar(title: localization("passAndPlay.start"), isEnabled: selectedPreset != nil, action: start)
        } wide: {
            let style = model.catalog.interface
            SetupSplit {
                ScreenHeading(title: localization("play.passAndPlay.title"))
                BoardThumbnail(position: .initial, side: style.home.heroThumbnailSize * style.platformScale)
                    .frame(maxWidth: .infinity)
                if let preset = selectedPreset {
                    Text(localization(preset.labelKey)).font(.title.bold())
                }
                Text(localization("play.passAndPlay.detail")).foregroundStyle(.secondary)
                autoFlipToggle
                StartButton(title: localization("passAndPlay.start"), isEnabled: selectedPreset != nil, action: start)
            } options: {
                ForEach(entries, id: \.category.id) { entry in
                    CardSection(title: localization(entry.category.nameKey)) {
                        ForEach(entry.presets) { preset in
                            ChoiceTile(title: localization(preset.labelKey), isSelected: preset.id == selectedPreset?.id) {
                                presetID = preset.id
                            } artwork: {
                                Image(systemName: entry.category.symbol).font(.title2).foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
        .screenTitle(localization("play.passAndPlay.title"), chrome: .pushed)
        .navigationDestination(item: $launch) { launch in
            GameScreen(launch: launch)
        }
    }

    private var autoFlipToggle: some View {
        Toggle(localization("passAndPlay.autoFlip.title"), isOn: $autoFlip)
    }

    /// The chosen preset, or the untimed one before a choice is made.
    private var selectedPreset: TimeControlPreset? {
        let presets = model.catalog.timeControls.presets
        return presetID.flatMap { id in presets.first { $0.id == id } } ?? presets.first { !$0.isTimed }
    }

    private func start() {
        guard let preset = selectedPreset else { return }
        launch = .new(PlaySetup.passAndPlay(preset: preset, autoFlip: autoFlip, localization: localization))
    }
}
