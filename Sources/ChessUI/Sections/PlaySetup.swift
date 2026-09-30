import ChessContent
import ChessCore
import ChessPlay

/// Builds the `GameSetup` the Play screens start a game with.
enum PlaySetup {
    /// The player's color; `random` picks between white and black when the choice is random.
    static func humanColor(
        for choice: BotColorChoice, random: () -> Bool = { Bool.random() }
    ) -> PieceColor {
        switch choice {
        case .white: .white
        case .black: .black
        case .random: random() ? .white : .black
        }
    }

    static func versus(
        _ bot: Bot, choice: BotColorChoice, localization: Localization, random: () -> Bool = { Bool.random() }
    ) -> GameSetup {
        .versus(bot, humanColor: humanColor(for: choice, random: random), localization: localization)
    }

    static func passAndPlay(preset: TimeControlPreset, autoFlip: Bool, localization: Localization) -> GameSetup {
        GameSetup(
            mode: .passAndPlay,
            white: PlayerInfo(name: localization.string("player.white.name")),
            black: PlayerInfo(name: localization.string("player.black.name")),
            timeControl: TimeControl(preset),
            autoFlip: autoFlip)
    }

    /// The presets of each category in catalog order; categories without a preset are left out.
    static func presetsByCategory(_ catalog: TimeControlCatalog) -> [(category: TimeControlCategory, presets: [TimeControlPreset])] {
        catalog.categories.compactMap { category in
            let presets = catalog.presets.filter { catalog.category(for: $0)?.id == category.id }
            return presets.isEmpty ? nil : (category, presets)
        }
    }
}
