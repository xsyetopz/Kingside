import ChessContent
import ChessCore
import Foundation
import Observation

// One game on an online service, played through an `OnlineGameConnection`.
// - The server is the source of truth. `.started` (sent again on every reconnect) replaces
//   all state; `.state` brings the moves, clocks, draw offers and status.
// - Call `activate()` when the screen appears: it reads `connection.events()`. `deactivate()`
//   stops reading and stops the clock; `activate()` again reconnects with a new stream.
// - `apply(_:)` handles `BoardInput` and `GameAction`, as in `GameSession`. The player's
//   move shows at once and is sent as UCI; it stays pending until a server state has it, and
//   a failed send rolls the board back to the last server state.
// - The local clock only counts down between server states; it never flags. The server ends
//   the game on time.
// - No engine: online play gets no hints or analysis.
// - A finished game is saved once, with `GameMode.online` and an id derived from the
//   service and game id, so a later save of the same game replaces it.

/// Whether the opponent of an online game is connected, and whether the player may claim the win.
enum OpponentPresence: Equatable {
  case present
  /// The opponent left; the claim timer, if the server offers a claim, makes it `claimable`.
  case gone
  /// The opponent left long enough ago that the player may claim the win.
  case claimable
}

@preconcurrency
@Observable
@MainActor
public final class OnlineGameSession {
  /// Everything a `.started` event replaces; `begin` replaces it in one assignment. The server
  /// sends `.started` again on every reconnect.
  private struct PerGameState {
    var game = ChessGame()
    /// Kept across a reconnect to the same game.
    var createdAt = Date()
    var result: GameResult = .ongoing
    var termination: GameTermination?
    var status: OnlineGameStatus = .created
    var pendingDrawOffer: PieceColor?
    var myDrawOfferPending = false
    var chat: [OnlineChatLine] = []
    /// How many lines of `chat` the player has seen.
    var chatReadCount = 0
    var presence = OpponentPresence.present
    var pendingMove: String?
    /// The moves of the latest server state; the board rolls back to them after a failed send.
    var serverMoves: [String] = []
    /// Kept across a reconnect to the same game.
    var saveFailure = SaveFailure.none
  }

  private var perGame = PerGameState() {
    didSet { if perGame.game != oldValue.game { refreshDerived() } }
  }

  public var game: ChessGame { perGame.game }
  public var result: GameResult { perGame.result }
  public var termination: GameTermination? { perGame.termination }
  /// The server's status; `.aborted` ends the game with `result` still `.ongoing`.
  public var status: OnlineGameStatus { perGame.status }
  /// The latest `.started` event; nil until the server sent one.
  public private(set) var start: OnlineGameStart?
  /// The opponent's color while the opponent offers a draw.
  public var pendingDrawOffer: PieceColor? { perGame.pendingDrawOffer }
  /// True while the player's own draw offer waits for an answer.
  public var myDrawOfferPending: Bool { perGame.myDrawOfferPending }
  public var chat: [OnlineChatLine] { perGame.chat }
  /// True after the player muted the opponent's chat; it lasts for this session only.
  public private(set) var isOpponentMuted = false
  var opponentPresence: OpponentPresence { perGame.presence }
  /// True after the server said the opponent left, until it says they are back.
  var opponentGone: Bool { perGame.presence != .present }
  /// True after the event stream ended with an error; `activate()` again reconnects.
  public private(set) var connectionError = false
  /// UCI of the player's move that the server has not confirmed yet.
  var pendingMove: String? { perGame.pendingMove }
  /// True after a save failed; the screen sets it back to false. Raised once per game.
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
  private(set) var capturedPieces: [PieceColor: [PieceType]] = [.white: [], .black: []]
  /// Material lead of each color in points; 0 for the side that is not ahead.
  public private(set) var materialAdvantage: [PieceColor: Int] = [.white: 0, .black: 0]
  public private(set) var topPlayer = PlayerSlot(color: .black, info: PlayerInfo(name: ""))
  public private(set) var bottomPlayer = PlayerSlot(color: .white, info: PlayerInfo(name: ""))
  /// Remaining time of both sides: the server's times, counted down locally for the side to move.
  public var clock: GameClock { clockRunner.clock }
  /// Side whose clock runs while the game is ongoing; nil before the start and once it has ended.
  public private(set) var activeClockColor: PieceColor?

  public let connection: any OnlineGameConnection

  private var input = MoveInput()

  private let chatFilter: ChatFilter
  private let localization: Localization
  private let settings: SettingsStore
  private let store: GamePersistenceStore
  private let feedback: any FeedbackSink
  private let onSave: @MainActor () -> Void
  private let clockRunner: ClockRunner
  private let sleep: @Sendable (Duration) async throws -> Void
  @ObservationIgnored
  private var savedGameID: String?
  @ObservationIgnored
  private(set) var eventTask: Task<Void, Never>?
  @ObservationIgnored
  private var claimTask: Task<Void, Never>?
  @ObservationIgnored
  private lazy var writer = SavedGameWriter(store: store, onSave: onSave) { [weak self] in
    self?.reportSaveFailure(of: $0)
  }

  /// `catalog` supplies the clock tuning and the chat filter. `onSave` runs on the main actor
  /// after each successful save. `clock` drives the local countdown and the claim-victory delay.
  @preconcurrency
  public init(
    connection: any OnlineGameConnection,
    catalog: ContentCatalog,
    localization: Localization,
    settings: SettingsStore,
    store: GamePersistenceStore,
    feedback: any FeedbackSink = NullFeedbackSink(),
    clock: some Clock<Duration> = ContinuousClock(),
    onSave: @escaping @MainActor () -> Void = {}
  ) {
    self.connection = connection
    chatFilter = catalog.chatFilter
    self.localization = localization
    self.settings = settings
    self.store = store
    self.feedback = feedback
    self.onSave = onSave
    clockRunner = ClockRunner(
      GameClock(timeControl: .untimed),
      policy: .showsZero,
      tuning: catalog.tuning.clock,
      feedback: feedback,
      time: clock
    )
    sleep = { try await clock.sleep(for: $0) }
    refreshDerived()
  }

  // MARK: - Derived state

  /// The player's color; nil until the game started.
  public var humanColor: PieceColor? { start?.myColor }
  public var isGameOver: Bool { status.isFinished }
  public var white: PlayerInfo { Self.playerInfo(start?.white, isLocalUser: humanColor == .white) }
  public var black: PlayerInfo { Self.playerInfo(start?.black, isLocalUser: humanColor == .black) }
  /// True when the player may move pieces now: the player's turn in an ongoing game, with no
  /// move waiting for the server.
  public var canMove: Bool {
    !isGameOver && humanColor == game.position.sideToMove && pendingMove == nil
  }
  /// The game can be aborted until both sides moved.
  public var canAbort: Bool { start != nil && !isGameOver && game.moves.count < 2 }
  /// The opponent left long enough ago that the player may claim the win.
  public var canClaimVictory: Bool { perGame.presence == .claimable && !isGameOver }
  /// True when `.cancel` would close the promotion picker or drop a selection.
  public var hasCancellableSelection: Bool { input.hasCancellableSelection }
  public var resultTitle: String {
    GamePresentation.resultTitle(result, humanColor: humanColor, localization: localization)
  }
  public var resultReason: String { termination.map { localization.string($0.reasonKey) } ?? "" }
  public var statusText: String {
    if isGameOver { return localization.string("game.status.over", resultTitle, resultReason) }
    return GamePresentation.turnText(
      sideToMove: game.position.sideToMove,
      humanColor: humanColor,
      inCheck: game.position.isInCheck(game.position.sideToMove),
      localization: localization
    )
  }

  // MARK: - Chat

  /// The opponent's name as the server reports it; nil until the game started.
  public var opponentName: String? {
    start.map { $0.myColor == .white ? $0.black.name : $0.white.name }
  }
  private var myName: String? {
    start.map { $0.myColor == .white ? $0.white.name : $0.black.name }
  }
  /// True when the player turned chat on in the settings.
  public var isChatEnabled: Bool { settings.value.chatEnabled }
  /// The lines the chat panel shows; empty while chat is off.
  public var chatMessages: [OnlineChatMessage] { visibleMessages(of: chat) }
  /// Lines from others that arrived since `markChatRead()`.
  public var unreadChatCount: Int {
    visibleMessages(of: Array(chat.dropFirst(perGame.chatReadCount)))
      .filter { $0.kind != .own }.count
  }

  private func visibleMessages(of lines: [OnlineChatLine]) -> [OnlineChatMessage] {
    OnlineChat.visibleMessages(
      lines,
      myName: myName,
      isEnabled: isChatEnabled,
      opponentMuted: isOpponentMuted,
      filter: chatFilter
    )
  }

  /// Sends `text`, trimmed and cut to `OnlineChat.maxLength`; nothing is sent while chat is off or
  /// the text is blank.
  public func sendChat(_ text: String) {
    let message = String(
      text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(OnlineChat.maxLength)
    )
    guard isChatEnabled, !message.isEmpty else { return }
    send(.chat(message))
  }

  public func setOpponentMuted(_ muted: Bool) { isOpponentMuted = muted }

  public func markChatRead() { perGame.chatReadCount = chat.count }

  public func player(_ color: PieceColor) -> PlayerInfo { color == .white ? white : black }

  /// True when `color`'s clock is at or below the low-time threshold.
  public func isLowTime(_ color: PieceColor) -> Bool { clockRunner.isLow(color) }

  public var snapshot: BoardSnapshot { input.snapshot(of: game.position, canMove: canMove) }

  // MARK: - Lifecycle

  /// Reads a new event stream and starts the clock. Does nothing while a stream is read.
  public func activate() {
    guard eventTask == nil else { return }
    connectionError = false
    let events = connection.events()
    eventTask = Task { [weak self] in
      do {
        for try await event in events {
          guard let self, !Task.isCancelled else { return }
          self.handle(event)
        }
        guard let self, !Task.isCancelled else { return }
        self.eventTask = nil
      } catch {
        guard let self, !Task.isCancelled else { return }
        self.eventTask = nil
        self.connectionError = true
      }
    }
    startClock()
  }

  /// Waits until every save started so far has finished.
  func flushPendingSave() async { await writer.flush() }

  /// Stops reading events, the clock and the claim-victory timer.
  public func deactivate() {
    eventTask?.cancel()
    eventTask = nil
    clockRunner.stop()
    cancelClaimTimer()
  }

  // MARK: - Input and actions

  public func apply(_ boardInput: BoardInput) {
    switch boardInput {
    case .moveFocus(let direction): input.moveFocus(direction)
    case .focus(let square): input.focus(square)
    case .selectFocused: select(input.focusedSquare)
    case .select(let square): select(square)
    case .cancel: input.cancel()
    case .promote(let type): if let move = input.promote(type) { play(move) }
    }
  }

  /// Resign, draws and flip. Hint, takeback, rematch and bot messages do nothing.
  public func apply(_ action: GameAction) {
    switch action {
    case .offerDraw: offerDraw()
    case .acceptDraw: answerDraw(accept: true)
    case .declineDraw: answerDraw(accept: false)
    case .resign:
      guard start != nil, !isGameOver else { return }
      send(.resign)
    case .flipBoard:
      input.isFlipped.toggle()
      refreshPlayers()
    case .requestHint, .takeback, .rematch, .dismissBotMessage: break
    }
  }

  /// Asks the server to abort; see `canAbort`.
  public func abort() {
    guard canAbort else { return }
    send(.abort)
  }

  /// Claims the win after the opponent left; see `canClaimVictory`.
  public func claimVictory() {
    guard canClaimVictory else { return }
    send(.claimVictory)
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

  /// Plays the player's move at once, then sends it; a failed send rolls back to the server state.
  private func play(_ move: ChessMove) {
    guard canMove else { return }
    tickClock()
    let before = game.position
    let plyBefore = game.moves.count
    do { try perGame.game.makeMove(move) } catch {
      feedback.receive(.illegalMove)
      return
    }
    clockRunner.recordMove(by: before.sideToMove, plyBeforeMove: plyBefore)
    input.complete(move)
    let uci = move.uci
    perGame.pendingMove = uci
    updateClockTurn()
    feedback.receive(.moved(MoveSound.effect(for: move, before: before, after: game.position)))
    Task { [weak self, connection] in
      do {
        try await connection.send(.move(uci))
      } catch {
        guard let self, self.pendingMove == uci, self.game.moves.count == plyBefore + 1 else {
          return
        }
        self.perGame.pendingMove = nil
        self.rebuild(self.perGame.serverMoves)
        self.feedback.receive(.illegalMove)
      }
    }
  }

  private func offerDraw() {
    guard start != nil, !isGameOver, !myDrawOfferPending else { return }
    perGame.myDrawOfferPending = true
    Task { [weak self, connection] in
      do { try await connection.send(.offerDraw) } catch {
        self?.perGame.myDrawOfferPending = false
      }
    }
  }

  private func answerDraw(accept: Bool) {
    guard let offer = pendingDrawOffer, !isGameOver else { return }
    perGame.pendingDrawOffer = nil
    Task { [weak self, connection] in
      do { try await connection.send(accept ? .acceptDraw : .declineDraw) } catch {
        guard let self, !self.isGameOver, self.pendingDrawOffer == nil else { return }
        self.perGame.pendingDrawOffer = offer
      }
    }
  }

  /// Sends `action`; the next server state shows its effect.
  private func send(_ action: OnlineAction) {
    Task { [connection] in try? await connection.send(action) }
  }

  // MARK: - Server events

  private func handle(_ event: OnlineGameEvent) {
    switch event {
    case .started(let start): begin(start)
    case .state(let state): sync(state)
    case .chat(let line): perGame.chat.append(line)
    case .opponentGone(let claimWinIn): opponentLeft(claimWinIn: claimWinIn)
    case .opponentBack:
      cancelClaimTimer()
      perGame.presence = .present
    }
  }

  /// Replaces all state with the server's full game.
  private func begin(_ start: OnlineGameStart) {
    let position: ChessPosition
    do { position = try start.initialFEN.map { try ChessPosition(fen: $0) } ?? .initial } catch {
      connectionError = true
      return
    }
    let isNewGame = self.start?.gameID != start.gameID
    // Only a game seen ongoing in this session announces its end.
    let announcesEnd = !isNewGame && !status.isFinished
    self.start = start
    if isNewGame {
      input.isFlipped = initialFlip
      input.resetFocus(for: start.myColor)
      if !start.state.status.isFinished && start.state.uciMoves.isEmpty {
        feedback.receive(.gameStarted)
      }
    }
    cancelClaimTimer()
    perGame = PerGameState(
      game: ChessGame(position: position),
      createdAt: isNewGame ? Date() : perGame.createdAt,
      saveFailure: isNewGame ? .none : perGame.saveFailure
    )
    input.cancel()
    input.lastMove = nil
    clockRunner.reset(to: GameClock(timeControl: start.timeControl ?? .untimed))
    refreshPlayers()
    // Replayed moves get no move feedback.
    rebuild(start.state.uciMoves.map(Self.normalized))
    adopt(start.state, announcesEnd: announcesEnd)
  }

  private func sync(_ state: OnlineGameState) {
    guard start != nil else { return }
    adopt(state, announcesEnd: true)
  }

  /// Brings the board, clocks, draw offers and result to `state`.
  private func adopt(_ state: OnlineGameState, announcesEnd: Bool) {
    guard let start else { return }
    adoptMoves(state.uciMoves.map(Self.normalized))
    adoptClock(state)
    adoptDrawOffers(state, myColor: start.myColor)
    adoptOutcome(state, announcesEnd: announcesEnd)
  }

  private func adoptMoves(_ incoming: [String]) {
    let local = game.moves.map(\.move.uci)
    // A state without the player's pending move keeps that move on the board.
    let awaitsPendingMove = perGame.pendingMove.map { local == incoming + [$0] } ?? false
    if !awaitsPendingMove {
      perGame.pendingMove = nil
      let extended =
        incoming.starts(with: local) && incoming.count > local.count
        && playServerMoves(incoming[local.count...])
      if !extended && incoming != local { rebuild(incoming) }
    }
    perGame.serverMoves = incoming
  }

  /// Keeps the local time of a side the server does not report.
  private func adoptClock(_ state: OnlineGameState) {
    clockRunner.resync(
      to: GameClock(
        timeControl: clock.timeControl,
        whiteRemaining: state.whiteTime.map(GamePresentation.seconds) ?? clock.remaining(.white),
        blackRemaining: state.blackTime.map(GamePresentation.seconds) ?? clock.remaining(.black)
      )
    )
  }

  private func adoptDrawOffers(_ state: OnlineGameState, myColor: PieceColor) {
    let opponent = myColor.opponent
    let opponentOffers = opponent == .white ? state.whiteOffersDraw : state.blackOffersDraw
    let myOffer = myColor == .white ? state.whiteOffersDraw : state.blackOffersDraw
    perGame.pendingDrawOffer = opponentOffers && !state.status.isFinished ? opponent : nil
    perGame.myDrawOfferPending = myOffer && !state.status.isFinished
  }

  /// Sets the result and, once the game is finished, stops play and saves.
  private func adoptOutcome(_ state: OnlineGameState, announcesEnd: Bool) {
    let wasFinished = status.isFinished
    perGame.status = state.status
    (perGame.result, perGame.termination) = Self.outcome(
      status: state.status,
      winner: state.winner,
      position: game.position,
      outcome: game.outcome
    )
    updateClockTurn()
    guard status.isFinished else { return }
    perGame.pendingMove = nil
    input.cancel()
    clockRunner.stop()
    cancelClaimTimer()
    if announcesEnd && !wasFinished { feedback.receive(.gameOver(result)) }
    save()
  }

  /// Plays the new server moves one by one with feedback; false when one is not legal here.
  private func playServerMoves(_ moves: ArraySlice<String>) -> Bool {
    var updated = game
    var last: (ChessMove, ChessPosition)?
    for uci in moves {
      guard let move = Self.legalMove(uci, in: updated.position) else { return false }
      let before = updated.position
      guard (try? updated.makeMove(move)) != nil else { return false }
      last = (move, before)
    }
    perGame.game = updated
    if let (move, before) = last {
      input.complete(move)
      feedback.receive(.moved(MoveSound.effect(for: move, before: before, after: game.position)))
    }
    return true
  }

  /// Replays `moves` from the start position without feedback; stops at the first illegal move.
  private func rebuild(_ moves: [String]) {
    var rebuilt = ChessGame(position: game.initialPosition)
    for uci in moves {
      guard let move = Self.legalMove(uci, in: rebuilt.position),
        (try? rebuilt.makeMove(move)) != nil
      else { break }
    }
    perGame.game = rebuilt
    input.cancel()
    input.lastMove = game.moves.last?.move
    updateClockTurn()
  }

  private func opponentLeft(claimWinIn: Duration?) {
    cancelClaimTimer()
    perGame.presence = .gone
    guard let claimWinIn else { return }
    guard claimWinIn > .zero else {
      perGame.presence = .claimable
      return
    }
    claimTask = Task { [weak self, sleep] in
      try? await sleep(claimWinIn)
      guard let self, !Task.isCancelled else { return }
      self.claimTask = nil
      self.perGame.presence = .claimable
    }
  }

  private func cancelClaimTimer() {
    claimTask?.cancel()
    claimTask = nil
  }

  // MARK: - Clock

  private func startClock() {
    clockRunner.stop()
    updateClockTurn()
    guard !isGameOver else { return }
    clockRunner.start { [weak self] in self?.tickClock() }
  }

  /// Charges the side to move for the time since the last tick; the server decides a flag.
  private func tickClock() {
    let running = start != nil && status == .started
    clockRunner.tick(
      sideToMove: running ? game.position.sideToMove : nil,
      plyCount: game.moves.count
    )
  }

  private func updateClockTurn() {
    let active = start == nil || isGameOver ? nil : game.position.sideToMove
    if activeClockColor != active { activeClockColor = active }
  }

  // MARK: - Helpers

  private var initialFlip: Bool {
    switch settings.value.orientation {
    case .white: false
    case .black: true
    case .automatic: humanColor == .black
    }
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

  /// Saves a finished game once; aborted games (no result) are not saved.
  private func save() {
    guard let start, status.isFinished, result != .ongoing, savedGameID != start.gameID else {
      return
    }
    savedGameID = start.gameID
    writer.save(
      id: storedID(of: start),
      createdAt: perGame.createdAt,
      mode: .online(service: connection.service, gameID: start.gameID),
      white: white,
      black: black,
      timeControl: start.timeControl ?? .untimed,
      autoFlip: false,
      game: game,
      result: result,
      termination: termination,
      clock: clock
    )
  }

  private func storedID(of start: OnlineGameStart) -> UUID {
    Self.savedGameID(service: connection.service, gameID: start.gameID)
  }

  /// Reports once per game; a save that fails after a `.started` for another game is not reported.
  private func reportSaveFailure(of gameID: UUID) {
    guard let start, storedID(of: start) == gameID, perGame.saveFailure == .none else { return }
    perGame.saveFailure = .reported
  }

  // MARK: - Pure rules

  /// Result and termination for a server status. `position` and `outcome` are the final
  /// board, used to tell a draw's reason and to name the winner when the server does not.
  /// Statuses with no matching `GameTermination` (such as `cheat`) have a nil termination.
  nonisolated static func outcome(
    status: OnlineGameStatus,
    winner: PieceColor?,
    position: ChessPosition,
    outcome: GameOutcome
  ) -> (GameResult, GameTermination?) {
    let decided = winner.map(GameResult.win(for:)) ?? .draw
    switch status {
    case .created, .started, .aborted: return (.ongoing, nil)
    case .mate: return (checkmateWinner(outcome).map(GameResult.win(for:)) ?? decided, .checkmate)
    case .resign: return (decided, .resignation)
    case .stalemate: return (.draw, .stalemate)
    case .draw: return (.draw, drawReason(outcome))
    case .outoftime: return timeoutOutcome(winner: winner)
    case .timeout, .cheat, .noStart, .unknownFinish, .variantEnd, .other:
      return (decided, nil)
    }
  }

  nonisolated private static func checkmateWinner(_ outcome: GameOutcome) -> PieceColor? {
    if case .checkmate(let winner) = outcome { return winner }
    return nil
  }

  /// The board's own draw reason; a draw the board does not show was agreed.
  nonisolated private static func drawReason(_ outcome: GameOutcome) -> GameTermination {
    if case (.draw, let reason)? = GameAdjudication.result(for: outcome) { return reason }
    return .agreement
  }

  /// A flag fall with no winner means the side with time left cannot mate.
  nonisolated private static func timeoutOutcome(
    winner: PieceColor?
  ) -> (GameResult, GameTermination?) {
    guard let winner else { return (.draw, .timeoutVsInsufficientMaterial) }
    return (.win(for: winner), .timeout)
  }

  /// Stable id of the saved copy of an online game: the same service and game id always
  /// give the same UUID (FNV-1a over the UTF-8 bytes, as a version 8 UUID).
  nonisolated static func savedGameID(service: String, gameID: String) -> UUID {
    let bytes = Array("\(service)\u{0}\(gameID)".utf8)
    func fnv(_ seed: UInt64) -> UInt64 {
      bytes.reduce(seed) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01b3 }
    }
    let high = fnv(0xcbf2_9ce4_8422_2325), low = fnv(0x6c62_272e_07bb_0142)
    var raw =
      (0..<8).map { UInt8(truncatingIfNeeded: high >> (56 - 8 * $0)) }
      + (0..<8).map { UInt8(truncatingIfNeeded: low >> (56 - 8 * $0)) }
    raw[6] = (raw[6] & 0x0f) | 0x80
    raw[8] = (raw[8] & 0x3f) | 0x80
    return UUID(
      uuid: (
        raw[0], raw[1], raw[2], raw[3], raw[4], raw[5], raw[6], raw[7],
        raw[8], raw[9], raw[10], raw[11], raw[12], raw[13], raw[14], raw[15]
      )
    )
  }

  /// The legal move in `position` that `uci` names, with its promotion piece.
  nonisolated static func legalMove(_ uci: String, in position: ChessPosition) -> ChessMove? {
    guard let move = ChessMove(uci: uci) else { return nil }
    return position.legalMoves().first { $0 == move }
  }

  nonisolated static func normalized(_ uci: String) -> String {
    ChessMove(uci: uci)?.uci ?? uci.lowercased()
  }

  nonisolated static func playerInfo(_ player: OnlinePlayer?, isLocalUser: Bool) -> PlayerInfo {
    PlayerInfo(name: player?.name ?? "", rating: player?.rating, isLocalUser: isLocalUser)
  }
}
