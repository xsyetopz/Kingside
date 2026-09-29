import SwiftUI

// Focusable choice tile for setup screens (time controls, bot avatars, color chips).
// `.buttonStyle(.selectableTile(isSelected: true))`: raised surface; the selected tile has a
// green border, the focused tile a white one and scales up. The label supplies content.

struct SelectableTileStyle: ButtonStyle {
    var isSelected: Bool
    var padding: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        SelectableTile(configuration: configuration, isSelected: isSelected, padding: padding)
    }
}

extension ButtonStyle where Self == SelectableTileStyle {
    static func selectableTile(isSelected: Bool, padding: CGFloat = 20) -> SelectableTileStyle {
        SelectableTileStyle(isSelected: isSelected, padding: padding)
    }
}

private struct SelectableTile: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let padding: CGFloat
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChessTheme.cornerRadius, style: .continuous)
        configuration.label
            .foregroundStyle(ChessTheme.textPrimary)
            .padding(padding)
            .background(isFocused ? ChessTheme.focusSurface : ChessTheme.raised, in: shape)
            .overlay {
                shape.strokeBorder(
                    isFocused ? .white : ChessTheme.primary,
                    lineWidth: isFocused || isSelected ? 5 : 0
                )
            }
            .scaleEffect(configuration.isPressed ? 0.98 : isFocused ? 1.06 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 18, y: 10)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isFocused)
            .animation(.easeOut(duration: 0.15), value: isSelected)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
