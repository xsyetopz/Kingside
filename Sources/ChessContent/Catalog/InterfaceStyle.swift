/// Spacing, corner radii, and board framing of the SwiftUI screens, decoded from `interface.json`.
/// Colors come from the system and the app's accent color, not from here.
public struct InterfaceStyle: Codable, Hashable, Sendable {
  public let cornerRadius: Double
  /// Between items in a group.
  public let spacing: Double
  /// Between groups.
  public let sectionSpacing: Double
  /// tvOS is viewed from across the room, so its spacing is multiplied by this.
  public let tvSpacingScale: Double
  public let game: GameLayoutStyle
  public let puzzles: PuzzleLayoutStyle
  public let account: AccountLayoutStyle
  public let settings: SettingsLayoutStyle
  public let home: HomeLayoutStyle
  public let board: BoardFrameStyle
}

/// Sizes of the game screen.
public struct GameLayoutStyle: Codable, Hashable, Sendable {
  /// Width divided by height from which the board goes left and the panel right.
  public let wideAspectRatio: Double
  /// Width of the panel beside the board.
  public let panelWidth: Double
  /// Diameter of a player's avatar.
  public let avatarSize: Double
  /// Height below which the wide layout moves the player bars from above and below the board
  /// into the panel, so a short screen such as a landscape phone gives the board its height.
  public let compactHeight: Double
}

/// Sizes of the puzzle screens, which share the game screen's wide or narrow rule.
public struct PuzzleLayoutStyle: Codable, Hashable, Sendable {
  /// Side of one Puzzle Rush strike mark.
  public let strikeSize: Double
}

/// Sizes and limits of the Account screen and the welcome sheet.
public struct AccountLayoutStyle: Codable, Hashable, Sendable {
  /// Side of the linked Chess.com avatar.
  public let avatarSize: Double
  /// Side of the app symbol on the welcome sheet.
  public let welcomeIconSize: Double
  /// Games listed from the latest Chess.com archive, newest first.
  public let recentGamesLimit: Int
}

/// Sizes of the section homes and setup screens: lists on narrow screens, card grids on wide ones.
/// Every length is multiplied by `tvSpacingScale` on tvOS.
public struct HomeLayoutStyle: Codable, Hashable, Sendable {
  /// Width of the icon column in list rows, so titles line up whatever the symbol's width.
  public let iconColumnWidth: Double
  /// Between a row's icon column and its title.
  public let iconSpacing: Double
  /// Narrowest a card may get before the grid drops a column.
  public let tileMinWidth: Double
  /// Shortest a card may be, so a row of cards lines up.
  public let tileMinHeight: Double
  /// Side of the board thumbnail on a card.
  public let thumbnailSize: Double
  /// Side of the board thumbnail on a section's leading card.
  public let heroThumbnailSize: Double
  /// Widest the grid gets, so cards do not stretch across a large window.
  public let contentMaxWidth: Double
  /// Size of a new macOS window, room for the sidebar, a board, and the panel beside it.
  public let macWindowWidth: Double
  public let macWindowHeight: Double
  /// Widest the rows of a list or form get, so lines stay readable on a wide screen.
  public let formMaxWidth: Double
  /// Width of a setup screen's pane that shows the current choice and Start, beside the options.
  public let setupPaneWidth: Double
  /// Narrowest an option tile on a setup screen may get, such as a bot or a time control.
  public let choiceTileMinWidth: Double
  /// Multiplies the game avatar size for the selected bot on Play Bots.
  public let heroAvatarScale: Double
}

/// Sizes of the Settings screen.
public struct SettingsLayoutStyle: Codable, Hashable, Sendable {
  /// Side of the board preview that shows the chosen theme and piece set.
  public let previewSize: Double
  /// Width of the macOS Settings window.
  public let macWindowWidth: Double
}

/// The rounded, shadowed frame around the SpriteKit board.
public struct BoardFrameStyle: Codable, Hashable, Sendable {
  public let cornerRadius: Double
  public let shadowRadius: Double
  /// 0...1.
  public let shadowOpacity: Double
  public let shadowYOffset: Double
}
