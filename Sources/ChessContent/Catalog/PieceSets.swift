import Foundation
import ChessCore

/// `piece-sets.json` entry: one image file per piece, named by a pattern.
///
/// SwiftPM flattens processed resources into the bundle root, so file names must be
/// unique across sets; the pattern should include the set id.
public struct PieceSet: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let nameKey: String
  public let attributionID: String
  /// File name without extension; `{color}` and `{piece}` are replaced by the codes below.
  public let fileNamePattern: String
  public let fileExtension: String
  /// Code for each `PieceColor` raw value.
  public let colorCodes: [String: String]
  /// Code for each `PieceType` raw value.
  public let pieceCodes: [String: String]

  /// The file name without extension, such as `cburnett-wK`; nil when a code is missing.
  public func resourceName(for piece: Piece) -> String? {
    guard let color = colorCodes[piece.color.rawValue], let type = pieceCodes[piece.type.rawValue]
    else {
      return nil
    }
    return
      fileNamePattern
      .replacingOccurrences(of: "{color}", with: color)
      .replacingOccurrences(of: "{piece}", with: type)
  }

  public func url(for piece: Piece, in bundle: Bundle = Localization.moduleBundle) -> URL? {
    resourceName(for: piece).flatMap { bundle.url(forResource: $0, withExtension: fileExtension) }
  }
}
