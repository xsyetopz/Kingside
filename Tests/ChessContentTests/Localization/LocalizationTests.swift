import Foundation
import Testing

@testable import ChessContent

@Suite
struct LocalizationTests {
  @Test
  func packagesEveryLocale() {
    let locales = Set(Localization.availableLocalizations().map { $0.lowercased() })
    #expect(locales.count == 83)
    #expect(locales.isSuperset(of: ["en-us", "c", "ar-sa", "zh-tw"]))
  }

  @Test
  func everyLocaleHasTheSourceKeys() throws {
    let source = try catalogKeys(Localization.sourceLocalization)
    #expect(!source.isEmpty)
    for locale in Localization.availableLocalizations() {
      #expect(try catalogKeys(locale) == source, "\(locale) keys differ from the source")
    }
  }

  @Test
  func sourcePluralsFillEveryCategory() throws {
    let categories: Set = ["zero", "one", "two", "few", "many", "other"]
    let plurals = try plist(Localization.sourceLocalization, "stringsdict")
    for (key, value) in plurals {
      let entry = try #require(value as? [String: Any])
      let variables = entry.filter { !$0.key.hasPrefix("NSString") }.compactMap {
        $0.value as? [String: Any]
      }
      #expect(!variables.isEmpty, "\(key) has no plural variable")
      for variable in variables {
        #expect(Set(variable.keys.filter { !$0.hasPrefix("NSString") }) == categories, "\(key)")
      }
    }
  }

  /// A translation with a missing or changed specifier shows wrong text or crashes
  /// `String(format:)`.
  @Test
  func everyLocaleKeepsTheSourceFormatSpecifiers() throws {
    let source = try catalogValues(Localization.sourceLocalization)
    for locale in Localization.availableLocalizations() {
      let values = try catalogValues(locale)
      for (key, sourceValue) in source {
        guard let value = values[key] else { continue }
        #expect(specifiers(value) == specifiers(sourceValue), "\(locale): \(key) = \(value)")
      }
    }
  }

  @Test
  func resolvesSourceEnglishAndPlurals() {
    let english = Localization(preferredLanguages: ["en-US"])
    #expect(english.resolvedLanguage?.lowercased() == "en-us")
    #expect(english.string("common.cancel") == "Cancel")
    #expect(english.plural("common.moves", count: 1) == "1 move")
    #expect(english.plural("common.moves", count: 2) == "2 moves")
  }

  @Test
  func picksThePreferredLocaleAndFallsBack() {
    let german = Localization(preferredLanguages: ["de-DE", "en-US"])
    #expect(german.resolvedLanguage?.lowercased() == "de-de")
    #expect(german.string("test.missing.key", defaultValue: "Fallback") == "Fallback")
    #expect(german.string("test.missing.key") == "test.missing.key")
  }

  private func plist(_ locale: String, _ ext: String) throws -> [String: Any] {
    let directory = try #require(Localization.directoryName(for: locale), "no \(locale).lproj")
    let path = try #require(
      Localization.moduleBundle.path(
        forResource: "Localizable",
        ofType: ext,
        inDirectory: "\(directory).lproj"
      ),
      "\(locale).lproj has no Localizable.\(ext)"
    )
    return try #require(
      PropertyListSerialization.propertyList(
        from: Data(contentsOf: URL(fileURLWithPath: path)),
        format: nil
      ) as? [String: Any]
    )
  }

  private func catalogKeys(_ locale: String) throws -> Set<String> {
    Set(try plist(locale, "strings").keys).union(try plist(locale, "stringsdict").keys)
  }

  /// Every string value, with plural values keyed as "key/variable/category".
  private func catalogValues(_ locale: String) throws -> [String: String] {
    var values = try plist(locale, "strings").compactMapValues { $0 as? String }
    for (key, entry) in try plist(locale, "stringsdict") {
      for (name, value) in try #require(entry as? [String: Any]) {
        if let text = value as? String {
          values["\(key)/\(name)"] = text
        } else if let variable = value as? [String: Any] {
          for (category, text) in variable where !category.hasPrefix("NSString") {
            values["\(key)/\(name)/\(category)"] = text as? String
          }
        }
      }
    }
    return values
  }

  /// The sorted format specifiers in `text`: `%%`, `%#@name@`, and `%@` or `%d` with an optional
  /// position.
  private func specifiers(_ text: String) -> [String] {
    let pattern = /%(?:%|#@[A-Za-z0-9_]+@|(?:[0-9]+\$)?[-+0-9.#]*(?:ll|l|h)?[@a-zA-Z])/
    return text.matches(of: pattern).map { String($0.output) }.sorted()
  }
}
