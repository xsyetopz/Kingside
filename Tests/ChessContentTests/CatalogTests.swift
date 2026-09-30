import ChessCore
import Foundation
import Testing

@testable import ChessContent

@Suite
struct CatalogTests {
  /// WCAG 2 minimum contrast for large text and graphics; coordinates must reach it.
  private static let minimumCoordinateContrast = 3.0

  @Test
  func catalogsAreValid() throws {
    let catalog = try ContentCatalog.load()
    let bundle = Localization.moduleBundle

    // Ids are unique in each catalog.
    expectUniqueIDs(catalog.bots.bots.map(\.id), "bots")
    expectUniqueIDs(catalog.bots.groups.map(\.id), "bot groups")
    expectUniqueIDs(catalog.boardThemes.map(\.id), "board themes")
    expectUniqueIDs(catalog.pieceSets.map(\.id), "piece sets")
    expectUniqueIDs(catalog.timeControls.categories.map(\.id), "time-control categories")
    expectUniqueIDs(catalog.timeControls.presets.map(\.id), "time controls")
    expectUniqueIDs(catalog.puzzles.map(\.id), "puzzles")
    expectUniqueIDs(catalog.soundPacks.map(\.id), "sound packs")
    expectUniqueIDs(catalog.attributions.map(\.id), "attributions")

    // Every referenced resource file exists in the bundle.
    for set in catalog.pieceSets {
      for color in PieceColor.allCases {
        for type in PieceType.allCases {
          let piece = Piece(type: type, color: color)
          let name = set.resourceName(for: piece)
          #expect(name != nil, "\(set.id) has no code for \(color) \(type)")
          #expect(
            set.url(for: piece, in: bundle) != nil,
            "\(set.id): \(name ?? "?").\(set.fileExtension) is missing"
          )
        }
      }
    }

    // Every piece set and sound pack has an attribution with a license.
    let attributionRefs =
      catalog.pieceSets.map { ($0.id, $0.attributionID) }
      + catalog.soundPacks.map { ($0.id, $0.attributionID) }
    for (owner, attributionID) in attributionRefs {
      let attribution = catalog.attribution(id: attributionID)
      #expect(attribution != nil, "\(owner) references missing attribution \(attributionID)")
      #expect(
        attribution?.license.isEmpty == false,
        "\(owner): attribution \(attributionID) has no license"
      )
    }
    for attribution in catalog.attributions {
      #expect(!attribution.author.isEmpty, "\(attribution.id) has no author")
      #expect(attribution.source.scheme == "https", "\(attribution.id) source is not an https URL")
      // BSD licenses require their notice in the binary distribution.
      if attribution.license.hasPrefix("BSD") {
        #expect(
          catalog.notices[attribution.id]?.isEmpty == false,
          "\(attribution.id) has no license notice"
        )
      }
    }

    // Every localisation key a catalog references exists in the en-US catalog.
    let sourceKeys = try sourceLocalizationKeys()
    for key in localizationKeys(in: catalog) {
      #expect(sourceKeys.contains(key), "en-US has no key \(key)")
    }

    // Every color parses (decoding already failed on a bad one) and round-trips;
    // coordinates stay readable on their squares.
    for theme in catalog.boardThemes {
      let pairs = [theme.squares, theme.lastMove, theme.selection, theme.coordinates]
      let colors = pairs.flatMap { [$0.light, $0.dark] } + [theme.legalMove, theme.check]
      for color in colors {
        #expect(
          HexColor(hex: color.description) == color,
          "\(theme.id): \(color) does not round-trip"
        )
      }
      for isLight in [true, false] {
        let ratio = theme.coordinates.color(isLight: isLight).contrastRatio(
          with: theme.squares.color(isLight: isLight)
        )
        #expect(
          ratio >= Self.minimumCoordinateContrast,
          "\(theme.id): coordinate contrast \(ratio) on \(isLight ? "light" : "dark")"
        )
      }
    }
    for bot in catalog.bots.bots {
      #expect(
        HexColor(hex: bot.avatar.color.description) == bot.avatar.color,
        "\(bot.id) avatar color"
      )
    }

    // Cross references and complete maps.
    let groupIDs = Set(catalog.bots.groups.map(\.id))
    for bot in catalog.bots.bots {
      #expect(groupIDs.contains(bot.groupID), "\(bot.id) is in missing group \(bot.groupID)")
      for event in BotChatEvent.allCases {
        #expect(bot.chat[event]?.isEmpty == false, "\(bot.id) has no \(event) line")
      }
    }
    for preset in catalog.timeControls.presets {
      #expect(
        catalog.timeControls.category(for: preset) != nil,
        "time control \(preset.id) has no category"
      )
    }
    for pack in catalog.soundPacks {
      #expect(pack.sampleRate > 0 && pack.voiceCount > 0, "\(pack.id) has no voices")
      for effect in SoundEffectID.allCases {
        #expect(pack.effects[effect]?.layers.isEmpty == false, "\(pack.id) has no \(effect) sound")
      }
    }

    // Haptic pulses are in range, every haptic and event is mapped, and controller timing is
    // positive.
    let feedback = catalog.feedback
    for haptic in HapticEventID.allCases {
      let pulses = feedback.haptics[haptic]?.pulses ?? []
      #expect(!pulses.isEmpty, "haptic \(haptic) has no pulses")
      for pulse in pulses {
        #expect(
          pulse.time >= 0 && pulse.duration >= 0,
          "haptic \(haptic): time or duration below 0"
        )
        #expect(
          (0...1).contains(pulse.intensity) && (0...1).contains(pulse.sharpness),
          "haptic \(haptic): \(pulse)"
        )
      }
    }
    for kind in FeedbackEventKind.allCases {
      #expect(feedback.events[kind] != nil, "feedback event \(kind) has no cue")
    }
    let controller = feedback.controller
    #expect(controller.repeatDelay > 0 && controller.repeatInterval > 0, "controller repeat timing")
    #expect(
      controller.axisThreshold > 0 && controller.axisThreshold < 1,
      "controller axis threshold"
    )

    // Every default id exists.
    let defaults = catalog.defaults
    #expect(
      catalog.boardTheme(id: defaults.boardThemeID) != nil,
      "default board theme \(defaults.boardThemeID)"
    )
    #expect(
      catalog.pieceSet(id: defaults.pieceSetID) != nil,
      "default piece set \(defaults.pieceSetID)"
    )
    #expect(
      catalog.soundPack(id: defaults.soundPackID) != nil,
      "default sound pack \(defaults.soundPackID)"
    )
    #expect(catalog.bots.bot(id: defaults.botID) != nil, "default bot \(defaults.botID)")
    #expect(
      catalog.timeControls.preset(id: defaults.timeControlID) != nil,
      "default time control \(defaults.timeControlID)"
    )

    // Tuning values are in range and ordered.
    let tuning = catalog.tuning
    #expect(tuning.clock.lowTimeSeconds > 0, "clock low-time threshold")
    #expect(
      tuning.drawOffer.minimumPly > 0 && tuning.drawOffer.equalMargin >= 0
        && tuning.drawOffer.lowMaterialLimit >= 0,
      "draw offer"
    )
    #expect(
      tuning.clock.tickMilliseconds > 0 && tuning.drawOffer.analysisMilliseconds > 0,
      "clock tick or draw-offer analysis time"
    )
    let game = tuning.game
    #expect(
      game.botThinkBaseSeconds >= 0 && game.botThinkExtraSeconds >= 0
        && game.botThinkBusyMoveCount > 0,
      "bot think delay"
    )
    #expect(
      game.blunderCentipawns > 0 && game.blunderAnalysisMilliseconds > 0
        && game.hintAnalysisMilliseconds > 0,
      "blunder check or hint"
    )
    let rating = tuning.puzzleRating
    #expect(
      rating.minimum > 0 && rating.minimum <= rating.initial,
      "puzzle rating minimum \(rating.minimum)"
    )
    #expect(
      rating.provisionalGames >= 0 && rating.provisionalKFactor > 0
        && rating.establishedKFactor > 0,
      "puzzle K-factors"
    )
    let selection = tuning.puzzleSelection
    #expect(
      selection.ratedWindow > 0 && selection.rushWindow > 0 && selection.rushRatingStep >= 0,
      "puzzle windows"
    )
    #expect(selection.rushStartRating <= selection.rushMaximumRating, "rush rating range")
    #expect(selection.dailyMinimumRating <= selection.dailyMaximumRating, "daily rating range")
    #expect(
      catalog.puzzles.contains {
        (selection.dailyMinimumRating...selection.dailyMaximumRating).contains($0.rating)
      },
      "no daily puzzles"
    )
    #expect(tuning.puzzleRush.maxStrikes > 0, "rush strikes")
    for (mode, seconds) in tuning.puzzleRush.timeLimits {
      #expect(seconds > 0, "rush mode \(mode) has no time")
    }
    #expect((1...5000).contains(tuning.puzzleRush.nextPuzzleMilliseconds), "rush next puzzle delay")
    let pacing = tuning.puzzleBoard
    #expect(
      [pacing.introMilliseconds, pacing.replyMilliseconds, pacing.solutionStepMilliseconds]
        .allSatisfy { (1...5000).contains($0) },
      "puzzle board delays \(pacing)"
    )
    let review = tuning.review
    let losses = [
      0, review.excellentLoss, review.goodLoss, review.inaccuracyLoss, review.mistakeLoss,
    ]
    #expect(losses == losses.sorted() && review.mistakeLoss <= 1, "review loss grades \(losses)")
    let probabilities = [
      review.greatGap, review.brilliantMinWinProbability, review.missMinBestWinProbability,
      review.missMinWinProbabilityAfter,
    ]
    #expect(
      probabilities.allSatisfy { (0...1).contains($0) },
      "review probabilities \(probabilities)"
    )
    #expect(
      review.brilliantMaterial > 0 && review.analysisMilliseconds > 0,
      "review sacrifice or analysis time"
    )

    // Board rendering constants are in range and the layers stack in order.
    let style = catalog.boardStyle
    let timing = style.animation
    #expect(
      [timing.moveSeconds, timing.captureFadeSeconds, timing.focusSeconds].allSatisfy {
        (0...2).contains($0)
      },
      "board animation durations"
    )
    let layers = style.zPositions.ordered
    #expect(zip(layers, layers.dropFirst()).allSatisfy { $0 < $1 }, "board z-order \(layers)")
    #expect(
      style.markers.all.allSatisfy { $0 > 0 && $0 <= 1 },
      "board marker ratios \(style.markers.all)"
    )
    #expect(style.markers.captureRingWidth * 2 < style.markers.captureRing, "capture ring width")
    #expect(
      style.badge.ratios.allSatisfy { $0 > 0 && $0 <= 1 },
      "badge ratios \(style.badge.ratios)"
    )
    #expect(
      style.focusRing.widthRatio > 0 && style.focusRing.widthRatio <= 0.25
        && style.focusRing.minimumWidth > 0,
      "focus ring width"
    )
    #expect(!style.coordinateFontName.isEmpty, "coordinate font")

    // Every opening-book line is legal SAN from the initial position.
    #expect(!catalog.openingBook.lines.isEmpty)
    for line in catalog.openingBook.lines {
      var position = ChessPosition.initial
      for san in line.split(separator: " ") {
        let move = try #require(
          ChessNotation.move(fromSAN: String(san), in: position),
          "\(san) in \(line)"
        )
        position = try position.applying(move)
      }
    }

    // Every puzzle FEN parses and every solution move is legal.
    #expect(!catalog.puzzles.isEmpty)
    for puzzle in catalog.puzzles {
      #expect(puzzle.moves.count >= 2, "puzzle \(puzzle.id) has no solution")
      var position = try puzzle.initialPosition()
      for move in puzzle.moves {
        try #require(
          position.legalMoves().contains(move),
          "puzzle \(puzzle.id): \(move.uci) is illegal"
        )
        position = try position.applying(move)
      }
    }
  }

  @Test
  func loadsTheShippedContent() throws {
    let catalog = try ContentCatalog.load()
    #expect(catalog.bots.bots.count == 12)
    #expect(catalog.pieceSets.map(\.id) == ["cburnett"])
    #expect(catalog.attribution(id: "cburnett")?.license == "BSD-3-Clause")
    #expect(catalog.puzzles.count == 1_512)
    #expect(catalog.puzzles.map(\.rating) == catalog.puzzles.map(\.rating).sorted())
    #expect(catalog.openingBook.lines.count == 37)
    #expect(catalog.tuning.puzzleRush.timeLimits == ["threeMinutes": 180, "fiveMinutes": 300])
    let cburnett = try #require(catalog.pieceSet(id: "cburnett"))
    #expect(cburnett.resourceName(for: Piece(type: .knight, color: .white)) == "cburnett-wN")
    #expect(cburnett.resourceName(for: Piece(type: .pawn, color: .black)) == "cburnett-bP")
  }

  @Test(arguments: [
    ("1+0", "bullet", "60"), ("2+1", "bullet", "120+1"), ("3+2", "blitz", "180+2"),
    ("5+0", "blitz", "300"), ("10+0", "rapid", "600"), ("15+10", "rapid", "900+10"),
    ("untimed", "untimed", "-"),
  ])
  func groupsTimeControls(presetID: String, categoryID: String, pgn: String) throws {
    let timeControls = try ContentCatalog.load().timeControls
    let preset = try #require(timeControls.preset(id: presetID))
    #expect(timeControls.category(for: preset)?.id == categoryID)
    #expect(preset.pgnValue == pgn)
  }

  @Test
  func parsesHexColors() {
    #expect(HexColor(hex: "#E3E6DC") == HexColor(red: 0xE3, green: 0xE6, blue: 0xDC))
    #expect(HexColor(hex: "#1D313859") == HexColor(red: 0x1D, green: 0x31, blue: 0x38, alpha: 0x59))
    #expect(HexColor(hex: "#1D313859")?.description == "#1D313859")
    for bad in ["", "E3E6DC", "#E3E6D", "#E3E6DCF", "#G3E6DC", "#+3E6DC0", "#E3E6DC0011"] {
      #expect(HexColor(hex: bad) == nil, "\(bad) should not parse")
    }
    let black = HexColor(red: 0, green: 0, blue: 0)
    let white = HexColor(red: 255, green: 255, blue: 255)
    #expect(abs(black.contrastRatio(with: white) - 21) < 0.001)
    #expect(white.contrastRatio(with: white) == 1)
  }

  @Test
  func servicesAndInterfaceAreUsable() throws {
    let catalog = try ContentCatalog.load()
    let chessCom = catalog.services.chessCom
    #expect(chessCom.baseURL.scheme == "https")
    #expect(chessCom.profileURL(username: "hikaru")?.absoluteString.hasSuffix("/hikaru") == true)
    let lichess = catalog.services.lichess
    #expect(lichess.baseURL.scheme == "https")
    #expect(lichess.redirectURI.scheme?.isEmpty == false)
    #expect(!lichess.clientID.isEmpty)
    #expect(!catalog.services.contact.isEmpty)
    #expect(
      catalog.services.userAgent(product: "Kingside", version: "1.0")
        == "Kingside/1.0 (+\(catalog.services.contact))"
    )

    let style = catalog.interface
    for value in [
      style.cornerRadius, style.spacing, style.sectionSpacing, style.board.cornerRadius,
      style.board.shadowRadius,
    ] {
      #expect((0...64).contains(value))
    }
    #expect((1...4).contains(style.tvSpacingScale))
    #expect((1...3).contains(style.game.wideAspectRatio))
    #expect((0...1024).contains(style.game.panelWidth))
    #expect((0...128).contains(style.game.avatarSize))
    #expect((0...2048).contains(style.game.compactHeight))
    #expect((0...128).contains(style.puzzles.strikeSize))
    #expect((0...256).contains(style.account.avatarSize))
    #expect((0...256).contains(style.account.welcomeIconSize))
    #expect((1...100).contains(style.account.recentGamesLimit))
    #expect((64...512).contains(style.settings.previewSize))
    #expect((0...64).contains(style.home.iconColumnWidth))
    #expect((0...64).contains(style.home.iconSpacing))
    #expect((160...800).contains(style.home.tileMinWidth))
    #expect(style.home.tileMinWidth <= style.home.contentMaxWidth)
    #expect((800...1600).contains(style.home.macWindowWidth))
    #expect((500...1000).contains(style.home.macWindowHeight))
    #expect((0...400).contains(style.home.tileMinHeight))
    #expect((32...512).contains(style.home.thumbnailSize))
    #expect(style.home.thumbnailSize <= style.home.heroThumbnailSize)
    #expect((240...640).contains(style.home.setupPaneWidth))
    #expect(style.home.setupPaneWidth < style.home.contentMaxWidth)
    #expect((80...400).contains(style.home.choiceTileMinWidth))
    #expect((1...6).contains(style.home.heroAvatarScale))
    #expect((320...1024).contains(style.settings.macWindowWidth))
    #expect((0...1).contains(style.board.shadowOpacity))
  }

  private func expectUniqueIDs(_ ids: [String], _ catalog: String) {
    let duplicates = Dictionary(grouping: ids, by: \.self).filter { $0.value.count > 1 }.keys
      .sorted()
    #expect(duplicates.isEmpty, "duplicate \(catalog) ids: \(duplicates)")
  }

  private func localizationKeys(in catalog: ContentCatalog) -> [String] {
    let bots =
      catalog.bots.groups.map(\.nameKey)
      + catalog.bots.bots.flatMap { [$0.nameKey, $0.bioKey] + $0.chat.values.flatMap(\.self) }
    let timeControls =
      catalog.timeControls.categories.map(\.nameKey) + catalog.timeControls.presets.map(\.labelKey)
    return bots + timeControls
      + catalog.boardThemes.map(\.nameKey)
      + catalog.pieceSets.map(\.nameKey)
      + catalog.soundPacks.map(\.nameKey)
      + catalog.attributions.map(\.titleKey)
  }

  private func sourceLocalizationKeys() throws -> Set<String> {
    let directory = try #require(Localization.directoryName(for: Localization.sourceLocalization))
    return try Set(
      ["strings", "stringsdict"].flatMap { ext in
        let path = try #require(
          Localization.moduleBundle.path(
            forResource: "Localizable",
            ofType: ext,
            inDirectory: "\(directory).lproj"
          )
        )
        return try #require(
          PropertyListSerialization.propertyList(
            from: Data(contentsOf: URL(fileURLWithPath: path)),
            format: nil
          ) as? [String: Any]
        ).keys
      }
    )
  }
}
