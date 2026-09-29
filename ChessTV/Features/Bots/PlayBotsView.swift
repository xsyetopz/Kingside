import SwiftUI
import ChessCore

/// Bot picker: the selected bot on the left, the roster grouped by `BotGroup` on the right,
/// then the color choice and Play. Focusing a bot tile selects it. The last bot and color
/// are remembered; a Random color is resolved when the game starts.
struct PlayBotsView: View {
    @Binding var path: [AppRoute]
    @AppStorage("ChessTV.playBots.botID") private var botID = BotRoster.defaultBot.id
    @AppStorage("ChessTV.playBots.color") private var colorChoice = ColorChoice.white
    @State private var greeting = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case bot(String)
        case color(ColorChoice)
        case play
    }

    enum ColorChoice: String, CaseIterable, Identifiable {
        case white, random, black
        var id: String { rawValue }
        var title: String { rawValue.capitalized }

        func resolved() -> PieceColor {
            switch self {
            case .white: .white
            case .black: .black
            case .random: Bool.random() ? .white : .black
            }
        }
    }

    private var bot: Bot { BotRoster.bot(id: botID) ?? BotRoster.defaultBot }

    var body: some View {
        HStack(alignment: .top, spacing: 64) {
            presentation
                .frame(width: 960, alignment: .topLeading)
            picker
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(.horizontal, 80)
        .padding(.vertical, 60)
        .chessScreen()
        .defaultFocus($focus, .play)
        .onAppear { greeting = bot.line(for: .greeting) }
        .onChange(of: botID) { greeting = bot.line(for: .greeting) }
        .onChange(of: focus) { _, newValue in
            if case .bot(let id)? = newValue { botID = id }
        }
    }

    // MARK: - Selected bot

    private var presentation: some View {
        VStack(alignment: .leading, spacing: 36) {
            Text("Play Bots").font(ChessFont.display)
            HStack(alignment: .center, spacing: 36) {
                bot.avatar(size: 280)
                SpeechBubble(text: greeting, font: ChessFont.subheading)
                    .frame(maxWidth: 560, alignment: .leading)
            }
            VStack(alignment: .leading, spacing: 12) {
                Text(bot.name).font(ChessFont.title)
                HStack(spacing: 20) {
                    Text(verbatim: "\(bot.rating)")
                        .font(ChessFont.heading)
                        .monospacedDigit()
                        .foregroundStyle(ChessTheme.textSecondary)
                    Text(bot.group.title)
                        .font(ChessFont.caption)
                        .foregroundStyle(ChessTheme.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(bot.color, in: Capsule())
                }
            }
            Text(bot.bio)
                .font(ChessFont.bodyRegular)
                .foregroundStyle(ChessTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.2), value: botID)
    }

    // MARK: - Roster and controls

    private var picker: some View {
        VStack(alignment: .leading, spacing: 32) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(BotGroup.allCases) { group in
                        let bots = BotRoster.bots(in: group)
                        if !bots.isEmpty {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(group.title)
                                    .font(ChessFont.subheading)
                                    .foregroundStyle(ChessTheme.textSecondary)
                                HStack(spacing: 28) {
                                    ForEach(bots) { tile(for: $0) }
                                }
                            }
                        }
                    }
                }
                .padding(20)
            }
            .clipped()
            .focusSection()

            VStack(alignment: .leading, spacing: 16) {
                Text("I play as").font(ChessFont.body).foregroundStyle(ChessTheme.textSecondary)
                HStack(spacing: 20) {
                    ForEach(ColorChoice.allCases) { choice in
                        Button { colorChoice = choice } label: {
                            Label(choice.title, systemImage: symbol(for: choice))
                                .font(ChessFont.body)
                                .frame(width: 160)
                        }
                        .buttonStyle(.selectableTile(isSelected: colorChoice == choice, padding: 18))
                        .focused($focus, equals: .color(choice))
                    }
                }
            }
            .focusSection()

            Button("Play", action: play)
                .buttonStyle(.chessPrimary(icon: "play.fill", fullWidth: true))
                .focused($focus, equals: .play)
        }
        .chessPanel()
    }

    private func tile(for bot: Bot) -> some View {
        Button {
            botID = bot.id
            focus = .play
        } label: {
            VStack(spacing: 10) {
                bot.avatar(size: 110)
                Text(bot.name)
                    .font(ChessFont.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(verbatim: "\(bot.rating)")
                    .font(ChessFont.caption)
                    .monospacedDigit()
                    .foregroundStyle(ChessTheme.textMuted)
            }
            .frame(width: 150)
        }
        .buttonStyle(.selectableTile(isSelected: botID == bot.id, padding: 14))
        .focused($focus, equals: .bot(bot.id))
        .accessibilityLabel("\(bot.name), rating \(bot.rating)")
    }

    private func symbol(for choice: ColorChoice) -> String {
        switch choice {
        case .white: "circle"
        case .random: "circle.lefthalf.filled"
        case .black: "circle.fill"
        }
    }

    private func play() {
        let setup = GameSetup.versus(bot, humanColor: colorChoice.resolved())
        path.append(.game(.new(setup)))
    }
}
