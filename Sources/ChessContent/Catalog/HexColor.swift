import Foundation

/// An sRGB color written in catalogs as `#RRGGBB` or `#RRGGBBAA`.
///
/// `ChessContent` stays free of UI frameworks, so renderers convert this to their own color type.
public struct HexColor: Codable, Hashable, Sendable, CustomStringConvertible {
  public let red: UInt8
  public let green: UInt8
  public let blue: UInt8
  public let alpha: UInt8

  public init(red: UInt8, green: UInt8, blue: UInt8, alpha: UInt8 = 255) {
    self.red = red
    self.green = green
    self.blue = blue
    self.alpha = alpha
  }

  /// Parses `#RRGGBB` or `#RRGGBBAA`; nil for anything else.
  public init?(hex: String) {
    guard hex.hasPrefix("#") else { return nil }
    let digits = hex.dropFirst()
    guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
      let value = UInt32(digits, radix: 16)
    else { return nil }
    let rgba = digits.count == 6 ? value << 8 | 0xFF : value
    self.init(
      red: UInt8(rgba >> 24 & 0xFF),
      green: UInt8(rgba >> 16 & 0xFF),
      blue: UInt8(rgba >> 8 & 0xFF),
      alpha: UInt8(rgba & 0xFF)
    )
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    let text = try container.decode(String.self)
    guard let color = Self(hex: text) else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Bad hex color \(text)"
      )
    }
    self = color
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(description)
  }

  /// `#RRGGBB`, or `#RRGGBBAA` when not opaque.
  public var description: String {
    let rgb = String(format: "#%02X%02X%02X", red, green, blue)
    return alpha == 255 ? rgb : rgb + String(format: "%02X", alpha)
  }

  /// WCAG 2 relative luminance of the color, ignoring alpha.
  var relativeLuminance: Double {
    func linear(_ channel: UInt8) -> Double {
      let value = Double(channel) / 255
      return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// WCAG 2 contrast ratio between two opaque colors, from 1 to 21.
  func contrastRatio(with other: Self) -> Double {
    let luminances = [relativeLuminance, other.relativeLuminance].sorted()
    return (luminances[1] + 0.05) / (luminances[0] + 0.05)
  }
}
