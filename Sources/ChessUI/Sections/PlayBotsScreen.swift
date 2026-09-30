import ChessContent
import ChessPlay
import SwiftUI

/// Pick a bot and a color, then start. The choice is remembered in the settings.
struct PlayBotsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization
    @State private var launch: GameLaunch?

    var body: some View {
        let catalog = model.catalog
        WidthAdaptive {
            List {
                Section(localization("playBots.color.title")) { colorPicker }
                ForEach(catalog.bots.groups) { group in
                    Section(localization(group.nameKey)) {
                        ForEach(catalog.bots.bots(in: group)) { bot in
                            SetupRow(
                                title: localization(bot.nameKey), subtitle: localization(bot.bioKey),
                                detail: localization.string("playBots.elo", bot.elo), isSelected: bot.id == selectedBotID
                            ) {
                                model.settings.value.playBotsBotID = bot.id
                            } leading: {
                                AvatarView(symbol: bot.avatar.symbol, name: localization(bot.nameKey))
                            }
                        }
                    }
                }
            }
            .startBar(title: localization("playBots.start"), isEnabled: selectedBot != nil, action: start)
        } wide: {
            SetupSplit {
                ScreenHeading(title: localization("play.bots.title"))
                if let bot = selectedBot { BotProfile(bot: bot) }
                Text(localization("playBots.color.title")).font(.headline)
                colorPicker
                StartButton(title: localization("playBots.start"), isEnabled: selectedBot != nil, action: start)
            } options: {
                ForEach(catalog.bots.groups) { group in
                    CardSection(title: localization(group.nameKey)) {
                        ForEach(catalog.bots.bots(in: group)) { bot in
                            ChoiceTile(
                                title: localization(bot.nameKey), detail: localization.string("playBots.elo", bot.elo),
                                isSelected: bot.id == selectedBotID
                            ) {
                                model.settings.value.playBotsBotID = bot.id
                            } artwork: {
                                AvatarView(symbol: bot.avatar.symbol, name: localization(bot.nameKey), scale: 1.5)
                            }
                        }
                    }
                }
            }
        }
        .screenTitle(localization("play.bots.title"), chrome: .pushed)
        .navigationDestination(item: $launch) { launch in
            GameScreen(launch: launch)
        }
    }

    private var colorPicker: some View {
        Picker(localization("playBots.color.title"), selection: color) {
            ForEach(BotColorChoice.allCases) { choice in
                Text(localization(choice.titleKey)).tag(choice)
            }
        }
        .pickerStyle(.segmented)
    }

    private var selectedBotID: String { model.settings.value.playBotsBotID ?? model.catalog.defaults.botID }

    private var selectedBot: Bot? { model.catalog.bots.bot(id: selectedBotID) }

    private var color: Binding<BotColorChoice> {
        Binding(get: { model.settings.value.playBotsColor }, set: { model.settings.value.playBotsColor = $0 })
    }

    private func start() {
        guard let bot = selectedBot else { return }
        launch = .new(PlaySetup.versus(bot, choice: model.settings.value.playBotsColor, localization: localization))
    }
}

/// The selected bot, large: avatar, name, rating, group, bio, and what it says when a game starts.
private struct BotProfile: View {
    let bot: Bot
    @Environment(AppModel.self) private var model
    @Environment(\.localization) private var localization

    var body: some View {
        let style = model.catalog.interface
        VStack(alignment: .leading, spacing: style.gap / 2) {
            AvatarView(symbol: bot.avatar.symbol, name: localization(bot.nameKey), scale: style.home.heroAvatarScale)
            Text(localization(bot.nameKey)).font(.title.bold())
            HStack(alignment: .firstTextBaseline) {
                Text(localization.string("playBots.elo", bot.elo))
                    .font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.tint)
                if let group = model.catalog.bots.groups.first(where: { $0.id == bot.groupID }) {
                    Text(localization(group.nameKey)).foregroundStyle(.secondary)
                }
            }
            Text(localization(bot.bioKey)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let greeting = bot.chat[.greeting]?.first {
                Text(localization(greeting))
                    .italic()
                    .padding(style.gap / 2)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
