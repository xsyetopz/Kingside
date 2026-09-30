import ChessContent
import ChessCore
import ChessPlay
import SwiftUI

/// The Play tab: continue the last game or start a new one. Each entry shows what it leads to:
/// the unfinished game's board, the bot that plays next, or the two-player mode.
struct PlayHome: View {
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization

    var body: some View {
        WidthAdaptive {
            List {
                if let game = model.unfinishedGame {
                    NavigationLink(value: AppRoute.game(.saved(game))) {
                        Label {
                            titled(localization("play.continue.title"), GamesLayout.title(game, localization: localization))
                        } icon: {
                            Image(systemName: "play.fill")
                        }
                    }
                }
                NavigationLink(value: AppRoute.bots) {
                    Label {
                        titled(localization("play.bots.title"), botSummary)
                    } icon: {
                        Image(systemName: "cpu")
                    }
                }
                .accessibilityIdentifier("play.bots")
                NavigationLink(value: AppRoute.passAndPlay) {
                    Label {
                        titled(localization("play.passAndPlay.title"), localization("play.passAndPlay.detail"))
                    } icon: {
                        Image(systemName: "person.2")
                    }
                }
                .accessibilityIdentifier("play.passAndPlay")
            }
            .iconColumnLabels(model.catalog.interface)
        } wide: {
            // As on Chess.com: a large board beside the ways to play.
            GeometryReader { proxy in
                let style = model.catalog.interface
                let columnWidth = style.home.setupPaneWidth * style.platformScale
                let side = max(0, min(proxy.size.height - 2 * style.gap, proxy.size.width - columnWidth - style.sectionGap - 2 * style.gap))
                HStack(spacing: style.sectionGap) {
                    BoardThumbnail(
                        position: model.unfinishedGame?.game.position ?? .initial,
                        flipped: model.unfinishedGame?.humanColor == .black, side: side)
                    VStack(spacing: style.gap) { wideEntries }
                        .frame(width: columnWidth)
                        #if os(tvOS)
                        .focusSection()
                        #endif
                }
                .padding(style.gap)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .screenTitle(localization("section.play.title"))
    }

    @ViewBuilder private var wideEntries: some View {
        if let game = model.unfinishedGame {
            NavigationLink(value: AppRoute.game(.saved(game))) {
                CardLabel(
                    title: localization("play.continue.title"),
                    subtitle: GamesLayout.title(game, localization: localization), isCompact: true
                ) {
                    SymbolBadge(systemImage: "play.fill")
                }
            }
            .cardButtonStyle()
        }
        NavigationLink(value: AppRoute.bots) {
            CardLabel(
                title: localization("play.bots.title"), subtitle: nextBot.map { localization($0.nameKey) },
                detail: nextBot.map { localization.string("playBots.elo", $0.elo) }, isCompact: true
            ) {
                if let bot = nextBot {
                    AvatarView(symbol: bot.avatar.symbol, name: localization(bot.nameKey), scale: 2)
                } else {
                    SymbolBadge(systemImage: "cpu")
                }
            }
        }
        .cardButtonStyle()
        .accessibilityIdentifier("play.bots")
        NavigationLink(value: AppRoute.passAndPlay) {
            CardLabel(
                title: localization("play.passAndPlay.title"),
                subtitle: localization("play.passAndPlay.detail"), isCompact: true
            ) {
                SymbolBadge(systemImage: "person.2")
            }
        }
        .cardButtonStyle()
        .accessibilityIdentifier("play.passAndPlay")
    }

    /// The bot Play Bots starts with: the last one picked, or the catalog default.
    private var nextBot: Bot? {
        model.catalog.bots.bot(id: model.settings.value.playBotsBotID ?? model.catalog.defaults.botID)
    }

    private var botSummary: String {
        guard let bot = nextBot else { return "" }
        return localization.string("play.bots.detail", localization.string(bot.nameKey), bot.elo)
    }

    private func titled(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading) {
            Text(title)
            if !subtitle.isEmpty {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
