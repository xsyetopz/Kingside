import ChessBoardScene
import ChessContent
import ChessCore
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

// MARK: - Lists

/// Symbols in a fixed-width column, tinted, with room before the title, so titles line up
/// whatever each symbol's width.
struct IconColumnLabelStyle: LabelStyle {
  let width: Double
  let spacing: Double

  func makeBody(configuration: Configuration) -> some View {
    HStack(spacing: spacing) {
      configuration.icon
        .foregroundStyle(.tint)
        .frame(width: width)
      configuration.title
    }
  }
}

extension View {
  /// Lays out the `Label`s inside with `IconColumnLabelStyle`. Apply it to lists, not to
  /// toolbars or tab bars, which have their own label styles.
  func iconColumnLabels(_ style: InterfaceStyle) -> some View {
    labelStyle(
      IconColumnLabelStyle(
        width: style.home.iconColumnWidth * style.platformScale,
        spacing: style.home.iconSpacing * style.platformScale
      )
    )
  }
}

extension View {
  /// Keeps a scrolling list's or form's rows at most `formMaxWidth` wide and centered. Outside
  /// tvOS its background and scrolling still span the whole width.
  func readableRows(_ style: InterfaceStyle) -> some View {
    modifier(ReadableRows(maxWidth: style.home.formMaxWidth * style.platformScale))
  }
}

private struct ReadableRows: ViewModifier {
  let maxWidth: Double
  #if !os(tvOS)
    @State
    private var inset = 0.0
  #endif

  func body(content: Content) -> some View {
    #if os(tvOS)
      // tvOS lists ignore `contentMargins`, and their background is clear, so a frame is enough.
      content
        .frame(maxWidth: maxWidth)
        .frame(maxWidth: .infinity)
    #else
      content
        .contentMargins(.horizontal, inset, for: .scrollContent)
        .onGeometryChange(for: Double.self) {
          $0.size.width
        } action: { width in
          inset = max(0, (width - maxWidth) / 2)
        }
    #endif
  }
}

// MARK: - Cards

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
  @ViewBuilder
  let artwork: Artwork
  @Environment(AppModel.self)
  private var model

  init(
    title: String,
    subtitle: String? = nil,
    subtitleLineLimit: Int? = 2,
    detail: String? = nil,
    isSelected: Bool = false,
    isCompact: Bool = false,
    @ViewBuilder artwork: () -> Artwork
  ) {
    self.title = title
    self.subtitle = subtitle
    self.subtitleLineLimit = subtitleLineLimit
    self.detail = detail
    self.isSelected = isSelected
    self.isCompact = isCompact
    self.artwork = artwork()
  }

  var body: some View {
    let style = model.catalog.interface
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
  @Environment(AppModel.self)
  private var model

  var body: some View {
    let style = model.catalog.interface
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

extension View {
  /// The system card style on tvOS (focus lift and parallax); a filled rounded card with a
  /// pressed state and a tinted outline when `isSelected` elsewhere.
  func cardButtonStyle(isSelected: Bool = false) -> some View {
    #if os(tvOS)
      buttonStyle(.card)
    #else
      buttonStyle(FilledCardButtonStyle(isSelected: isSelected))
    #endif
  }
}

#if !os(tvOS)
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

// MARK: - Board thumbnail

/// A still board, for cards and previews: in the chosen theme and piece set unless others are
/// given.
struct BoardThumbnail: View {
  let position: ChessPosition
  /// Black at the bottom.
  var flipped = false
  let side: Double
  var theme: BoardTheme?
  var pieceSet: PieceSet?

  @Environment(AppModel.self)
  private var model
  @Environment(\.displayScale)
  private var displayScale

  var body: some View {
    let theme = theme ?? model.boardTheme
    let pixels = Int((side / 8 * displayScale).rounded())
    let images = PieceThumbnails.images(for: pieceSet ?? model.pieceSet, pixelSize: pixels)
    let scale = displayScale
    Canvas { context, size in
      let cell = size.width / 8
      for rank in 0..<8 {
        for file in 0..<8 {
          let rect = CGRect(
            x: Double(flipped ? 7 - file : file) * cell,
            y: Double(flipped ? rank : 7 - rank) * cell,
            width: cell,
            height: cell
          )
          let isDark = (file + rank).isMultiple(of: 2)
          context.fill(
            Path(rect),
            with: .color(Color(isDark ? theme.squares.dark : theme.squares.light))
          )
          if let piece = position[Square(file: file, rank: rank)], let image = images[piece] {
            context.draw(Image(decorative: image, scale: scale), in: rect)
          }
        }
      }
    }
    .frame(width: side, height: side)
    .clipShape(RoundedRectangle(cornerRadius: side / 24, style: .continuous))
    .accessibilityHidden(true)
  }
}

/// Rasterized pieces by set and size, so thumbnails do not read the PDFs on every redraw.
@MainActor
private enum PieceThumbnails {
  private struct Key: Hashable {
    let setID: String
    let pixelSize: Int
  }

  private static var cache: [Key: [Piece: CGImage]] = [:]

  static func images(for set: PieceSet, pixelSize: Int) -> [Piece: CGImage] {
    let key = Key(setID: set.id, pixelSize: pixelSize)
    if let images = cache[key] { return images }
    var images: [Piece: CGImage] = [:]
    for color in [PieceColor.white, .black] {
      for type in PieceType.allCases {
        let piece = Piece(type: type, color: color)
        images[piece] = PieceImage.cgImage(for: piece, in: set, pixelSize: pixelSize)
      }
    }
    cache[key] = images
    return images
  }
}

/// Four large pieces of a set on a two-by-two board in the chosen theme: a set's look shows at
/// a size where a whole-board thumbnail makes its pieces too small to tell apart.
struct PieceSetSample: View {
  let pieceSet: PieceSet
  let side: Double

  @Environment(AppModel.self)
  private var model
  @Environment(\.displayScale)
  private var displayScale

  private static let pieces: [Piece] = [
    Piece(type: .king, color: .white), Piece(type: .knight, color: .black),
    Piece(type: .queen, color: .black), Piece(type: .knight, color: .white),
  ]

  var body: some View {
    let theme = model.boardTheme
    let images = PieceThumbnails.images(
      for: pieceSet,
      pixelSize: Int((side / 2 * displayScale).rounded())
    )
    let scale = displayScale
    Canvas { context, size in
      let cell = size.width / 2
      for (index, piece) in Self.pieces.enumerated() {
        let rect = CGRect(
          x: Double(index % 2) * cell,
          y: Double(index / 2) * cell,
          width: cell,
          height: cell
        )
        // Dark at the bottom left, as on a real board.
        let isDark = index == 1 || index == 2
        context.fill(
          Path(rect),
          with: .color(Color(isDark ? theme.squares.dark : theme.squares.light))
        )
        if let image = images[piece] {
          context.draw(Image(decorative: image, scale: scale), in: rect)
        }
      }
    }
    .frame(width: side, height: side)
    .clipShape(RoundedRectangle(cornerRadius: side / 12, style: .continuous))
    .accessibilityHidden(true)
  }
}

// MARK: - Titles

/// Where a screen sits, which decides the bars around it.
enum ScreenChrome {
  /// A section's home: the tab bar shows.
  case root
  /// A screen pushed onto a section. On tvOS the tab bar hides, as it would float over the
  /// content, and Menu goes back.
  case pushed
  /// A pushed screen built around the board: the tab bar hides everywhere, so the board gets
  /// the full height.
  case board
}

extension View {
  /// The screen's navigation title and bars. On tvOS the navigation bar hides: its title
  /// stays put while content scrolls over it, and the tab bar already names the section.
  /// Pushed screens there show a `ScreenHeading` in their content.
  func screenTitle(_ title: String, chrome: ScreenChrome = .root) -> some View {
    #if os(tvOS)
      navigationTitle(title)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(chrome == .root ? .automatic : .hidden, for: .tabBar)
        .modifier(HiddenTabBarInset(isHidden: chrome != .root))
    #elseif os(iOS)
      navigationTitle(title)
        .toolbar(chrome == .board ? .hidden : .automatic, for: .tabBar)
    #else
      navigationTitle(title)
    #endif
  }
}

#if os(tvOS)
  /// A hidden tvOS tab bar still reserves its height at the top of the safe area, which leaves
  /// a gap above pushed screens. This replaces that top inset with the overscan inset, which the
  /// TV safe area has equally at the top and bottom.
  private struct HiddenTabBarInset: ViewModifier {
    let isHidden: Bool
    @State
    private var overscan = 0.0

    func body(content: Content) -> some View {
      if isHidden {
        content
          .safeAreaPadding(.top, overscan)
          .ignoresSafeArea(.container, edges: .top)
          .onGeometryChange(for: Double.self) {
            $0.safeAreaInsets.bottom
          } action: {
            overscan = $0
          }
      } else {
        content
      }
    }
  }
#endif

/// A pushed screen's title inside its scrolling content on tvOS, where `screenTitle` hides the
/// navigation bar; nothing elsewhere, where the navigation bar shows it.
struct ScreenHeading: View {
  let title: String

  var body: some View {
    #if os(tvOS)
      Text(title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
    #endif
  }
}
