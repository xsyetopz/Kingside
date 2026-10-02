import Foundation

/// Resolves the packaged `Localizable` strings and plurals.
///
/// `ChessContent` owns the only catalog. Every UI string goes through a key here;
/// `en-US` is the source language and the fallback for keys a locale lacks.
public struct Localization: Sendable {
  static let sourceLocalization = "en-US"

  /// The SwiftPM resource bundle. Tests pin this instead of `Bundle.main`.
  public static var moduleBundle: Bundle { .module }

  /// The localization chosen for the injected preference order, if any.
  let resolvedLanguage: String?

  private let preferredBundle: Bundle?
  private let sourceBundle: Bundle?
  private let locale: Locale

  public init(
    bundle: Bundle = Self.moduleBundle,
    preferredLanguages: [String] = Locale.preferredLanguages
  ) {
    let names = Self.availableLocalizations(in: bundle)
    let preferred = Bundle.preferredLocalizations(from: names, forPreferences: preferredLanguages)
      .first
    let language = preferred.flatMap { match in
      names.first { $0.caseInsensitiveCompare(match) == .orderedSame }
    }
    resolvedLanguage = language
    preferredBundle = language.flatMap { Self.lprojBundle($0, in: bundle, among: names) }
    sourceBundle =
      [Self.sourceLocalization, "en", "C"].lazy
      .compactMap { Self.lprojBundle($0, in: bundle, among: names) }.first
    locale =
      language.map { Locale(identifier: $0.replacingOccurrences(of: "-", with: "_")) } ?? .current
  }

  /// The best packaged value for `key`: the chosen locale, then source English,
  /// then `defaultValue`, then the key itself.
  public func string(_ key: String, defaultValue: String? = nil) -> String {
    lookup(key, fallback: defaultValue ?? key)
  }

  /// Formats `key` with `arguments`, using the chosen locale's number formatting.
  public func string(_ key: String, _ arguments: any CVarArg...) -> String {
    String(format: string(key), locale: locale, arguments: arguments)
  }

  /// Formats `count` through a `Localizable.stringsdict` plural (`%#@count@`).
  /// Foundation picks the CLDR category, so callers never branch on `count == 1`.
  public func plural(_ key: String, count: Int, defaultValue: String? = nil) -> String {
    String(format: lookup(key, fallback: defaultValue ?? key), locale: locale, arguments: [count])
  }

  private func lookup(_ key: String, fallback: String) -> String {
    for bundle in [preferredBundle, sourceBundle].compactMap(\.self) {
      let value = bundle.localizedString(forKey: key, value: fallback, table: "Localizable")
      if value != fallback { return value }
    }
    return fallback
  }

  /// Locale directories packaged in `bundle`, excluding `Base`. SwiftPM may lowercase
  /// the directory names (`en-us.lproj`), so compare them case-insensitively.
  static func availableLocalizations(
    in bundle: Bundle = Self.moduleBundle
  ) -> [String] {
    let entries =
      bundle.resourceURL.flatMap {
        try? FileManager.default.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)
      } ?? []
    let directories = entries.filter { $0.pathExtension == "lproj" }.map {
      $0.deletingPathExtension().lastPathComponent
    }
    let names = directories.isEmpty ? bundle.localizations : directories
    return names.filter { $0.caseInsensitiveCompare("Base") != .orderedSame }.sorted()
  }

  /// The packaged directory name for `language`, matched case-insensitively.
  static func directoryName(
    for language: String,
    in bundle: Bundle = Self.moduleBundle
  ) -> String? {
    availableLocalizations(in: bundle).first { $0.caseInsensitiveCompare(language) == .orderedSame }
  }

  private static func lprojBundle(
    _ language: String,
    in bundle: Bundle,
    among names: [String]
  ) -> Bundle? {
    // Device file systems are case-sensitive, so use the packaged spelling.
    guard let name = names.first(where: { $0.caseInsensitiveCompare(language) == .orderedSame })
    else { return nil }
    return bundle.path(forResource: name, ofType: "lproj").flatMap(Bundle.init(path:))
  }
}
