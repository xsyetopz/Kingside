import ChessContent
import ChessPlay
import SwiftUI

/// The Games tab: saved games, newest first. A finished game opens its review and an unfinished
/// one continues.
struct GamesHome: View {
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization

    var body: some View {
        Group {
            if model.savedGames.isEmpty {
                ContentUnavailableView(
                    localization("games.empty.title"), systemImage: "clock.arrow.circlepath",
                    description: Text(localization("games.empty.detail")))
            } else {
                WidthAdaptive {
                    List(model.savedGames) { game in
                        NavigationLink(value: route(game)) {
                            GameRow(game: game)
                        }
                        .contextMenu { actions(for: game) }
                        #if !os(tvOS)
                        .swipeActions(edge: .trailing) {
                            Button(localization("games.action.delete"), systemImage: "trash", role: .destructive) {
                                delete(game)
                            }
                        }
                        #endif
                    }
                } wide: {
                    CardGrid {
                        ForEach(model.savedGames) { game in
                            NavigationLink(value: route(game)) {
                                GameCard(game: game)
                            }
                            .cardButtonStyle()
                            .contextMenu { actions(for: game) }
                        }
                    }
                }
            }
        }
        .screenTitle(localization("section.games.title"))
    }

    /// A finished game opens its review; an unfinished one continues.
    private func route(_ game: SavedGame) -> AppRoute {
        game.isFinished ? .review(game.id) : .game(.saved(game))
    }

    @ViewBuilder private func actions(for game: SavedGame) -> some View {
        NavigationLink(
            localization(game.isFinished ? "games.action.review" : "games.action.continue"), value: route(game))
        #if !os(tvOS)
        ShareLink(item: game.pgn) {
            Label(localization("games.action.sharePGN"), systemImage: "square.and.arrow.up")
        }
        #endif
        Button(localization("games.action.delete"), systemImage: "trash", role: .destructive) { delete(game) }
    }

    private func delete(_ game: SavedGame) {
        Task {
            try? await model.gameStore.delete(id: game.id)
            await model.reloadGames()
        }
    }
}

/// One saved game: the opponent, and the result, move count, and date. Unfinished games say
/// what the row does.
private struct GameRow: View {
    let game: SavedGame
    @Environment(\.localization) private var localization
    @Environment(\.locale) private var locale

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(GamesLayout.title(game, localization: localization))
                Text(GamesLayout.detail(game, localization: localization, locale: locale))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if !game.isFinished {
                Text(localization("games.action.continue")).foregroundStyle(.tint)
            }
        }
    }
}

/// One saved game as a card: its last position, the players, and the result line.
private struct GameCard: View {
    let game: SavedGame
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization
    @Environment(\.locale) private var locale

    var body: some View {
        let style = model.catalog.interface
        CardLabel(
            title: GamesLayout.title(game, localization: localization),
            subtitle: GamesLayout.detail(game, localization: localization, locale: locale),
            detail: game.isFinished ? nil : localization("games.action.continue")
        ) {
            BoardThumbnail(
                position: game.game.position, flipped: game.humanColor == .black,
                side: style.home.thumbnailSize * style.platformScale)
        }
    }
}
