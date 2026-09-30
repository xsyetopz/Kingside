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

@Observable
@MainActor
public final class GameSession {
    public private(set) var game = ChessGame() { didSet { refreshDerived() } }
    public private(set) var result: GameResult = .ongoing
    public private(set) var termination: GameTermination?
    public private(set) var isBotThinking = false
    /// Latest chat line of the bot, localised; nil when there is nothing to show.
    public private(set) var botMessage: String?
    public private(set) var isLoadingHint = false
    /// Pass-and-play: the color that offered a draw, waiting for the other side to answer.
    public private(set) var pendingDrawOffer: PieceColor?
    public private(set) var moveRows: [MoveRow] = []
    /// Opponent pieces captured by each color.
    public private(set) var capturedPieces: [PieceColor: [PieceType]] = [.white: [], .black: []]
    /// Material lead of each color in points; 0 for the side that is not ahead.
    public private(set) var materialAdvantage: [PieceColor: Int] = [.white: 0, .black: 0]
    public private(set) var topPlayer: PlayerSlot
    public private(set) var bottomPlayer: PlayerSlot
    /// Remaining time of both sides; updated every `tuning.clock.tickMilliseconds` while it runs.
    public private(set) var clock: GameClock
    /// Side whose clock runs while the game is ongoing; nil once it has ended.
    public private(set) var activeClockColor: PieceColor?

    public private(set) var id: UUID
    public private(set) var mode: GameMode
    public private(set) var white: PlayerInfo
    public private(set) var black: PlayerInfo
    public let opponent: Opponent
    public let timeControl: TimeControl
    public let autoFlip: Bool

    private var board = BoardInteraction()
    private var hint: BoardArrow?
    /// Promotion moves waiting for `.promote`; empty when no picker is shown.
    private var pendingPromotion: [ChessMove] = []

    private let engine: ChessEngine
    private let tuning: PlayTuning
    private let localization: Localization
    private let settings: SettingsStore
    private let store: GamePersistenceStore
    private let feedback: any FeedbackSink
    private let onSave: @MainActor () -> Void
    /// Time since the session was created, on the injected clock.
    private let now: @Sendable () -> Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var createdAt: Date
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var hasAnnouncedStart: Bool
    @ObservationIgnored private var lowTimeWarned: Set<PieceColor> = []
    @ObservationIgnored private var lastTick: Duration = .zero
    @ObservationIgnored private(set) var botTask: Task<Void, Never>?
    @ObservationIgnored private var hintTask: Task<Void, Never>?
    @ObservationIgnored private var drawTask: Task<Void, Never>?
    @ObservationIgnored private var clockTask: Task<Void, Never>?
    /// The latest save; each save waits for the previous one, so the newest snapshot wins.
    @ObservationIgnored private(set) var saveTask: Task<Void, Never>?

    /// `catalog` supplies the bots and `tuning`. `onSave` runs on the main actor after each
    /// completed save. `clock` drives the game clock and the bot's minimum think time.
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
        switch launch {
        case .new(let setup):
            id = UUID()
            createdAt = Date()
            mode = setup.mode
            white = setup.white
            black = setup.black
            timeControl = setup.timeControl
            autoFlip = setup.autoFlip
            self.clock = GameClock(timeControl: setup.timeControl)
            hasAnnouncedStart = false
        case .saved(let saved):
            id = saved.id
            createdAt = saved.createdAt
            mode = saved.mode
            white = saved.white
            black = saved.black
            timeControl = saved.timeControl
            autoFlip = saved.autoFlip
            self.clock = saved.clock
            game = saved.game
            result = saved.result
            termination = saved.termination
            hasAnnouncedStart = true
        }
        let (launchMode, launchWhite, launchBlack): (GameMode, PlayerInfo, PlayerInfo)
        switch launch {
        case .new(let setup): (launchMode, launchWhite, launchBlack) = (setup.mode, setup.white, setup.black)
        case .saved(let saved): (launchMode, launchWhite, launchBlack) = (saved.mode, saved.white, saved.black)
        }
        opponent = launchMode.botID.flatMap(catalog.bots.bot(id:)).map(Opponent.bot) ?? .human
        topPlayer = PlayerSlot(color: .black, info: launchBlack)
        bottomPlayer = PlayerSlot(color: .white, info: launchWhite)
        board.lastMove = game.moves.last?.move
        board.isFlipped = initialFlip
        board.resetFocus(for: humanColor ?? game.position.sideToMove)
        refreshDerived()
    }

    // MARK: - Derived state

    public var bot: Bot? {
        if case .bot(let bot) = opponent { return bot }
        return nil
    }
    /// The human's color in a bot game; nil in pass-and-play.
    public var humanColor: PieceColor? { mode.botID == nil ? nil : (white.isBot ? .black : .white) }
    public var isPassAndPlay: Bool { mode == .passAndPlay }
    public var isGameOver: Bool { result != .ongoing }
    /// True when the player may move pieces now.
    public var canMove: Bool {
        !isGameOver && !isBotThinking && pendingDrawOffer == nil
            && (humanColor == nil || game.position.sideToMove == humanColor)
    }
    public var canTakeback: Bool {
        !isGameOver && Self.takebackPlies(plyCount: game.moves.count, sideToMove: game.position.sideToMove, humanColor: humanColor) > 0
    }
    /// True when `.cancel` would close the promotion picker or drop a selection; otherwise the
    /// UI may use the cancel input for its own navigation.
    public var hasCancellableSelection: Bool { !pendingPromotion.isEmpty || board.selectedSquare != nil }
    public var resultTitle: String { Self.resultTitle(result, humanColor: humanColor, localization: localization) }
    public var resultReason: String { termination.map { localization.string($0.reasonKey) } ?? "" }
    public var statusText: String {
        if isGameOver { return localization.string("game.status.over", resultTitle, resultReason) }
        if isBotThinking, let bot { return localization.string("game.status.botThinking", localization.string(bot.nameKey)) }
        return Self.turnText(sideToMove: game.position.sideToMove, humanColor: humanColor,
                             inCheck: game.position.isInCheck(game.position.sideToMove), localization: localization)
    }

    public func player(_ color: PieceColor) -> PlayerInfo { color == .white ? white : black }

    /// True when `color`'s clock is at or below the low-time threshold.
    public func isLowTime(_ color: PieceColor) -> Bool { clock.isLow(color, tuning: tuning.clock) }

    public var snapshot: BoardSnapshot {
        let position = game.position
        let side = position.sideToMove
        let king = Piece(type: .king, color: side)
        return BoardSnapshot(
            pieces: position.board,
            orientation: board.isFlipped ? .black : .white,
            focusedSquare: board.focusedSquare,
            selectedSquare: board.selectedSquare,
            legalTargets: board.legalTargets,
            lastMove: board.lastMove,
            checkSquare: position.isInCheck(side) ? position.board.first { $0.value == king }?.key : nil,
            hint: hint,
            pendingPromotion: pendingPromotion.first.map { move in
                PendingPromotion(from: move.from, to: move.to, color: side, choices: pendingPromotion.compactMap(\.promotion))
            },
            isInputEnabled: canMove && pendingPromotion.isEmpty
        )
    }

    // MARK: - Lifecycle

    /// Starts the clock and the bot. Reports `.gameStarted` and greets once for a new game.
    public func activate() {
        guard !isActive else { return }
        isActive = true
        if !hasAnnouncedStart {
            hasAnnouncedStart = true
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
        case .moveFocus(let direction): board.moveFocus(direction)
        case .focus(let square): board.focusedSquare = square
        case .selectFocused: select(board.focusedSquare)
        case .select(let square): select(square)
        case .cancel: cancelSelection()
        case .promote(let type): choosePromotion(type)
        case .requestHint: requestHint()
        case .takeback: takeback()
        case .offerDraw: offerDraw()
        case .acceptDraw: acceptDraw()
        case .declineDraw: pendingDrawOffer = nil
        case .resign: resign()
        case .flipBoard:
            board.isFlipped.toggle()
            refreshPlayers()
        case .rematch: rematch()
        case .dismissBotMessage: botMessage = nil
        }
    }

    // MARK: - Board input

    private func select(_ square: Square) {
        guard canMove else { return }
        switch board.select(square, in: game.position, movableColor: game.position.sideToMove) {
        case .none: break
        case .illegalTarget: feedback.receive(.illegalMove)
        case .move(let move): play(move)
        case .promotion(let moves):
            if settings.value.autoPromoteToQueen, let queen = moves.first(where: { $0.promotion == .queen }) {
                play(queen)
            } else {
                pendingPromotion = moves
            }
        }
    }

    private func choosePromotion(_ type: PieceType) {
        guard let move = pendingPromotion.first(where: { $0.promotion == type }) else { return }
        pendingPromotion = []
        play(move)
    }

    private func cancelSelection() {
        pendingPromotion = []
        board.cancelSelection()
    }

    // MARK: - Actions

    private func requestHint() {
        guard canMove, hintTask == nil else { return }
        let game = self.game
        let limit = SearchLimit.time(tuning.game.hintAnalysisTime)
        isLoadingHint = true
        hintTask = Task { [weak self, engine] in
            let analysis = try? await engine.analyze(
                position: game.position, history: game.moves.map(\.positionBefore), limit: limit
            )
            guard let self, !Task.isCancelled else { return }
            self.hintTask = nil
            self.isLoadingHint = false
            guard self.game == game, let move = analysis?.bestMove else { return }
            self.hint = BoardArrow(from: move.from, to: move.to)
        }
    }

    private func takeback() {
        guard !isGameOver else { return }
        let plies = Self.takebackPlies(plyCount: game.moves.count, sideToMove: game.position.sideToMove, humanColor: humanColor)
        guard plies > 0 else { return }
        botTask?.cancel()
        botTask = nil
        isBotThinking = false
        cancelHint()
        pendingPromotion = []
        pendingDrawOffer = nil
        for _ in 0..<plies { game.undo() }
        board.lastMove = game.moves.last?.move
        board.cancelSelection()
        say(.takeback)
        applyAutoFlip()
        updateClockTurn()
        save()
    }

    private func offerDraw() {
        guard !isGameOver else { return }
        guard let humanColor else {
            pendingDrawOffer = game.position.sideToMove
            return
        }
        guard drawTask == nil else { return }
        let game = self.game
        let policy = tuning.drawOffer
        drawTask = Task { [weak self, engine] in
            let analysis = try? await engine.analyze(
                position: game.position, history: game.moves.map(\.positionBefore), limit: .time(policy.analysisTime)
            )
            guard let self, !Task.isCancelled else { return }
            self.drawTask = nil
            guard !self.isGameOver, let analysis else { return }
            if policy.botAccepts(evaluation: analysis.evaluation, botColor: humanColor.opponent,
                                 plyCount: game.moves.count, position: game.position) {
                self.finish(.draw, .agreement)
            } else {
                self.say(.drawDeclined)
            }
        }
    }

    private func acceptDraw() {
        guard pendingDrawOffer != nil, !isGameOver else { return }
        pendingDrawOffer = nil
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
        id = UUID()
        createdAt = Date()
        result = .ongoing
        termination = nil
        game = ChessGame()
        clock = GameClock(timeControl: timeControl)
        lowTimeWarned = []
        botMessage = nil
        hint = nil
        pendingPromotion = []
        pendingDrawOffer = nil
        board.lastMove = nil
        board.cancelSelection()
        board.isFlipped = initialFlip
        board.resetFocus(for: humanColor ?? .white)
        refreshPlayers()
        hasAnnouncedStart = false
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
        do { try game.makeMove(move) } catch {
            feedback.receive(.illegalMove)
            return
        }
        clock.recordMove(by: mover, plyBeforeMove: plyBefore)
        board.complete(move)
        cancelHint()
        pendingDrawOffer = nil
        if case let (result, termination)? = GameAdjudication.result(for: game.outcome) {
            finish(result, termination)
            return
        }
        feedback.receive(.moved(MoveSound.effect(for: move, before: before, after: game.position)))
        if bot != nil, let event = Self.chatEvent(
            moveByBot: mover != humanColor,
            isCapture: MoveSound.isCapture(move, before: before),
            givesCheck: game.position.isInCheck(game.position.sideToMove)
        ) {
            say(event)
        }
        applyAutoFlip()
        updateClockTurn()
        save()
        scheduleBotMoveIfNeeded()
    }

    private func scheduleBotMoveIfNeeded() {
        guard isActive, !isGameOver, let bot, let humanColor, game.position.sideToMove != humanColor, botTask == nil else { return }
        isBotThinking = true
        let game = self.game
        let tuning = tuning.game
        let delay = Duration.seconds(Self.botThinkDelay(legalMoveCount: game.position.legalMoves().count, tuning: tuning))
        let start = now()
        botTask = Task { [weak self, engine, now, sleep] in
            do {
                if let playerMove = game.moves.last {
                    let history = game.moves.map(\.positionBefore)
                    let limit = SearchLimit.time(tuning.blunderAnalysisTime)
                    let before = try await engine.analyze(
                        position: playerMove.positionBefore, history: Array(history.dropLast()), limit: limit
                    )
                    let after = try await engine.analyze(position: game.position, history: history, limit: limit)
                    if Self.isBlunder(before: before.evaluation, after: after.evaluation, by: humanColor, tuning: tuning) {
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
        self.result = result
        self.termination = termination
        cancelTasks()
        pendingPromotion = []
        pendingDrawOffer = nil
        board.cancelSelection()
        updateClockTurn()
        feedback.receive(.gameOver(result))
        if let humanColor {
            say(result == .draw ? .draw : (result.winner == humanColor ? .botLoses : .botWins))
        }
        save()
    }

    // MARK: - Clock

    private func startClock() {
        clockTask?.cancel()
        clockTask = nil
        lastTick = now()
        updateClockTurn()
        guard clock.isTimed, !isGameOver else { return }
        let interval = tuning.clock.tickInterval
        clockTask = Task { [weak self, sleep] in
            while !Task.isCancelled {
                try? await sleep(interval)
                guard let self, !Task.isCancelled else { return }
                self.tickClock()
            }
        }
    }

    /// Charges the side to move for the time since the last tick; ends the game on a flag.
    private func tickClock() {
        let current = now()
        let elapsed = current - lastTick
        lastTick = current
        guard isActive, !isGameOver, clock.runs(atPly: game.moves.count) else { return }
        let side = game.position.sideToMove
        let flagged = clock.consume(Self.seconds(elapsed), by: side)
        if isLowTime(side), !lowTimeWarned.contains(side) {
            lowTimeWarned.insert(side)
            feedback.receive(.lowTime)
        }
        if flagged {
            let (result, termination) = GameAdjudication.timeout(flagged: side, in: game.position)
            finish(result, termination)
        }
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
        botMessage = line
    }

    private func cancelHint() {
        hintTask?.cancel()
        hintTask = nil
        isLoadingHint = false
        hint = nil
    }

    private func cancelTasks() {
        botTask?.cancel()
        botTask = nil
        drawTask?.cancel()
        drawTask = nil
        clockTask?.cancel()
        clockTask = nil
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
        board.isFlipped = game.position.sideToMove == .black
        board.resetFocus(for: game.position.sideToMove)
        refreshPlayers()
    }

    private func refreshDerived() {
        moveRows = Self.moveRows(game.moves)
        let position = game.position
        capturedPieces = [.white: Material.missing(.black, in: position), .black: Material.missing(.white, in: position)]
        materialAdvantage = Self.materialAdvantage(in: position)
    }

    private func refreshPlayers() {
        let bottom: PieceColor = board.isFlipped ? .black : .white
        bottomPlayer = PlayerSlot(color: bottom, info: player(bottom))
        topPlayer = PlayerSlot(color: bottom.opponent, info: player(bottom.opponent))
    }

    /// Saves after the previous save finished, so the newest snapshot always wins.
    private func save() {
        guard !game.moves.isEmpty else { return }
        let snapshot = SavedGame(
            id: id, createdAt: createdAt, updatedAt: Date(), mode: mode, white: white, black: black,
            timeControl: timeControl, autoFlip: autoFlip, game: game, result: result,
            termination: termination, clock: clock
        )
        let previous = saveTask
        saveTask = Task { [weak self, store] in
            await previous?.value
            try? await store.save(snapshot)
            self?.onSave()
        }
    }

    // MARK: - Pure rules

    /// Human-like minimum think time in seconds: `botThinkBaseSeconds` plus up to
    /// `botThinkExtraSeconds` for positions with `botThinkBusyMoveCount` or more moves.
    nonisolated static func botThinkDelay(legalMoveCount: Int, tuning: GameTuning) -> TimeInterval {
        tuning.botThinkBaseSeconds
            + tuning.botThinkExtraSeconds * min(1, Double(legalMoveCount) / Double(tuning.botThinkBusyMoveCount))
    }

    /// True when the player's move lost `tuning.blunderCentipawns` or more.
    /// Evaluations are from White's point of view.
    nonisolated static func isBlunder(before: Evaluation, after: Evaluation, by player: PieceColor, tuning: GameTuning) -> Bool {
        DrawOfferTuning.score(before, for: player) - DrawOfferTuning.score(after, for: player) >= tuning.blunderCentipawns
    }

    /// Plies to undo so the player is to move again; 0 when a takeback is not possible.
    nonisolated static func takebackPlies(plyCount: Int, sideToMove: PieceColor, humanColor: PieceColor?) -> Int {
        guard let humanColor else { return plyCount > 0 ? 1 : 0 }
        let plies = sideToMove == humanColor ? 2 : 1
        return plyCount >= plies ? plies : 0
    }

    /// Chat event for a move that did not end the game.
    nonisolated static func chatEvent(moveByBot: Bool, isCapture: Bool, givesCheck: Bool) -> BotChatEvent? {
        if moveByBot { return givesCheck ? .check : (isCapture ? .botCaptures : nil) }
        return isCapture ? .playerCaptures : nil
    }

    nonisolated static func moveRows(_ moves: [PlayedMove]) -> [MoveRow] {
        stride(from: 0, to: moves.count, by: 2).map { index in
            MoveRow(number: index / 2 + 1, white: moves[index].san,
                    black: index + 1 < moves.count ? moves[index + 1].san : nil)
        }
    }

    nonisolated static func materialAdvantage(in position: ChessPosition) -> [PieceColor: Int] {
        let difference = Material.points(.white, in: position) - Material.points(.black, in: position)
        return [.white: max(0, difference), .black: max(0, -difference)]
    }

    /// Localisation key of the game-over title; nil while the game is ongoing.
    public nonisolated static func resultTitleKey(_ result: GameResult, humanColor: PieceColor?) -> String? {
        switch result {
        case .ongoing: return nil
        case .draw: return "game.result.draw.title"
        case .whiteWon, .blackWon:
            if let humanColor { return result.winner == humanColor ? "game.result.youWon.title" : "game.result.youLost.title" }
            return result == .whiteWon ? "game.result.whiteWon.title" : "game.result.blackWon.title"
        }
    }

    nonisolated static func resultTitle(_ result: GameResult, humanColor: PieceColor?, localization: Localization) -> String {
        resultTitleKey(result, humanColor: humanColor).map { localization.string($0) } ?? ""
    }

    nonisolated static func turnTextKey(sideToMove: PieceColor, humanColor: PieceColor?) -> String {
        if let humanColor { return sideToMove == humanColor ? "game.turn.yours" : "game.turn.opponent" }
        return sideToMove == .white ? "game.turn.white" : "game.turn.black"
    }

    nonisolated static func turnText(sideToMove: PieceColor, humanColor: PieceColor?, inCheck: Bool, localization: Localization) -> String {
        let base = localization.string(turnTextKey(sideToMove: sideToMove, humanColor: humanColor))
        return inCheck ? localization.string("game.turn.check", base) : base
    }

    private nonisolated static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
