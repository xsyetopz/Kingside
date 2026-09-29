import SwiftUI
import ChessCore

/// Pass-and-play setup: time control tiles grouped by category, player names, the
/// flip-board toggle and Start Game. The last time control is remembered.
struct PlayFriendView: View {
    @Binding var path: [AppRoute]
    /// `TimeControl.pgnValue` of the last choice ("600", "180+2", "-" for no timer).
    @AppStorage("ChessTV.playFriend.timeControl") private var timeControlKey = "600"
    @State private var whiteName = "White"
    @State private var blackName = "Black"
    @State private var autoFlip = false
    @FocusState private var focusStart: Bool

    private static let options = TimeControl.presets + [.untimed]
    private static let categories: [TimeControl.Category] = [.bullet, .blitz, .rapid, .untimed]

    private var timeControl: TimeControl {
        Self.options.first { $0.pgnValue == timeControlKey } ?? TimeControl(initialSeconds: 600, incrementSeconds: 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 48) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Play a Friend").font(ChessFont.display)
                Text("Pass and play on this TV")
                    .font(ChessFont.subheading)
                    .foregroundStyle(ChessTheme.textSecondary)
            }
            HStack(alignment: .top, spacing: 64) {
                timeControls
                    .focusSection()
                players
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .focusSection()
            }
            Spacer(minLength: 0)
        }
        .padding(80)
        .chessScreen()
        .defaultFocus($focusStart, true)
    }

    // MARK: - Time control

    private var timeControls: some View {
        VStack(alignment: .leading, spacing: 28) {
            ForEach(Self.categories, id: \.self) { category in
                HStack(spacing: 28) {
                    Label(category.title, systemImage: symbol(for: category))
                        .labelStyle(.alignedIcon(width: 56))
                        .font(ChessFont.heading)
                        .foregroundStyle(ChessTheme.textSecondary)
                        .frame(width: 240, alignment: .leading)
                    ForEach(Self.options.filter { $0.category == category }, id: \.self) { option in
                        Button { timeControlKey = option.pgnValue } label: {
                            Text(category == .untimed ? "No timer" : option.label)
                                .font(ChessFont.heading)
                                .monospacedDigit()
                                .frame(width: 190, height: 64)
                        }
                        .buttonStyle(.selectableTile(isSelected: option == timeControl))
                    }
                }
            }
        }
    }

    private func symbol(for category: TimeControl.Category) -> String {
        switch category {
        case .bullet: "bolt.fill"
        case .blitz: "flame.fill"
        case .rapid: "timer"
        case .untimed: "infinity"
        }
    }

    // MARK: - Players and start

    private var players: some View {
        VStack(alignment: .leading, spacing: 28) {
            nameField("White player", text: $whiteName, symbol: "circle")
            nameField("Black player", text: $blackName, symbol: "circle.fill")
            Toggle("Flip board each turn", isOn: $autoFlip)
                .font(ChessFont.body)
            Button("Start Game", action: start)
                .buttonStyle(.chessPrimary(icon: "play.fill", fullWidth: true))
                .focused($focusStart)
                .padding(.top, 12)
        }
        .chessPanel()
    }

    private func nameField(_ title: String, text: Binding<String>, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: symbol)
                .font(ChessFont.caption)
                .foregroundStyle(ChessTheme.textMuted)
            TextField(title, text: text)
                .font(ChessFont.body)
        }
    }

    private func start() {
        let setup = GameSetup(
            mode: .passAndPlay,
            white: PlayerInfo(name: displayName(whiteName, fallback: "White")),
            black: PlayerInfo(name: displayName(blackName, fallback: "Black")),
            timeControl: timeControl,
            autoFlip: autoFlip
        )
        path.append(.game(.new(setup)))
    }

    private func displayName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
