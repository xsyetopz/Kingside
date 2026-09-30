import ChessContent
import SwiftUI

extension EnvironmentValues {
  /// The app's strings. Views read plain text as `localization("key")` and formatted text as
  /// `localization.string("key", value)`.
  @Entry
  public var localization = Localization()
}

extension Localization {
  func callAsFunction(_ key: String) -> String { string(key) }
}
