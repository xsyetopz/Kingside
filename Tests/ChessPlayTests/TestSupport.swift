import Foundation
import Testing

import ChessContent

/// Values shared by every ChessPlay test.
enum Shared {
  /// The bundled catalog, decoded once.
  static let loadedCatalog = Result { try ContentCatalog.load() }

  static var catalog: ContentCatalog {
    get throws { try loadedCatalog.get() }
  }

  /// Source English, independent of the machine's language settings.
  static let english = Localization(preferredLanguages: ["en-US"])
}

/// Runs `body` with an empty `UserDefaults` suite that is removed afterwards.
func withTemporaryDefaults<Value>(_ body: (UserDefaults) throws -> Value) throws -> Value {
  let suite = "ChessPlayTests.\(UUID().uuidString)"
  let defaults = try #require(UserDefaults(suiteName: suite))
  defer { defaults.removePersistentDomain(forName: suite) }
  return try body(defaults)
}

/// Runs `body` with a new empty directory that is removed afterwards.
func withTemporaryDirectory<Value>(_ body: (URL) async throws -> Value) async throws -> Value {
  let directory = FileManager.default.temporaryDirectory
    .appending(component: "ChessPlayTests-\(UUID().uuidString)", directoryHint: .isDirectory)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  return try await body(directory)
}

/// URL of a file in this target's `Fixtures` directory.
func fixtureURL(_ name: String) throws -> URL {
  let url = Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
  return try #require(url, "Missing fixture \(name)")
}
