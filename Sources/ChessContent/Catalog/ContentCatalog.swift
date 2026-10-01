import Foundation

/// All game content, decoded from the JSON catalogs bundled with `ChessContent`.
///
/// Adding a bot, board theme, piece set, time control, sound pack, or tuning value changes only
/// these files and their assets. `ChessContentTests.catalogsAreValid` checks the references.
public struct ContentCatalog: Sendable {
  public let bots: BotCatalog
  public let boardThemes: [BoardTheme]
  public let boardStyle: BoardStyle
  public let pieceSets: [PieceSet]
  public let timeControls: TimeControlCatalog
  /// Sorted by rating, easiest first.
  public let puzzles: [Puzzle]
  public let soundPacks: [SoundPack]
  public let feedback: FeedbackTuning
  public let attributions: [Attribution]
  /// License notices that must ship with the app, by attribution ID.
  public let notices: [Attribution.ID: String]
  public let defaults: ContentDefaults
  public let tuning: PlayTuning
  public let openingBook: OpeningBook
  public let services: ServiceEndpoints
  public let chatFilter: ChatFilter
  public let interface: InterfaceStyle

  public static func load(from bundle: Bundle = Localization.moduleBundle) throws -> Self {
    let decoder = JSONDecoder()
    func decode<Value: Decodable>(_ type: Value.Type, _ name: String) throws -> Value {
      // SwiftPM flattens processed resources, so `Catalogs/` is not part of the path.
      guard let url = bundle.url(forResource: name, withExtension: "json") else {
        throw ContentCatalogError.missingFile("\(name).json")
      }
      do {
        return try decoder.decode(type, from: Data(contentsOf: url))
      } catch {
        throw ContentCatalogError.invalidFile("\(name).json", String(describing: error))
      }
    }
    let attributions = try decode(AttributionFile.self, "attributions").attributions
    var notices: [Attribution.ID: String] = [:]
    for attribution in attributions {
      guard let file = attribution.noticeFile else { continue }
      guard let url = bundle.url(forResource: file, withExtension: "txt"),
        let text = try? String(contentsOf: url, encoding: .utf8)
      else {
        throw ContentCatalogError.missingFile("\(file).txt")
      }
      notices[attribution.id] = text
    }
    return Self(
      bots: try decode(BotCatalog.self, "bots"),
      boardThemes: try decode(BoardThemeFile.self, "board-themes").themes,
      boardStyle: try decode(BoardStyle.self, "board-style"),
      pieceSets: try decode(PieceSetFile.self, "piece-sets").sets,
      timeControls: try decode(TimeControlCatalog.self, "time-controls"),
      puzzles: try decode([Puzzle].self, "puzzles").sorted { $0.rating < $1.rating },
      soundPacks: try decode(SoundPackFile.self, "sound-packs").packs,
      feedback: try decode(FeedbackTuning.self, "haptics"),
      attributions: attributions,
      notices: notices,
      defaults: try decode(ContentDefaults.self, "defaults"),
      tuning: try decode(PlayTuning.self, "play-tuning"),
      openingBook: try decode(OpeningBook.self, "opening-book"),
      services: try decode(ServiceEndpoints.self, "services"),
      chatFilter: try decode(ChatFilter.self, "chat-filter"),
      interface: try decode(InterfaceStyle.self, "interface")
    )
  }

  public func boardTheme(id: String) -> BoardTheme? { boardThemes.first { $0.id == id } }

  public func pieceSet(id: String) -> PieceSet? { pieceSets.first { $0.id == id } }

  public func soundPack(id: String) -> SoundPack? { soundPacks.first { $0.id == id } }

  public func attribution(id: String) -> Attribution? { attributions.first { $0.id == id } }

  private struct BoardThemeFile: Decodable { let themes: [BoardTheme] }
  private struct PieceSetFile: Decodable { let sets: [PieceSet] }
  private struct SoundPackFile: Decodable { let packs: [SoundPack] }
  private struct AttributionFile: Decodable { let attributions: [Attribution] }
}

/// `defaults.json`: the choices a fresh install starts with.
public struct ContentDefaults: Codable, Hashable, Sendable {
  public let boardThemeID: String
  public let pieceSetID: String
  public let soundPackID: String
  public let botID: String
  let timeControlID: String
}

/// `attributions.json` entry: credit and license for bundled third-party or original assets.
public struct Attribution: Codable, Hashable, Identifiable, Sendable {
  public let id: String
  public let titleKey: String
  public let author: String
  /// SPDX license identifier, such as `BSD-3-Clause`.
  public let license: String
  public let source: URL
  /// Name of a bundled `.txt` license notice the license requires in the distribution.
  let noticeFile: String?
}

enum ContentCatalogError: Error, Equatable, LocalizedError {
  case missingFile(String)
  case invalidFile(String, String)

  var errorDescription: String? {
    switch self {
    case .missingFile(let name): "Content catalog \(name) is not in the bundle."
    case .invalidFile(let name, let reason): "Content catalog \(name) does not decode: \(reason)"
    }
  }
}
