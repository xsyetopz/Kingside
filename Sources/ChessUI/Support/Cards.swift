import ChessContent
import SwiftUI

// Building blocks of the section homes and setup screens. Narrow screens (iPhone, and iPad in
// compact width) keep grouped lists; tvOS, iPad, and the Mac lay the same choices out as cards
// in a grid, so a wide screen shows them without scrolling and with their content, not just a
// label.

/// Shows `narrow` in compact width and `wide` everywhere else.
struct WidthAdaptive<Narrow: View, Wide: View>: View {
  @ViewBuilder
  let narrow: Narrow
  @ViewBuilder
  let wide: Wide

  #if os(iOS)
    @Environment(\.horizontalSizeClass)
    private var sizeClass

    var body: some View {
      if sizeClass == .compact { narrow } else { wide }
    }
  #else
    var body: some View { wide }
  #endif
}

/// A scrolling grid of cards, as many columns as fit `tileMinWidth`, centered and at most
/// `contentMaxWidth` wide, under an optional full-width `header` such as a picker. Put
/// `CardSection`s or cards inside.
struct CardGrid<Header: View, Content: View>: View {
  @ViewBuilder
  let header: Header
  @ViewBuilder
  let content: Content
  @Environment(AppModel.self)
  private var model

  init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
    self.header = header()
    self.content = content()
  }

  var body: some View {
    let style = model.catalog.interface
    let scale = style.platformScale
    ScrollView {
      VStack(alignment: .leading, spacing: style.gap) {
        header
        LazyVGrid(
          columns: [
            GridItem(
              .adaptive(minimum: style.home.tileMinWidth * scale),
              spacing: style.gap,
              alignment: .top
            )
          ],
          alignment: .leading,
          spacing: style.gap
        ) {
          content
        }
      }
      .frame(maxWidth: style.home.contentMaxWidth * scale)
      .padding(style.gap)
      .frame(maxWidth: .infinity)
    }
    // The tvOS focus lift grows a card past the grid's edge.
    .scrollClipDisabled()
  }
}

extension CardGrid where Header == EmptyView {
  init(@ViewBuilder content: () -> Content) {
    self.init(header: { EmptyView() }, content: content)
  }
}

/// A titled group of cards inside a `CardGrid`.
struct CardSection<Content: View>: View {
  let title: String
  @ViewBuilder
  let content: Content
  @Environment(AppModel.self)
  private var model

  var body: some View {
    Section {
      content
    } header: {
      Text(title)
        .font(.title3.weight(.semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, model.catalog.interface.gap)
        .accessibilityAddTraits(.isHeader)
    }
  }
}

/// A card's content: artwork, a title with an optional subtitle, an optional detail such as a
/// rating, and a checkmark when it is the selected choice. Use it as the label of a
/// `NavigationLink` or `Button` styled with `cardButtonStyle()`. A compact card is only as
/// tall as its content, for short choices such as time controls.
struct CardLabel<Artwork: View>: View {
  let title: String
  var subtitle: String?
  /// Two lines by default, so a long bio stays short; `nil` shows all of it.
  var subtitleLineLimit: Int? = 2
  var detail: String?
  var isSelected = false
  var isCompact = false
  let style: InterfaceStyle
  @ViewBuilder
  let artwork: Artwork

  var body: some View {
    HStack(spacing: style.gap) {
      artwork
      VStack(alignment: .leading, spacing: style.gap / 4) {
        Text(title).font(.headline)
        if let subtitle {
          Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            .lineLimit(subtitleLineLimit)
        }
        if let detail {
          Text(detail).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(.tint)
        }
      }
      .multilineTextAlignment(.leading)
      Spacer(minLength: 0)
      if isSelected {
        Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(.tint)
      }
    }
    .padding(style.gap)
    .frame(
      maxWidth: .infinity,
      minHeight: isCompact ? nil : style.home.tileMinHeight * style.platformScale,
      alignment: .leading
    )
    .contentShape(RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous))
  }
}

/// An SF Symbol on a tinted rounded square: the artwork of a card without a board.
struct SymbolBadge: View {
  let systemImage: String
  let style: InterfaceStyle

  var body: some View {
    let side = style.home.iconColumnWidth * 2 * style.platformScale
    Image(systemName: systemImage)
      .font(.title2)
      .foregroundStyle(.tint)
      .frame(width: side, height: side)
      .background(
        .tint.opacity(0.15),
        in: RoundedRectangle(cornerRadius: side / 4, style: .continuous)
      )
      .accessibilityHidden(true)
  }
}

#if os(tvOS)
  extension View {
    /// The system card style: focus lift and parallax. `isSelected` has no look of its own on
    /// tvOS; the card's checkmark shows the choice.
    func cardButtonStyle(isSelected: Bool = false) -> some View {
      buttonStyle(.card)
    }
  }
#else
  extension View {
    /// A filled rounded card with a pressed state, and a tinted outline when `isSelected`.
    func cardButtonStyle(isSelected: Bool = false) -> some View {
      buttonStyle(FilledCardButtonStyle(isSelected: isSelected))
    }
  }

  private struct FilledCardButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(AppModel.self)
    private var model

    func makeBody(configuration: Configuration) -> some View {
      let shape = RoundedRectangle(
        cornerRadius: model.catalog.interface.cornerRadius,
        style: .continuous
      )
      configuration.label
        .background(.fill.tertiary, in: shape)
        .overlay { if isSelected { shape.strokeBorder(.tint, lineWidth: 2) } }
        .opacity(configuration.isPressed ? 0.7 : 1)
        .animation(.snappy, value: configuration.isPressed)
    }
  }
#endif
