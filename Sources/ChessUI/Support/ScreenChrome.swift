import ChessContent
import SwiftUI

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

  /// Keeps a scrolling list's or form's rows at most `formMaxWidth` wide and centered. Outside
  /// tvOS its background and scrolling still span the whole width.
  func readableRows(_ style: InterfaceStyle) -> some View {
    modifier(ReadableRows(maxWidth: style.home.formMaxWidth * style.platformScale))
  }
}

#if os(tvOS)
  private struct ReadableRows: ViewModifier {
    let maxWidth: Double

    // tvOS lists ignore `contentMargins`, and their background is clear, so a frame is enough.
    func body(content: Content) -> some View {
      content
        .frame(maxWidth: maxWidth)
        .frame(maxWidth: .infinity)
    }
  }
#else
  private struct ReadableRows: ViewModifier {
    let maxWidth: Double
    @State
    private var inset = 0.0

    func body(content: Content) -> some View {
      content
        .contentMargins(.horizontal, inset, for: .scrollContent)
        .onGeometryChange(for: Double.self) {
          $0.size.width
        } action: { width in
          inset = max(0, (width - maxWidth) / 2)
        }
    }
  }
#endif

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
