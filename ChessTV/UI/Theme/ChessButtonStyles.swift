import SwiftUI

// Focus-aware button styles for the Siri Remote focus engine.
// - `.buttonStyle(.chessPrimary)` / `.chessPrimary(icon: "play.fill")`: big raised green button.
// - `.buttonStyle(.chessSecondary)` / `.chessSecondary(icon:)`: raised grey button.
// - `.buttonStyle(.panelCard)`: focusable card on a raised surface; the label supplies content.
// Focused: scales up, brightens, shows a white outline. Pressed: the face drops onto its edge.
// `fullWidth: true` stretches the button to the available width.

struct PrimaryButtonStyle: ButtonStyle {
    var icon: String?
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        RaisedButton(
            configuration: configuration,
            icon: icon,
            fullWidth: fullWidth,
            face: ChessTheme.primary,
            focusedFace: ChessTheme.primaryFocused,
            edge: ChessTheme.primaryEdge
        )
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    var icon: String?
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        RaisedButton(
            configuration: configuration,
            icon: icon,
            fullWidth: fullWidth,
            face: ChessTheme.secondary,
            focusedFace: ChessTheme.secondaryFocused,
            edge: ChessTheme.secondaryEdge
        )
    }
}

struct PanelCardStyle: ButtonStyle {
    var padding: CGFloat = 28

    func makeBody(configuration: Configuration) -> some View {
        PanelCard(configuration: configuration, padding: padding)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var chessPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func chessPrimary(icon: String? = nil, fullWidth: Bool = false) -> PrimaryButtonStyle {
        PrimaryButtonStyle(icon: icon, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var chessSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func chessSecondary(icon: String? = nil, fullWidth: Bool = false) -> SecondaryButtonStyle {
        SecondaryButtonStyle(icon: icon, fullWidth: fullWidth)
    }
}

extension ButtonStyle where Self == PanelCardStyle {
    static var panelCard: PanelCardStyle { PanelCardStyle() }
}

/// Depth of the darker bottom edge that gives buttons their raised look.
private let raisedEdgeDepth: CGFloat = 7

private struct RaisedButton: View {
    let configuration: ButtonStyleConfiguration
    let icon: String?
    let fullWidth: Bool
    let face: Color
    let focusedFace: Color
    let edge: Color
    @Environment(\.isFocused) private var isFocused
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChessTheme.cornerRadius, style: .continuous)
        let drop = configuration.isPressed ? raisedEdgeDepth - 2 : 0
        HStack(spacing: 16) {
            if let icon { Image(systemName: icon).font(.system(size: 34, weight: .bold)) }
            configuration.label
        }
        .font(ChessFont.button)
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.25), radius: 0, y: 2)
        .padding(.horizontal, 44)
        .padding(.vertical, 22)
        .frame(maxWidth: fullWidth ? .infinity : nil)
        .background(isFocused ? focusedFace : face, in: shape)
        .overlay { shape.strokeBorder(.white, lineWidth: isFocused ? 4 : 0) }
        .offset(y: drop)
        .padding(.bottom, raisedEdgeDepth)
        .background(alignment: .bottom) {
            shape.fill(edge).padding(.top, raisedEdgeDepth)
        }
        .opacity(isEnabled ? 1 : 0.45)
        .scaleEffect(isFocused ? 1.06 : 1)
        .shadow(color: .black.opacity(isFocused ? 0.45 : 0.2), radius: isFocused ? 18 : 4, y: isFocused ? 10 : 2)
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isFocused)
        .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

private struct PanelCard: View {
    let configuration: ButtonStyleConfiguration
    let padding: CGFloat
    @Environment(\.isFocused) private var isFocused

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: ChessTheme.cornerRadius, style: .continuous)
        configuration.label
            .foregroundStyle(ChessTheme.textPrimary)
            .padding(padding)
            .background(isFocused ? ChessTheme.focusSurface : ChessTheme.raised, in: shape)
            .overlay { shape.strokeBorder(.white, lineWidth: isFocused ? 4 : 0) }
            .scaleEffect(configuration.isPressed ? 0.98 : isFocused ? 1.05 : 1)
            .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 20, y: 12)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isFocused)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
