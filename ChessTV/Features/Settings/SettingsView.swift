import SwiftUI
import ChessCore

/// Settings screen: grouped panels of choices on the left, a live board preview on the right.
struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    Text("Settings")
                        .font(ChessFont.title)
                        .foregroundStyle(ChessTheme.textPrimary)

                    SettingsGroup(title: "Board") {
                        HStack(spacing: 24) {
                            ForEach(BoardTheme.allCases) { theme in
                                BoardThemeSwatch(theme: theme, isSelected: settings.value.boardTheme == theme) {
                                    settings.value.boardTheme = theme
                                }
                            }
                        }
                        OptionRow(title: "Orientation", icon: "arrow.up.arrow.down") {
                            ForEach(BoardOrientation.allCases) { orientation in
                                ChoiceChip(title: orientation.title, isSelected: settings.value.orientation == orientation) {
                                    settings.value.orientation = orientation
                                }
                            }
                        }
                    }

                    SettingsGroup(title: "Pieces") {
                        ForEach(PieceSet.allCases) { set in
                            PieceSetPreview(pieceSet: set, isSelected: settings.value.pieceSet == set)
                        }
                    }

                    SettingsGroup(title: "Gameplay") {
                        ToggleRow(title: "Show Legal Moves", subtitle: "Dots on the squares a piece can reach", icon: "circle.grid.3x3.fill", isOn: binding(\.showLegalMoves))
                        ToggleRow(title: "Show Coordinates", subtitle: "Files and ranks on the board edge", icon: "a.square", isOn: binding(\.showCoordinates))
                        ToggleRow(title: "Highlight Last Move", subtitle: "Tint the squares of the last move", icon: "square.fill.on.square.fill", isOn: binding(\.highlightLastMove))
                        ToggleRow(title: "Move Animation", subtitle: "Slide pieces between squares", icon: "wand.and.stars", isOn: binding(\.moveAnimation))
                        ToggleRow(title: "Auto-Promote to Queen", subtitle: "Skip the promotion picker", icon: "crown.fill", isOn: binding(\.autoPromoteToQueen))
                        ToggleRow(title: "Sounds", subtitle: "Moves, captures and game end", icon: "speaker.wave.2.fill", isOn: $settings.soundEnabled)
                    }
                }
                .padding(.vertical, 40)
                .padding(.horizontal, 30)
            }
            .frame(width: 1060)

            SettingsBoardPreview(settings: settings.value)
                .padding(.top, 150)
        }
        .padding(.horizontal, 50)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .chessScreen()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AppSettings, Value>) -> Binding<Value> {
        Binding(get: { settings.value[keyPath: keyPath] }, set: { settings.value[keyPath: keyPath] = $0 })
    }
}

/// A titled, non-focusable panel that groups related settings.
private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(title.uppercased())
                .font(ChessFont.caption)
                .tracking(2)
                .foregroundStyle(ChessTheme.textMuted)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .chessPanel()
        .focusSection()
    }
}

private struct BoardThemeSwatch: View {
    let theme: BoardTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Grid(horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(0..<4, id: \.self) { row in
                        GridRow {
                            ForEach(0..<4, id: \.self) { column in
                                Rectangle()
                                    .fill(theme.squareColor(isLight: (row + column).isMultiple(of: 2)))
                                    .frame(width: 34, height: 34)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(ChessTheme.primary, lineWidth: isSelected ? 5 : 0)
                }
                HStack(spacing: 8) {
                    if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(ChessTheme.primary) }
                    Text(theme.title).lineLimit(1)
                }
                .font(ChessFont.caption)
            }
            .frame(width: 176)
        }
        .buttonStyle(PanelCardStyle(padding: 18))
        .accessibilityLabel("\(theme.title) board")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A row with a title on the left and a group of focusable choices on the right.
private struct OptionRow<Choices: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let choices: Choices

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(ChessTheme.textSecondary)
                .frame(width: 44)
            Text(title)
                .font(ChessFont.body)
                .foregroundStyle(ChessTheme.textPrimary)
            Spacer(minLength: 20)
            HStack(spacing: 16) { choices }
        }
        .padding(.top, 8)
    }
}

private struct ChoiceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(ChessFont.caption)
                .foregroundStyle(isSelected ? ChessTheme.textPrimary : ChessTheme.textSecondary)
                .frame(minWidth: 120)
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(ChessTheme.primary)
                        .frame(height: 4)
                        .offset(y: 10)
                        .opacity(isSelected ? 1 : 0)
                }
        }
        .buttonStyle(PanelCardStyle(padding: 18))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PieceSetPreview: View {
    let pieceSet: PieceSet
    let isSelected: Bool

    private static let pieces: [PieceType] = [.king, .queen, .rook, .bishop, .knight, .pawn]

    var body: some View {
        HStack(spacing: 24) {
            HStack(spacing: 4) {
                ForEach(Self.pieces, id: \.self) { type in
                    pieceSet.image(for: Piece(type: type, color: .white))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
                ForEach(Self.pieces.prefix(2), id: \.self) { type in
                    pieceSet.image(for: Piece(type: type, color: .black))
                        .resizable()
                        .scaledToFit()
                        .frame(width: 64, height: 64)
                }
            }
            .padding(12)
            .background(ChessTheme.raised, in: RoundedRectangle(cornerRadius: ChessTheme.cornerRadius, style: .continuous))
            Text(pieceSet.title)
                .font(ChessFont.body)
                .foregroundStyle(ChessTheme.textPrimary)
            Spacer()
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(ChessTheme.primary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pieceSet.title) pieces")
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 22) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(ChessTheme.textSecondary)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(ChessFont.body)
                    Text(subtitle)
                        .font(ChessFont.caption)
                        .foregroundStyle(ChessTheme.textMuted)
                }
                Spacer(minLength: 20)
                SwitchIndicator(isOn: isOn)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(PanelCardStyle(padding: 20))
        .accessibilityLabel(title)
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct SwitchIndicator: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? ChessTheme.primary : ChessTheme.secondaryEdge)
            .frame(width: 88, height: 48)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .padding(6)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
            }
            .animation(.easeOut(duration: 0.15), value: isOn)
    }
}

/// A small board that redraws as settings change: 1.e4 e5 with the g1 knight picked up.
private struct SettingsBoardPreview: View {
    let settings: AppSettings

    private static let lastMove = ChessMove(from: Square(file: 4, rank: 6), to: Square(file: 4, rank: 4))
    private static let position: ChessPosition = {
        let e4 = ChessMove(from: Square(file: 4, rank: 1), to: Square(file: 4, rank: 3))
        return (try? ChessPosition.initial.applying(e4).applying(lastMove)) ?? .initial
    }()
    private static let knight = Square(file: 6, rank: 0)
    private static let knightMoves = Set(position.legalMoves(from: knight).map(\.to))

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ChessBoardDisplay(
                position: Self.position,
                lastMove: settings.highlightLastMove ? Self.lastMove : nil,
                isFlipped: settings.orientation == .black,
                theme: settings.boardTheme,
                pieceSet: settings.pieceSet,
                showCoordinates: settings.showCoordinates,
                animateMoves: false,
                selectedSquare: Self.knight,
                legalDestinations: settings.showLegalMoves ? Self.knightMoves : []
            )
            .frame(width: 620, height: 620)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            Text("Preview")
                .font(ChessFont.caption)
                .foregroundStyle(ChessTheme.textMuted)
        }
        .accessibilityHidden(true)
    }
}
