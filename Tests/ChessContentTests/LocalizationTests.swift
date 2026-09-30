import Foundation
import Testing

@testable import ChessContent

@Suite struct LocalizationTests {
    @Test func packagesEveryLocale() {
        let locales = Set(Localization.availableLocalizations().map { $0.lowercased() })
        #expect(locales.count == 83)
        #expect(locales.isSuperset(of: ["en-us", "c", "ar-sa", "zh-tw"]))
    }

    @Test func everyLocaleHasTheSourceKeys() throws {
        let source = try catalogKeys(Localization.sourceLocalization)
        #expect(!source.isEmpty)
        for locale in Localization.availableLocalizations() {
            #expect(try catalogKeys(locale) == source, "\(locale) keys differ from the source")
        }
    }

    @Test func sourcePluralsFillEveryCategory() throws {
        let categories: Set = ["zero", "one", "two", "few", "many", "other"]
        let plurals = try plist(Localization.sourceLocalization, "stringsdict")
        for (key, value) in plurals {
            let entry = try #require(value as? [String: Any])
            let variables = entry.filter { !$0.key.hasPrefix("NSString") }.compactMap { $0.value as? [String: Any] }
            #expect(!variables.isEmpty, "\(key) has no plural variable")
            for variable in variables {
                #expect(Set(variable.keys.filter { !$0.hasPrefix("NSString") }) == categories, "\(key)")
            }
        }
    }

    @Test func resolvesSourceEnglishAndPlurals() {
        let english = Localization(preferredLanguages: ["en-US"])
        #expect(english.resolvedLanguage?.lowercased() == "en-us")
        #expect(english.string("common.cancel") == "Cancel")
        #expect(english.plural("common.moves", count: 1) == "1 move")
        #expect(english.plural("common.moves", count: 2) == "2 moves")
    }

    @Test func picksThePreferredLocaleAndFallsBack() {
        let german = Localization(preferredLanguages: ["de-DE", "en-US"])
        #expect(german.resolvedLanguage?.lowercased() == "de-de")
        #expect(german.string("test.missing.key", defaultValue: "Fallback") == "Fallback")
        #expect(german.string("test.missing.key") == "test.missing.key")
    }

    private func plist(_ locale: String, _ ext: String) throws -> [String: Any] {
        let directory = try #require(Localization.directoryName(for: locale), "no \(locale).lproj")
        let path = try #require(
            Localization.moduleBundle.path(forResource: "Localizable", ofType: ext, inDirectory: "\(directory).lproj"),
            "\(locale).lproj has no Localizable.\(ext)")
        return try #require(NSDictionary(contentsOfFile: path) as? [String: Any])
    }

    private func catalogKeys(_ locale: String) throws -> Set<String> {
        Set(try plist(locale, "strings").keys).union(try plist(locale, "stringsdict").keys)
    }
}
