import ChessContent
import SwiftUI

/// What an attribution credits, used to group the Licenses list.
enum LicenseKind: CaseIterable {
  case pieces, sounds, other

  /// Localisation key of the group title.
  var titleKey: String {
    switch self {
    case .pieces: "licenses.kind.pieces"
    case .sounds: "licenses.kind.sounds"
    case .other: "licenses.kind.other"
    }
  }
}

/// The attributions of one kind, in catalog order.
struct LicenseGroup: Identifiable {
  let kind: LicenseKind
  let attributions: [Attribution]

  var id: LicenseKind { kind }

  /// Groups the catalog's attributions by what uses them: piece sets, sound packs, or anything
  /// else. Groups without attributions are left out, and kinds keep their `LicenseKind` order.
  static func groups(in catalog: ContentCatalog) -> [Self] {
    let pieceIDs = Set(catalog.pieceSets.map(\.attributionID))
    let soundIDs = Set(catalog.soundPacks.map(\.attributionID))
    func kind(of attribution: Attribution) -> LicenseKind {
      if pieceIDs.contains(attribution.id) {
        .pieces
      } else if soundIDs.contains(attribution.id) {
        .sounds
      } else {
        .other
      }
    }
    let byKind = Dictionary(grouping: catalog.attributions, by: kind(of:))
    return LicenseKind.allCases.compactMap { kind in
      byKind[kind].map { Self(kind: kind, attributions: $0) }
    }
  }
}

/// Credit and license of every bundled third-party or original asset.
struct LicensesScreen: View {
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    Form {
      ScreenHeading(title: localization("licenses.title")).listRowBackground(Color.clear)
      ForEach(LicenseGroup.groups(in: model.catalog)) { group in
        Section(localization(group.kind.titleKey)) {
          ForEach(group.attributions) { attribution in
            AttributionRow(attribution: attribution)
            if let notice = model.catalog.notices[attribution.id] {
              NavigationLink(localization("licenses.notice")) {
                LicenseNoticeScreen(title: localization(attribution.titleKey), notice: notice)
              }
            }
          }
        }
      }
    }
    .formStyle(.grouped)
    .readableRows(model.catalog.interface)
    .screenTitle(localization("licenses.title"), chrome: .pushed)
  }
}

/// A license notice, one row per paragraph so focus can scroll through it on tvOS.
private struct LicenseNoticeScreen: View {
  let title: String
  let notice: String
  @Environment(AppModel.self)
  private var model

  var body: some View {
    List {
      ScreenHeading(title: title).listRowBackground(Color.clear)
      ForEach(Array(notice.components(separatedBy: "\n\n").enumerated()), id: \.offset) {
        _,
        paragraph in
        Text(paragraph.replacingOccurrences(of: "\n", with: " "))
          .font(.footnote)
          .modifier(ReadOnlyRow())
      }
    }
    .readableRows(model.catalog.interface)
    .screenTitle(title, chrome: .pushed)
  }
}

private struct AttributionRow: View {
  let attribution: Attribution
  @Environment(\.localization)
  private var localization

  var body: some View {
    VStack(alignment: .leading) {
      Text(localization(attribution.titleKey))
      LabeledContent(localization("licenses.author"), value: attribution.author)
      LabeledContent(localization("licenses.license"), value: attribution.license)
      #if os(tvOS)
        Text(attribution.source.absoluteString).foregroundStyle(.secondary)
      #else
        Link(attribution.source.absoluteString, destination: attribution.source)
      #endif
    }
    .modifier(ReadOnlyRow())
  }
}

/// On tvOS, focus rests on a read-only row so the remote can scroll the list; the focus
/// engine draws no effect on it, so the row draws an outline.
private struct ReadOnlyRow: ViewModifier {
  #if os(tvOS)
    @Environment(AppModel.self)
    private var model
    @FocusState
    private var isFocused: Bool
  #endif

  func body(content: Content) -> some View {
    #if os(tvOS)
      let style = model.catalog.interface
      content
        .focusable()
        .focused($isFocused)
        .overlay {
          RoundedRectangle(cornerRadius: style.cornerRadius, style: .continuous)
            .strokeBorder(.tint, lineWidth: 2 * style.platformScale)
            .padding(-style.gap / 2)
            .opacity(isFocused ? 1 : 0)
        }
    #else
      content
    #endif
  }
}
