import ChessBoardScene
import ChessContent
import ChessCore
import ChessFeedback
import ChessPlay
import SwiftUI

/// The Settings tab, and the macOS Settings window. On wide screens a live board preview sits
/// beside the form; elsewhere it is part of the Board section.
struct SettingsHome: View {
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization

    var body: some View {
        #if os(macOS)
        form(showsPreview: true)
        #else
        WidthAdaptive {
            form(showsPreview: true)
        } wide: {
            let style = model.catalog.interface
            HStack(alignment: .top, spacing: style.sectionGap) {
                BoardThumbnail(position: .initial, side: style.home.heroThumbnailSize * style.platformScale)
                    .padding(.top, style.sectionGap)
                form(showsPreview: false)
                    .frame(maxWidth: style.home.formMaxWidth * style.platformScale)
            }
            .padding(.leading, style.sectionGap)
            .frame(maxWidth: .infinity)
        }
        #endif
    }

    private func form(showsPreview: Bool) -> some View {
        @Bindable var settings = model.settings
        return Form {
            Section(localization("settings.board.title")) {
                appearanceChoices
                if showsPreview {
                    BoardThumbnail(position: .initial, side: model.catalog.interface.settings.previewSize)
                        .frame(maxWidth: .infinity)
                }
                Toggle(localization("settings.coordinates"), isOn: $settings.value.showCoordinates)
                Toggle(localization("settings.legalMoves"), isOn: $settings.value.showLegalMoves)
                Toggle(localization("settings.lastMove"), isOn: $settings.value.highlightLastMove)
            }
            Section(localization("settings.gameplay.title")) {
                Toggle(localization("settings.moveAnimation"), isOn: $settings.value.moveAnimation)
                Toggle(localization("settings.autoQueen"), isOn: $settings.value.autoPromoteToQueen)
                Toggle(localization("settings.onlineChat"), isOn: $settings.value.chatEnabled)
            }
            Section(localization("settings.soundHaptics.title")) {
                Toggle(localization("settings.soundEffects"), isOn: $settings.value.soundEffects)
                if HapticFeedback.isSupported {
                    Toggle(localization("settings.haptics"), isOn: $settings.value.haptics)
                }
            }
            Section(localization("settings.about.title")) {
                LabeledContent(localization("app.name"), value: version)
                NavigationLink(localization("settings.licenses")) { LicensesScreen() }
            }
        }
        .formStyle(.grouped)
        .screenTitle(localization("section.settings.title"))
    }

    #if os(macOS)
    @ViewBuilder private var appearanceChoices: some View {
        Picker(localization("settings.boardTheme"), selection: boardThemeID) {
            ForEach(model.catalog.boardThemes) { Text(localization($0.nameKey)).tag($0.id) }
        }
        Picker(localization("settings.pieceSet"), selection: pieceSetID) {
            ForEach(model.catalog.pieceSets) { Text(localization($0.nameKey)).tag($0.id) }
        }
        Picker(localization("settings.orientation.title"), selection: orientationID) {
            ForEach(BoardOrientation.allCases) { Text(localization($0.titleKey)).tag($0.id) }
        }
    }
    #else
    /// Pushed choosers, not pickers: on tvOS a picker's pushed list renders blank here.
    @ViewBuilder private var appearanceChoices: some View {
        let style = model.catalog.interface
        let side = style.home.thumbnailSize * style.platformScale
        choiceLink(localization("settings.boardTheme"), value: localization(model.boardTheme.nameKey)) {
            ChoiceScreen(
                title: localization("settings.boardTheme"), options: model.catalog.boardThemes,
                selection: boardThemeID, name: { localization($0.nameKey) }
            ) { theme in
                BoardThumbnail(position: .initial, side: side, theme: theme)
            }
        }
        choiceLink(localization("settings.pieceSet"), value: localization(model.pieceSet.nameKey)) {
            ChoiceScreen(
                title: localization("settings.pieceSet"), options: model.catalog.pieceSets,
                selection: pieceSetID, name: { localization($0.nameKey) }
            ) { set in
                PieceSetSample(pieceSet: set, side: side)
            }
        }
        choiceLink(
            localization("settings.orientation.title"), value: localization(model.settings.value.orientation.titleKey)
        ) {
            ChoiceScreen(
                title: localization("settings.orientation.title"), options: BoardOrientation.allCases,
                selection: orientationID, name: { localization($0.titleKey) }, isCompact: true
            ) { _ in
                EmptyView()
            }
        }
    }

    private func choiceLink(_ title: String, value: String, @ViewBuilder destination: () -> some View) -> some View {
        NavigationLink(destination: destination()) {
            LabeledContent(title, value: value)
        }
    }
    #endif

    private var orientationID: Binding<String> {
        Binding(
            get: { model.settings.value.orientation.id },
            set: { model.settings.value.orientation = BoardOrientation(rawValue: $0) ?? model.settings.value.orientation })
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    private var boardThemeID: Binding<String> {
        Binding(
            get: { model.settings.value.boardTheme(in: model.catalog)?.id ?? "" },
            set: { model.settings.value.boardTheme = $0 })
    }

    private var pieceSetID: Binding<String> {
        Binding(
            get: { model.settings.value.pieceSet(in: model.catalog)?.id ?? "" },
            set: { model.settings.value.pieceSet = $0 })
    }
}
