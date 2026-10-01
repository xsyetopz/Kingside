import ChessContent
import ChessCore
import Foundation
import Observation

// One game against a bot or pass-and-play.
// - Create with a `GameLaunch`; call `activate()` when the screen appears or the app becomes
//   active, and `deactivate()` when it disappears or goes to the background (stops the bot,
//   the hint and the clock, then saves).
// - `apply(_:)` is the only way the game changes; the board scene reads `snapshot`.
// - Feedback goes to the injected `FeedbackSink`. Time comes from the injected `Clock`, bot
//   and hint searches run on the `ChessEngine` actor, and every tunable is `catalog.tuning`.
// - Pure rules are static functions at the bottom, covered by unit tests.

/// Who plays the side the human does not.
public enum Opponent: Hashable, Sendable {
  /// Pass-and-play: both sides are people on this device.
  case human
  case bot(Bot)
}

/// One line of the move list: "12. Nf3 Nc6".
public struct MoveRow: Identifiable, Equatable, Sendable {
  public let number: Int
  public let white: String
  public let black: String?
  public var id: Int { number }
}

/// A player bar: which color it shows and who plays it.
public struct PlayerSlot: Equatable, Sendable {
  public let color: PieceColor
  public let info: PlayerInfo
}

/// A failed save is reported once per game; the screen dismisses the report.
enum SaveFailure {
  case none
  case reported
  case dismissed
}

@preconcurrency
@Observable
@MainActor
public final class GameSession {
  /// Everything that starts fresh with each game; `rematch` replaces it in one assignment.
  private struct PerGameState {
    var id = UUID()
    var createdAt = Date()
    var game = ChessGame()
    var result: GameResult = .ongoing
    var termination: GameTermination?
    var hasAnnouncedStart = false
    var pendingDrawOffer: PieceColor?
    var botMessage: String?
    var hint: BoardArrow?
    var saveFailure = SaveFailure.none
  }

  private var perGame: PerGameState {
    didSet { if perGame.game != oldValue.game { refreshDerived() } }
  }

  public var game: ChessGame { perGame.game }
  public var result: GameResult { perGame.result }
  public var termination: GameTermination? { perGame.termination }
  public private(set) var isBotThinking = false
  /// Latest chat line of the bot, localised; nil when there is nothing to show.
  public var botMessage: String? { perGame.botMessage }
  public private(set) var isLoadingHint = false
  /// Pass-and-play: the color that offered a draw, waiting for the other side to answer.
  public var pendingDrawOffer: PieceColor? { perGame.pendingDrawOffer }
  /// True after a save failed, so the screen can say the game will not resume; the screen
  /// sets it back to false. Raised once per game, not after every move.
  public var showsSaveFailure: Bool {
    get { perGame.saveFailure == .reported }
    set {
      if newValue {
        perGame.saveFailure = .reported
      } else if perGame.saveFailure == .reported {
        perGame.saveFailure = .dismissed
      }
    }
  }
  public private(set) var moveRows: [MoveRow] = []
  /// Opponent pieces captured by each color.
  public private(set) var capturedPieces: [PieceColor: [PieceType]] = [.white: [], .black: []]
  /// Material lead of each color in points; 0 for the side that is not ahead.
  public private(set) var materialAdvantage: [PieceColor: Int] = [.white: 0, .black: 0]
  public private(set) var topPlayer: PlayerSlot
  public private(set) var bottomPlayer: PlayerSlot
  /// Remaining time of both sides; updated every `tuning.clock.tickMilliseconds` while it runs.
  public var clock: GameClock { clockRunner.clock }
  /// Side whose clock runs while the game is ongoing; nil once it has ended.
  public private(set) var activeClockColor: PieceColor?

  public var id: UUID { perGame.id }
  public private(set) var mode: GameMode
  public private(set) var white: PlayerInfo
  public private(set) var black: PlayerInfo
  public let opponent: Opponent
  public let timeControl: TimeControl
  public let autoFlip: Bool

  private var input = MoveInput()

  private let engine: ChessEngine
  private let tuning: PlayTuning
  private let localization: Localization
  private let settings: SettingsStore
  private let store: GamePersistenceStore
  private let feedback: any FeedbackSink
  private let onSave: @MainActor () -> Void
  private let clockRunner: ClockRunner
  /// Time since the session was created, on the injected clock.
  private let now: @Sendable () -> Duration
  private let sleep: @Sendable (Duration) async throws -> Void
  @ObservationIgnored
  private var isActive = false
  @ObservationIgnored
  private(set) var botTask: Task<Void, Never>?
  @ObservationIgnored
  private var hintTask: Task<Void, Never>?
  @ObservationIgnored
  private var drawTask: Task<Void, Never>?
  /// The latest save; each save waits for the previous one, so the newest snapshot wins.
  @ObservationIgnored
  private(set) var saveTask: Task<Void, Never>?

  /// `catalog` supplies the bots and `tuning`. `onSave` runs on the main actor after each
  /// successful save. `clock` drives the game clock and the bot's minimum think time.
  @preconcurrency
  public init(
    launch: GameLaunch,
    engine: ChessEngine,
    catalog: ContentCatalog,
    localization: Localization,
    settings: SettingsStore,
    store: GamePersistenceStore,
    feedback: any FeedbackSink = NullFeedbackSink(),
    clock: some Clock<Duration> = ContinuousClock(),
    onSave: @escaping @MainActor () -> Void = {}
  ) {
    self.engine = engine
    tuning = catalog.tuning
    self.localization = localization
    self.settings = settings
    self.store = store
    self.feedback = feedback
    self.onSave = onSave
    let origin = clock.now
    now = { origin.duration(to: clock.now) }
    sleep = { try await clock.sleep(for: $0) }
    let gameClock: GameClock
    switch launch {
    case .new(let setup):
      perGame = PerGameState()
      mode = setup.mode
      white = setup.white
      black = setup.black
      timeControl = setup.timeControl
      autoFlip = setup.autoFlip
      gameClock = GameClock(timeControl: setup.timeControl)
    case .saved(let saved):
      perGame = PerGameState(
        id: saved.id,
        createdAt: saved.createdAt,
        game: saved.game,
        result: saved.result,
        termination: saved.termination,
        hasAnnouncedStart: true
      )
      mode = saved.mode
      white = saved.white
      black = saved.black
      timeControl = saved.timeControl
      autoFlip = saved.autoFlip
      gameClock = saved.clock
    }
    clockRunner = ClockRunner(
      gameClock,
      policy: .endsGame,
      tuning: catalog.tuning.clock,
      feedback: feedback,
      time: clock
    )
    let (launchMode, launchWhite, launchBlack): (GameMode, PlayerInfo, PlayerInfo)
    switch launch {
    case .new(let setup):
      (launchMode, launchWhite, launchBlack) = (setup.mode, setup.white, setup.black)
    case .saved(let saved):
      (launchMode, launchWhite, launchBlack) = (saved.mode, saved.white, saved.black)
    }
    opponent = launchMode.botID.flatMap(catalog.bots.bot(id:)).map(Opponent.bot) ?? .human
    topPlayer = PlayerSlot(color: .black, info: launchBlack)
    bottomPlayer = PlayerSlot(color: .white, info: launchWhite)
    input.lastMove = game.moves.last?.move
    input.isFlipped = initialFlip
    refreshPlayers()
    input.resetFocus(for: humanColor ?? game.position.sideToMove)
    refreshDerived()
  }

  // MARK: - Derived state

  public var bot: Bot? {
    if case .bot(let bot) = opponent { return bot }
    return nil
  }
  /// The human's color in a bot game; nil in pass-and-play.
  public var humanColor: PieceColor? { mode.humanColor(white: white, black: black) }
  public var isPassAndPlay: Bool { mode == .passAndPlay }
  public var isGameOver: Bool { result != .ongoing }
  /// True when the player may move pieces now.
  public var canMove: Bool {
    !isGameOver && !isBotThinking && pendingDrawOffer == nil
      && (humanColor == nil || game.position.sideToMove == humanColor)
  }
  public var canTakeback: Bool {
    !isGameOver
      && Self.takebackPlies(
        plyCount: game.moves.count,
        sideToMove: game.position.sideToMove,
        humanColor: humanColor
      ) > 0
  }
  /// True when `.cancel` would close the promotion picker or drop a selection; otherwise the
  /// UI may use the cancel input for its own navigation.
  public var hasCancellableSelection: Bool { input.hasCancellableSelection }
  public var resultTitle: String {
    GamePresentation.resultTitle(result, humanColor: humanColor, localization: localization)
  }
  public var resultReason: String { termination.map { localization.string($0.reasonKey) } ?? "" }
  public var statusText: String {
    if isGameOver { return localization.string("game.status.over", resultTitle, resultReason) }
    if isBotThinking, let bot {
      return localization.string("game.status.botThinking", localization.string(bot.nameKey))
    }
    return GamePresentation.turnText(
      sideToMove: game.position.sideToMove,
      humanColor: humanColor,
      inCheck: game.position.isInCheck(game.position.sideToMove),
      localization: localization
    )
  }

  public func player(_ color: PieceColor) -> PlayerInfo { color == .white ? white : black }

  /// True when `color`'s clock is at or below the low-time threshold.
  public func isLowTime(_ color: PieceColor) -> Bool { clockRunner.isLow(color) }

  public var snapshot: BoardSnapshot {
    input.snapshot(of: game.position, canMove: canMove, hint: perGame.hint)
  }

  // MARK: - Lifecycle

  /// Starts the clock and the bot. Reports `.gameStarted` and greets once for a new game.
  public func activate() {
    guard !isActive else { return }
    isActive = true
    if !perGame.hasAnnouncedStart {
      perGame.hasAnnouncedStart = true
      feedback.receive(.gameStarted)
      say(.greeting)
    }
    startClock()
    scheduleBotMoveIfNeeded()
  }

  /// Stops the bot, hint, draw decision and clock, then saves.
  public func deactivate() {
    guard isActive else { return }
    tickClock()
    isActive = false
    cancelTasks()
    save()
  }

  // MARK: - Intents

  public func apply(_ intent: BoardIntent) {
    switch intent {
    case .moveFocus(let direction): input.moveFocus(direction)
    case .focus(let square): input.focus(square)
    case .selectFocused: select(input.focusedSquare)
    case .select(let square): select(square)
    case .cancel: input.cancel()
    case .promote(let type): if let move = input.promote(type) { play(move) }
    case .requestHint: requestHint()
    case .takeback: takeback()
    case .offerDraw: offerDraw()
    case .acceptDraw: acceptDraw()
    case .declineDraw: perGame.pendingDrawOffer = nil
    case .resign: resign()
    case .flipBoard:
      input.isFlipped.toggle()
      refreshPlayers()
    case .rematch: rematch()
    case .dismissBotMessage: perGame.botMessage = nil
    }
  }

  // MARK: - Board input

  private func select(_ square: Square) {
    guard canMove else { return }
    let outcome = input.select(
      square,
      in: game.position,
      movableColor: game.position.sideToMove,
      autoQueen: settings.value.autoPromoteToQueen
    )
    switch outcome {
    case .none: break
    case .illegalTarget: feedback.receive(.illegalMove)
    case .play(let move): play(move)
    }
  }

  // MARK: - Actions

  private func requestHint() {
    guard canMove, hintTask == nil else { return }
    let game = self.game
    let limit = SearchLimit.time(tuning.game.hintAnalysisTime)
    isLoadingHint = true
    hintTask = Task { [weak self, engine] in
      let analysis = try? await engine.analyze(
        position: game.position,
        history: game.moves.map(\.positionBefore),
        limit: limit
      )
      guard let self, !Task.isCancelled else { return }
      self.hintTask = nil
      self.isLoadingHint = false
      guard self.game == game, let move = analysis?.bestMove else { return }
      self.perGame.hint = BoardArrow(from: move.from, to: move.to)
    }
  }

  private func takeback() {
    guard !isGameOver else { return }
    let plies = Self.takebackPlies(
      plyCount: game.moves.count,
      sideToMove: game.position.sideToMove,
      humanColor: humanColor
    )
    guard plies > 0 else { return }
    botTask?.cancel()
    botTask = nil
    isBotThinking = false
    cancelHint()
    perGame.pendingDrawOffer = nil
    for _ in 0..<plies { perGame.game.undo() }
    input.cancel()
    input.lastMove = game.moves.last?.move
    say(.takeback)
    applyAutoFlip()
    updateClockTurn()
    save()
  }

  private func offerDraw() {
    guard !isGameOver else { return }
    guard let humanColor else {
      perGame.pendingDrawOffer = game.position.sideToMove
      return
    }
    guard drawTask == nil else { return }
    let game = self.game
    let policy = tuning.drawOffer
    drawTask = Task { [weak self, engine] in
      let analysis = try? await engine.analyze(
        position: game.position,
        history: game.moves.map(\.positionBefore),
        limit: .time(policy.analysisTime)
      )
      guard let self, !Task.isCancelled else { return }
      self.drawTask = nil
      guard !self.isGameOver, let analysis else { return }
      if policy.botAccepts(
        evaluation: analysis.evaluation,
        botColor: humanColor.opponent,
        plyCount: game.moves.count,
        position: game.position
      ) {
        self.finish(.draw, .agreement)
      } else {
        self.say(.drawDeclined)
      }
    }
  }

  private func acceptDraw() {
    guard pendingDrawOffer != nil, !isGameOver else { return }
    perGame.pendingDrawOffer = nil
    tickClock()
    guard !isGameOver else { return }
    finish(.draw, .agreement)
  }

  private func resign() {
    guard !isGameOver else { return }
    tickClock()
    guard !isGameOver else { return }
    let loser = humanColor ?? game.position.sideToMove
    finish(.win(for: loser.opponent), .resignation)
  }

  private func rematch() {
    cancelTasks()
    swap(&white, &black)
    perGame = PerGameState()
    clockRunner.reset(to: GameClock(timeControl: timeControl))
    input = MoveInput()
    input.isFlipped = initialFlip
    input.resetFocus(for: humanColor ?? .white)
    refreshPlayers()
    if isActive {
      isActive = false
      activate()
    }
  }

  // MARK: - Moves

  private func play(_ move: ChessMove) {
    tickClock()
    let before = game.position
    let plyBefore = game.moves.count
    let mover = before.sideToMove
    do { try perGame.game.makeMove(move) } catch {
      feedback.receive(.illegalMove)
      return
    }
    clockRunner.recordMove(by: mover, plyBeforeMove: plyBefore)
    input.complete(move)
    cancelHint()
    perGame.pendingDrawOffer = nil
    if case let (result, termination)? = GameAdjudication.result(for: game.outcome) {
      finish(result, termination)
      return
    }
    feedback.receive(.moved(MoveSound.effect(for: move, before: before, after: game.position)))
    if bot != nil,
      let event = Self.chatEvent(
        moveByBot: mover != humanColor,
        isCapture: MoveSound.isCapture(move, before: before),
        givesCheck: game.position.isInCheck(game.position.sideToMove)
      )
    {
      say(event)
    }
    applyAutoFlip()
    updateClockTurn()
    save()
    scheduleBotMoveIfNeeded()
  }

  private func scheduleBotMoveIfNeeded() {
    guard isActive, !isGameOver, let bot, let humanColor, game.position.sideToMove != humanColor,
      botTask == nil
    else { return }
    isBotThinking = true
    let game = self.game
    let tuning = tuning.game
    let delay = Duration.seconds(
      Self.botThinkDelay(legalMoveCount: game.position.legalMoves().count, tuning: tuning)
    )
    let start = now()
    botTask = Task { [weak self, engine, now, sleep] in
      do {
        if let playerMove = game.moves.last {
          let history = game.moves.map(\.positionBefore)
          let limit = SearchLimit.time(tuning.blunderAnalysisTime)
          let before = try await engine.analyze(
            position: playerMove.positionBefore,
            history: Array(history.dropLast()),
            limit: limit
          )
          let after = try await engine.analyze(
            position: game.position,
            history: history,
            limit: limit
          )
          if Self.isBlunder(
            before: before.evaluation,
            after: after.evaluation,
            by: humanColor,
            tuning: tuning
          ) {
            self?.say(.playerBlunder)
          }
        }
        let move = try await engine.bestMove(game: game, strength: bot.strength)
        let remaining = delay - (now() - start)
        if remaining > .zero { try await sleep(remaining) }
        guard let self, !Task.isCancelled, self.game == game else { return }
        self.botTask = nil
        self.isBotThinking = false
        self.play(move)
      } catch {
        guard let self, !Task.isCancelled else { return }
        self.botTask = nil
        self.isBotThinking = false
      }
    }
  }

  private func finish(_ result: GameResult, _ termination: GameTermination) {
    perGame.result = result
    perGame.termination = termination
    cancelTasks()
    perGame.pendingDrawOffer = nil
    input.cancel()
    updateClockTurn()
    feedback.receive(.gameOver(result))
    if let humanColor {
      say(result == .draw ? .draw : (result.winner == humanColor ? .botLoses : .botWins))
    }
    save()
  }

  // MARK: - Clock

  private func startClock() {
    updateClockTurn()
    guard clock.isTimed, !isGameOver else { return }
    clockRunner.start { [weak self] in self?.tickClock() }
  }

  /// Charges the side to move for the time since the last tick; ends the game on a flag.
  private func tickClock() {
    let running = isActive && !isGameOver
    guard
      let flagged = clockRunner.tick(
        sideToMove: running ? game.position.sideToMove : nil,
        plyCount: game.moves.count
      )
    else { return }
    let (result, termination) = GameAdjudication.timeout(flagged: flagged, in: game.position)
    finish(result, termination)
  }

  private func updateClockTurn() {
    let active = isGameOver ? nil : game.position.sideToMove
    if activeClockColor != active { activeClockColor = active }
  }

  // MARK: - Helpers

  private func say(_ event: BotChatEvent) {
    guard let key = bot?.chat[event]?.randomElement() else { return }
    let line = localization.string(key)
    guard !line.isEmpty else { return }
    perGame.botMessage = line
  }

  private func cancelHint() {
    hintTask?.cancel()
    hintTask = nil
    isLoadingHint = false
    perGame.hint = nil
  }

  private func cancelTasks() {
    botTask?.cancel()
    botTask = nil
    drawTask?.cancel()
    drawTask = nil
    clockRunner.stop()
    cancelHint()
    isBotThinking = false
  }

  private var initialFlip: Bool {
    if isPassAndPlay && autoFlip { return game.position.sideToMove == .black }
    switch settings.value.orientation {
    case .white: return false
    case .black: return true
    case .automatic: return humanColor == .black
    }
  }

  private func applyAutoFlip() {
    guard isPassAndPlay, autoFlip else { return }
    input.isFlipped = game.position.sideToMove == .black
    input.resetFocus(for: game.position.sideToMove)
    refreshPlayers()
  }

  private func refreshDerived() {
    moveRows = GamePresentation.moveRows(game.moves)
    let position = game.position
    capturedPieces = [
      .white: Material.missing(.black, in: position),
      .black: Material.missing(.white, in: position),
    ]
    materialAdvantage = GamePresentation.materialAdvantage(in: position)
  }

  private func refreshPlayers() {
    let bottom: PieceColor = input.isFlipped ? .black : .white
    bottomPlayer = PlayerSlot(color: bottom, info: player(bottom))
    topPlayer = PlayerSlot(color: bottom.opponent, info: player(bottom.opponent))
  }

  /// Saves after the previous save finished, so the newest snapshot always wins.
  private func save() {
    guard !game.moves.isEmpty else { return }
    let snapshot = SavedGame(
      id: perGame.id,
      createdAt: perGame.createdAt,
      updatedAt: Date(),
      mode: mode,
      white: white,
      black: black,
      timeControl: timeControl,
      autoFlip: autoFlip,
      game: game,
      result: result,
      termination: termination,
      clock: clock
    )
    let previous = saveTask
    saveTask = Task { [weak self, store] in
      await previous?.value
      do {
        try await store.save(snapshot)
        self?.onSave()
      } catch {
        self?.reportSaveFailure(of: snapshot.id)
      }
    }
  }

  /// Returns once the bot's pending reply and every queued save have finished.
  func flushPendingSave() async {
    await botTask?.value
    await saveTask?.value
  }

  /// A save that fails after a rematch belongs to the previous game and is not reported.
  private func reportSaveFailure(of gameID: UUID) {
    guard perGame.id == gameID, perGame.saveFailure == .none else { return }
    perGame.saveFailure = .reported
  }

  // MARK: - Pure rules

  /// Human-like minimum think time in seconds: `botThinkBaseSeconds` plus up to
  /// `botThinkExtraSeconds` for positions with `botThinkBusyMoveCount` or more moves.
  nonisolated static func botThinkDelay(legalMoveCount: Int, tuning: GameTuning) -> TimeInterval {
    tuning.botThinkBaseSeconds
      + tuning.botThinkExtraSeconds
      * min(1, Double(legalMoveCount) / Double(tuning.botThinkBusyMoveCount))
  }

  /// True when the player's move lost `tuning.blunderCentipawns` or more.
  /// Evaluations are from White's point of view.
  nonisolated static func isBlunder(
    before: Evaluation,
    after: Evaluation,
    by player: PieceColor,
    tuning: GameTuning
  ) -> Bool {
    DrawOfferTuning.score(before, for: player) - DrawOfferTuning.score(after, for: player)
      >= tuning.blunderCentipawns
  }

  /// Plies to undo so the player is to move again; 0 when a takeback is not possible.
  nonisolated static func takebackPlies(
    plyCount: Int,
    sideToMove: PieceColor,
    humanColor: PieceColor?
  ) -> Int {
    guard let humanColor else { return plyCount > 0 ? 1 : 0 }
    let plies = sideToMove == humanColor ? 2 : 1
    return plyCount >= plies ? plies : 0
  }

  /// Chat event for a move that did not end the game.
  nonisolated static func chatEvent(
    moveByBot: Bool,
    isCapture: Bool,
    givesCheck: Bool
  ) -> BotChatEvent? {
    if moveByBot { return givesCheck ? .check : (isCapture ? .botCaptures : nil) }
    return isCapture ? .playerCaptures : nil
  }

  /// Localisation key of the game-over title; nil while the game is ongoing.
  nonisolated public static func resultTitleKey(
    _ result: GameResult,
    humanColor: PieceColor?
  ) -> String? {
    switch result {
    case .ongoing: return nil
    case .draw: return "game.result.draw.title"
    case .whiteWon, .blackWon:
      if let humanColor {
        return result.winner == humanColor
          ? "game.result.youWon.title" : "game.result.youLost.title"
      }
      return result == .whiteWon ? "game.result.whiteWon.title" : "game.result.blackWon.title"
    }
  }
}
