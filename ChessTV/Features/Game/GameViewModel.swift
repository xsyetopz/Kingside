import Foundation
import ChessCore

// Game screen state for bot games and pass-and-play.
// - Create with a `GameLaunch`; call `activate()` when the screen appears or the app becomes
//   active, and `deactivate()` when it disappears or goes to the background (stops the bot,
//   the hint and the clock, then saves).
// - Board input: `select()` / `cancelSelection()` / `choosePromotion(_:)` drive `board`.
// - Actions: `requestHint()`, `takeback()`, `offerDraw()` (+ `acceptDraw()` / `declineDraw()`
//   for pass-and-play), `resign()`, `flipBoard()`, `rematch()`.
// - The clock lives in `clock` (`GameClockModel`) so its 10 Hz tick redraws only clock views.
// - Pure rules are static functions at the bottom, covered by unit tests.

/// Remaining time shown by clock views. Updated about ten times a second while a clock runs.
@MainActor
final class GameClockModel: ObservableObject {
    @Published fileprivate(set) var clock: GameClock
    /// Side to move while the game is ongoing; nil once it has ended.
    @Published fileprivate(set) var activeColor: PieceColor?

    init(clock: GameClock) {
        self.clock = clock
    }

    var isTimed: Bool { clock.isTimed }
    func remaining(_ color: PieceColor) -> TimeInterval { clock.remaining(color) }
    func isLow(_ color: PieceColor) -> Bool { clock.isLow(color) }
}

/// One line of the move list: "12. Nf3 Nc6".
struct MoveRow: Identifiable, Equatable {
    let number: Int
    let white: String
    let black: String?
    var id: Int { number }
}

/// A player bar: which color it shows and who plays it.
struct PlayerSlot: Equatable {
    let color: PieceColor
    let info: PlayerInfo
}

@MainActor
final class GameViewModel: ObservableObject {
    /// Minimum drop, in centipawns from the player's side, reported as a blunder.
    nonisolated static let blunderThreshold = 250

    @Published private(set) var game = ChessGame() { didSet { refreshDerived() } }
    @Published private(set) var result: GameResult = .ongoing
    @Published private(set) var termination: GameTermination?
    @Published private(set) var isBotThinking = false
    /// Latest chat line of the bot; nil when there is nothing to show.
    @Published private(set) var botMessage: String?
    /// Suggested move from `requestHint()`; cleared by the next move.
    @Published private(set) var hintArrow: BoardArrow?
    @Published private(set) var isLoadingHint = false
    /// Promotion choices waiting for `choosePromotion(_:)`; empty when no picker is shown.
    @Published private(set) var pendingPromotion: [ChessMove] = []
    /// Pass-and-play: the color that offered a draw, waiting for the other side to answer.
    @Published private(set) var pendingDrawOffer: PieceColor?
    @Published private(set) var moveRows: [MoveRow] = []
    /// Opponent pieces captured by each color.
    @Published private(set) var capturedPieces: [PieceColor: [PieceType]] = [.white: [], .black: []]
    /// Material lead of each color in points; 0 for the side that is not ahead.
    @Published private(set) var materialAdvantage: [PieceColor: Int] = [.white: 0, .black: 0]
    @Published private(set) var topPlayer: PlayerSlot
    @Published private(set) var bottomPlayer: PlayerSlot

    let board = BoardInteractionController()
    let clock: GameClockModel

    private(set) var id: UUID
    private(set) var mode: GameMode
    private(set) var white: PlayerInfo
    private(set) var black: PlayerInfo
    let timeControl: TimeControl
    let autoFlip: Bool

    private let engine: ChessEngine
    private let settings: SettingsStore
    private let store: GamePersistenceStore
    private let onSave: () -> Void
    private var createdAt: Date
    private var isActive = false
    private var hasAnnouncedStart: Bool
    private var lowTimeWarned: Set<PieceColor> = []
    private var lastTick = ContinuousClock.now
    private var botTask: Task<Void, Never>?
    private var hintTask: Task<Void, Never>?
    private var drawTask: Task<Void, Never>?
    private var clockTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?

    /// `onSave` runs on the main actor after each completed save.
    init(
        launch: GameLaunch,
        engine: ChessEngine,
        settings: SettingsStore,
        store: GamePersistenceStore,
        onSave: @escaping () -> Void = {}
    ) {
        self.engine = engine
        self.settings = settings
        self.store = store
        self.onSave = onSave
        switch launch {
        case .new(let setup):
            id = UUID()
            createdAt = Date()
            mode = setup.mode
            white = setup.white
            black = setup.black
            timeControl = setup.timeControl
            autoFlip = setup.autoFlip
            clock = GameClockModel(clock: GameClock(timeControl: setup.timeControl))
            hasAnnouncedStart = false
        case .saved(let saved):
            id = saved.id
            createdAt = saved.createdAt
            mode = saved.mode
            white = saved.white
            black = saved.black
            timeControl = saved.timeControl
            autoFlip = saved.autoFlip
            clock = GameClockModel(clock: saved.clock)
            game = saved.game
            result = saved.result
            termination = saved.termination
            hasAnnouncedStart = true
        }
        topPlayer = PlayerSlot(color: .black, info: black)
        bottomPlayer = PlayerSlot(color: .white, info: white)
        board.lastMove = game.moves.last?.move
        board.isFlipped = initialFlip
        board.resetFocus(for: humanColor ?? game.position.sideToMove)
        refreshDerived()
    }

    // MARK: - Derived state

    var bot: Bot? { mode.botID.flatMap(BotRoster.bot(id:)) }
    /// The human's color in a bot game; nil in pass-and-play.
    var humanColor: PieceColor? { mode.botID == nil ? nil : (white.isBot ? .black : .white) }
    var isPassAndPlay: Bool { mode == .passAndPlay }
    var isGameOver: Bool { result != .ongoing }
    /// True when the remote may move pieces now.
    var canMove: Bool {
        !isGameOver && !isBotThinking && pendingDrawOffer == nil
            && (humanColor == nil || game.position.sideToMove == humanColor)
    }
    var canTakeback: Bool {
        !isGameOver && Self.takebackPlies(plyCount: game.moves.count, sideToMove: game.position.sideToMove, humanColor: humanColor) > 0
    }
    var resultTitle: String { Self.resultTitle(result, humanColor: humanColor) }
    var resultReason: String { termination?.reasonText ?? "" }
    var statusText: String {
        if isGameOver { return "\(resultTitle) \(resultReason)" }
        if isBotThinking, let bot { return "\(bot.name) is thinking…" }
        return Self.turnText(sideToMove: game.position.sideToMove, humanColor: humanColor,
                             inCheck: game.position.isInCheck(game.position.sideToMove))
    }

    func player(_ color: PieceColor) -> PlayerInfo { color == .white ? white : black }

    // MARK: - Lifecycle

    /// Starts the clock and the bot. Plays the start sound and greeting once for a new game.
    func activate() {
        guard !isActive else { return }
        isActive = true
        if !hasAnnouncedStart {
            hasAnnouncedStart = true
            SoundEffects.shared.play(.gameStart)
            say(.greeting)
        }
        startClock()
        scheduleBotMoveIfNeeded()
    }

    /// Stops the bot, hint, draw decision and clock, then saves.
    func deactivate() {
        guard isActive else { return }
        tickClock()
        isActive = false
        cancelTasks()
        save()
    }

    // MARK: - Board input

    func select() {
        guard canMove else { return }
        switch board.selectFocused(in: game.position, movableColor: game.position.sideToMove) {
        case .none: break
        case .move(let move): play(move)
        case .promotion(let moves):
            if settings.value.autoPromoteToQueen, let queen = moves.first(where: { $0.promotion == .queen }) {
                play(queen)
            } else {
                pendingPromotion = moves
            }
        }
    }

    func choosePromotion(_ type: PieceType) {
        guard let move = pendingPromotion.first(where: { $0.promotion == type }) else { return }
        pendingPromotion = []
        play(move)
    }

    /// Closes the promotion picker or drops the selection. Returns false when there was
    /// nothing to cancel, so the view can open its menu instead.
    @discardableResult
    func cancelSelection() -> Bool {
        if !pendingPromotion.isEmpty {
            pendingPromotion = []
            board.cancelSelection()
            return true
        }
        if board.selectedSquare != nil {
            board.cancelSelection()
            return true
        }
        return false
    }

    // MARK: - Actions

    func requestHint() {
        guard canMove, hintTask == nil else { return }
        let game = self.game
        isLoadingHint = true
        hintTask = Task { [weak self, engine] in
            let analysis = try? await engine.analyze(
                position: game.position, history: game.moves.map(\.positionBefore), limit: .time(.seconds(1))
            )
            guard let self, !Task.isCancelled else { return }
            self.hintTask = nil
            self.isLoadingHint = false
            guard self.game == game, let move = analysis?.bestMove else { return }
            self.hintArrow = BoardArrow(from: move.from, to: move.to)
        }
    }

    /// Bot games: back to the player's previous turn (1 or 2 plies). Pass-and-play: 1 ply.
    func takeback() {
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

    /// Bot games: the bot answers through `DrawOfferPolicy`. Pass-and-play: waits for the
    /// other side to call `acceptDraw()` or `declineDraw()`.
    func offerDraw() {
        guard !isGameOver else { return }
        guard let humanColor else {
            pendingDrawOffer = game.position.sideToMove
            return
        }
        guard drawTask == nil else { return }
        let game = self.game
        drawTask = Task { [weak self, engine] in
            let analysis = try? await engine.analyze(
                position: game.position, history: game.moves.map(\.positionBefore), limit: .time(.milliseconds(300))
            )
            guard let self, !Task.isCancelled else { return }
            self.drawTask = nil
            guard !self.isGameOver, let analysis else { return }
            if DrawOfferPolicy.botAccepts(evaluation: analysis.evaluation, botColor: humanColor.opponent,
                                          plyCount: game.moves.count, position: game.position) {
                self.finish(.draw, .agreement)
            } else {
                self.say(.drawDeclined)
            }
        }
    }

    func acceptDraw() {
        guard pendingDrawOffer != nil, !isGameOver else { return }
        pendingDrawOffer = nil
        tickClock()
        guard !isGameOver else { return }
        finish(.draw, .agreement)
    }

    func declineDraw() {
        pendingDrawOffer = nil
    }

    /// The human resigns in a bot game; the side to move resigns in pass-and-play.
    func resign() {
        guard !isGameOver else { return }
        tickClock()
        guard !isGameOver else { return }
        let loser = humanColor ?? game.position.sideToMove
        finish(.win(for: loser.opponent), .resignation)
    }

    func flipBoard() {
        board.isFlipped.toggle()
        refreshPlayers()
    }

    /// New game with the same players and colors swapped.
    func rematch() {
        cancelTasks()
        swap(&white, &black)
        id = UUID()
        createdAt = Date()
        result = .ongoing
        termination = nil
        game = ChessGame()
        clock.clock = GameClock(timeControl: timeControl)
        lowTimeWarned = []
        botMessage = nil
        hintArrow = nil
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

    func dismissBotMessage() { botMessage = nil }

    // MARK: - Moves

    private func play(_ move: ChessMove) {
        tickClock()
        let before = game.position
        let plyBefore = game.moves.count
        let mover = before.sideToMove
        do { try game.makeMove(move) } catch {
            SoundEffects.shared.play(.illegal)
            return
        }
        clock.clock.recordMove(by: mover, plyBeforeMove: plyBefore)
        board.complete(move)
        cancelHint()
        pendingDrawOffer = nil
        if case let (result, termination)? = GameAdjudication.result(for: game.outcome) {
            finish(result, termination)
            return
        }
        SoundEffects.shared.play(MoveSound.effect(for: move, before: before, after: game.position))
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
        let delay = Self.botThinkDelay(legalMoveCount: game.position.legalMoves().count)
        botTask = Task { [weak self, engine] in
            let start = ContinuousClock.now
            do {
                if let playerMove = game.moves.last {
                    let history = game.moves.map(\.positionBefore)
                    let before = try await engine.analyze(
                        position: playerMove.positionBefore, history: Array(history.dropLast()), limit: .time(.milliseconds(200))
                    )
                    let after = try await engine.analyze(position: game.position, history: history, limit: .time(.milliseconds(200)))
                    if Self.isBlunder(before: before.evaluation, after: after.evaluation, by: humanColor) {
                        self?.say(.playerBlunder)
                    }
                }
                let move = try await engine.bestMove(game: game, strength: bot.strength)
                let remaining = Duration.seconds(delay) - (ContinuousClock.now - start)
                if remaining > .zero { try await Task.sleep(for: remaining) }
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
        SoundEffects.shared.play(.gameEnd)
        if let humanColor {
            say(result == .draw ? .draw : (result.winner == humanColor ? .botLoses : .botWins))
        }
        save()
    }

    // MARK: - Clock

    private func startClock() {
        clockTask?.cancel()
        clockTask = nil
        lastTick = .now
        updateClockTurn()
        guard clock.isTimed, !isGameOver else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, !Task.isCancelled else { return }
                self.tickClock()
            }
        }
    }

    /// Charges the side to move for the time since the last tick; ends the game on a flag.
    private func tickClock() {
        let now = ContinuousClock.now
        let elapsed = now - lastTick
        lastTick = now
        guard isActive, !isGameOver, clock.clock.runs(atPly: game.moves.count) else { return }
        let side = game.position.sideToMove
        let flagged = clock.clock.consume(Self.seconds(elapsed), by: side)
        if clock.clock.isLow(side), !lowTimeWarned.contains(side) {
            lowTimeWarned.insert(side)
            SoundEffects.shared.play(.lowTime)
        }
        if flagged {
            let (result, termination) = GameAdjudication.timeout(flagged: side, in: game.position)
            finish(result, termination)
        }
    }

    private func updateClockTurn() {
        let active = isGameOver ? nil : game.position.sideToMove
        if clock.activeColor != active { clock.activeColor = active }
    }

    // MARK: - Helpers

    private func say(_ event: BotChatEvent) {
        guard let line = bot?.line(for: event), !line.isEmpty else { return }
        botMessage = line
    }

    private func cancelHint() {
        hintTask?.cancel()
        hintTask = nil
        isLoadingHint = false
        hintArrow = nil
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
            termination: termination, clock: clock.clock
        )
        let previous = saveTask
        saveTask = Task { [weak self, store] in
            await previous?.value
            try? await store.save(snapshot)
            self?.onSave()
        }
    }

    // MARK: - Pure rules

    /// Human-like minimum think time: 0.4 s plus up to 0.8 s for positions with many moves.
    nonisolated static func botThinkDelay(legalMoveCount: Int) -> TimeInterval {
        0.4 + 0.8 * min(1, Double(legalMoveCount) / 40)
    }

    /// True when the player's move lost `blunderThreshold` centipawns or more.
    /// Evaluations are from White's point of view.
    nonisolated static func isBlunder(before: Evaluation, after: Evaluation, by player: PieceColor) -> Bool {
        DrawOfferPolicy.score(before, for: player) - DrawOfferPolicy.score(after, for: player) >= blunderThreshold
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

    nonisolated static func resultTitle(_ result: GameResult, humanColor: PieceColor?) -> String {
        switch result {
        case .ongoing: return ""
        case .draw: return "Draw"
        case .whiteWon, .blackWon:
            if let humanColor { return result.winner == humanColor ? "You Won!" : "You Lost" }
            return result == .whiteWon ? "White Won" : "Black Won"
        }
    }

    nonisolated static func turnText(sideToMove: PieceColor, humanColor: PieceColor?, inCheck: Bool) -> String {
        let base: String
        if let humanColor {
            base = sideToMove == humanColor ? "Your move" : "Opponent to move"
        } else {
            base = sideToMove == .white ? "White to move" : "Black to move"
        }
        return inCheck ? "\(base) · Check" : base
    }

    private nonisolated static func seconds(_ duration: Duration) -> TimeInterval {
        let parts = duration.components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
