import ChessContent
import Testing

@testable import ChessUI

@MainActor
struct SettingsTests {
  @Test
  func attributionsGroupByWhatUsesThem() throws {
    let catalog = try ContentCatalog.load()
    let groups = LicenseGroup.groups(in: catalog)
    let kinds = groups.map(\.kind)
    #expect(
      kinds
        == kinds.sorted {
          LicenseKind.allCases.firstIndex(of: $0)! < LicenseKind.allCases.firstIndex(of: $1)!
        }
    )
    #expect(
      groups.flatMap(\.attributions).map(\.id).sorted() == catalog.attributions.map(\.id).sorted()
    )
    let pieces = try #require(groups.first { $0.kind == .pieces })
    #expect(pieces.attributions.map(\.id) == catalog.pieceSets.map(\.attributionID).uniqued)
    let sounds = try #require(groups.first { $0.kind == .sounds })
    #expect(sounds.attributions.map(\.id) == catalog.soundPacks.map(\.attributionID).uniqued)
    #expect(groups.allSatisfy { !$0.attributions.isEmpty })
  }

  @Test
  func hexColorConvertsToUnitComponents() throws {
    let opaque = try #require(HexColor(hex: "#FF8000")).unitComponents
    #expect(opaque.red == 1 && opaque.green == 128.0 / 255 && opaque.blue == 0 && opaque.alpha == 1)
    let translucent = try #require(HexColor(hex: "#00000080")).unitComponents
    #expect(translucent.alpha == 128.0 / 255)
  }
}

private extension Array where Element: Hashable {
  var uniqued: [Element] {
    var seen = Set<Element>()
    return filter { seen.insert($0).inserted }
  }
}
