import SwiftUI

/// A list row that picks one option: `leading` view, title with an optional subtitle, an
/// optional detail, and a checkmark when selected.
struct SetupRow<Leading: View>: View {
    let title: String
    var subtitle: String?
    var detail: String?
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let leading: Leading
    @Environment(AppModel.self) private var model

    init(
        title: String, subtitle: String? = nil, detail: String? = nil, isSelected: Bool,
        action: @escaping () -> Void, @ViewBuilder leading: () -> Leading
    ) {
        self.title = title
        self.subtitle = subtitle
        self.detail = detail
        self.isSelected = isSelected
        self.action = action
        self.leading = leading()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: model.catalog.interface.gap) {
                leading
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    if let subtitle { Text(subtitle).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 0)
                if let detail { Text(detail).foregroundStyle(.secondary) }
                if isSelected { Image(systemName: "checkmark").foregroundStyle(.tint) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

extension View {
    /// A prominent Start button under the content, above the tab bar and home indicator.
    func startBar(title: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        modifier(StartBarModifier(title: title, isEnabled: isEnabled, action: action))
    }
}

private struct StartBarModifier: ViewModifier {
    let title: String
    let isEnabled: Bool
    let action: () -> Void
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom) {
            StartButton(title: title, isEnabled: isEnabled, action: action)
                .padding(model.catalog.interface.gap)
        }
    }
}

/// The prominent button that starts a game from a setup screen.
struct StartButton: View {
    let title: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!isEnabled)
        .accessibilityIdentifier("setup.start")
    }
}

/// A wide setup screen, laid out as on chess.com: the current choice large in a side pane that
/// ends with Start, beside a scrolling grid of the options. Start never covers an option, and
/// the options fit many to a row.
struct SetupSplit<Pane: View, Options: View>: View {
    @ViewBuilder let pane: Pane
    @ViewBuilder let options: Options
    @Environment(AppModel.self) private var model

    var body: some View {
        let style = model.catalog.interface
        let scale = style.platformScale
        HStack(alignment: .top, spacing: style.sectionGap) {
            ScrollView {
                VStack(alignment: .leading, spacing: style.gap) { pane }
                    .padding(style.gap)
            }
            .frame(width: style.home.setupPaneWidth * scale)
            .scrollClipDisabled()
            .tvFocusSection()
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: style.home.choiceTileMinWidth * scale), spacing: style.gap, alignment: .top)],
                    alignment: .leading, spacing: style.gap
                ) {
                    options
                }
                .padding(style.gap)
            }
            // The tvOS focus lift grows a tile past the grid's edge.
            .scrollClipDisabled()
            .tvFocusSection()
        }
        .frame(maxWidth: style.home.contentMaxWidth * scale)
        .frame(maxWidth: .infinity)
    }
}

private extension View {
    /// On tvOS, left and right move between the panes from any height: without a focus
    /// section, focus only moves to an item level with the focused one.
    @ViewBuilder func tvFocusSection() -> some View {
        #if os(tvOS)
        focusSection()
        #else
        self
        #endif
    }
}

/// An option tile in a `SetupSplit` grid: artwork over a title and an optional detail.
struct ChoiceTile<Artwork: View>: View {
    let title: String
    var detail: String?
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let artwork: Artwork
    @Environment(AppModel.self) private var model

    init(
        title: String, detail: String? = nil, isSelected: Bool, action: @escaping () -> Void,
        @ViewBuilder artwork: () -> Artwork
    ) {
        self.title = title
        self.detail = detail
        self.isSelected = isSelected
        self.action = action
        self.artwork = artwork()
    }

    var body: some View {
        let style = model.catalog.interface
        Button(action: action) {
            VStack(spacing: style.gap / 2) {
                artwork
                Text(title).font(.headline).lineLimit(1)
                if let detail {
                    Text(detail).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            .padding(style.gap)
            .frame(maxWidth: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
        }
        .cardButtonStyle(isSelected: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
