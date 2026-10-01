import ChessContent
import ChessCore
import Foundation
import Observation

// One game on an online service, played through an `OnlineGameConnection`.
// - The server is the source of truth. `.started` (sent again on every reconnect) replaces
//   all state; `.state` brings the moves, clocks, draw offers and status.
// - Call `activate()` when the screen appears: it reads `connection.events()`. `deactivate()`
//   stops reading and stops the clock; `activate()` again reconnects with a new stream.
// - `apply(_:)` handles board input and the game intents, as in `GameSession`. The player's
//   move shows at once and is sent as UCI; it stays pending until a server state has it, and
//   a failed send rolls the board back to the last server state.
// - The local clock only counts down between server states; it never flags. The server ends
//   the game on time.
// - No engine: online play gets no hints or analysis.
// - A finished game is saved once, with `GameMode.online` and an id derived from the
//   service and game id, so a later save of the same game replaces it.

@preconcurrency
@Observable
@MainActor
public final class OnlineGameSession {
  public private(set) var game = ChessGame() { didSet { refreshDerived() } }
  public private(set) var result: GameResult = .ongoing
  public private(set) var termination: GameTermination?
  /// The server's status; `.aborted` ends the game with `result` still `.ongoing`.
  public private(set) var status: OnlineGameStatus = .created
  /// The latest `.started` event; nil until the server sent one.
  public private(set) var start: OnlineGameStart?
  /// The opponent's color while the opponent offers a draw.
  public private(set) var pendingDrawOffer: PieceColor?
  /// True while the player's own draw offer waits for an answer.
  public private(set) var myDrawOfferPending = false
  public private(set) var chat: [OnlineChatLine] = []
  /// True after the player muted the opponent's chat; it lasts for this session only.
  public private(set) var isOpponentMuted = false
  /// How many lines of `chat` the player has seen.
  @ObservationIgnored
  private var chatReadCount = 0
  /// True after the server said the opponent left, until it says they are back.
  public private(set) var opponentGone = false
  /// True after the event stream ended with an error; `activate()` again reconnects.
  public private(set) var connectionError = false
  /// UCI of the player's move that the server has not confirmed yet.
  public private(set) var pendingMove: String?
  /// True after a save failed; the screen sets it back to false. Raised once per session.
  public var showsSaveFailure = false
  public private(set) var moveRows: [MoveRow] = []
  /// Opponent pieces captured by each color.
  public private(set) var capturedPieces: [PieceColor: [PieceType]] = [.white: [], .black: []]
  /// Material lead of each color in points; 0 for the side that is not ahead.
  public private(set) var materialAdvantage: [PieceColor: Int] = [.white: 0, .black: 0]
  public private(set) var topPlayer = PlayerSlot(color: .black, info: PlayerInfo(name: ""))
  public private(set) var bottomPlayer = PlayerSlot(color: .white, info: PlayerInfo(name: ""))
  /// Remaining time of both sides: the server's times, counted down locally for the side to move.
  public private(set) var clock = GameClock(timeControl: .untimed)
  /// Side whose clock runs while the game is ongoing; nil before the start and once it has ended.
  public private(set) var activeClockColor: PieceColor?
  private var claimVictoryReady = false

  public let connection: any OnlineGameConnection

  private var board = BoardInteraction()
  /// Promotion moves waiting for `.promote`; empty when no picker is shown.
  private var pendingPromotion: [ChessMove] = []

  private let tuning: PlayTuning
  private let chatFilter: ChatFilter
  private let localization: Localization
  private let settings: SettingsStore
  private let store: GamePersistenceStore
  private let feedback: any FeedbackSink
  private let onSave: @MainActor () -> Void
  /// Time since the session was created, on the injected clock.
  private let now: @Sendable () -> Duration
  private let sleep: @Sendable (Duration) async throws -> Void
  /// The moves of the latest server state; the board rolls back to them after a failed send.
  @ObservationIgnored
  private var serverMoves: [String] = []
  @ObservationIgnored
  private var createdAt = Date()
  @ObservationIgnored
  private var lowTimeWarned: Set<PieceColor> = []
  @ObservationIgnored
  private var lastTick: Duration = .zero
  @ObservationIgnored
  private var savedGameID: String?
  @ObservationIgnored
  private(set) var eventTask: Task<Void, Never>?
  @ObservationIgnored
  private var clockTask: Task<Void, Never>?
  @ObservationIgnored
  private var claimTask: Task<Void, Never>?
  /// The latest save; each save waits for the previous one.
  @ObservationIgnored
  private var saveTask: Task<Void, Never>?
  @ObservationIgnored
  private var hasReportedSaveFailure = false

  /// `catalog` supplies `tuning`. `onSave` runs on the main actor after each successful save.
  /// `clock` drives the local countdown and the claim-victory delay.
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
    tuning = catalog.tuning
    chatFilter = catalog.chatFilter
    self.localization = localization
    self.settings = settings
    self.store = store
    self.feedback = feedback
    self.onSave = onSave
    let origin = clock.now
    now = { origin.duration(to: clock.now) }
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
  public var canClaimVictory: Bool { claimVictoryReady && opponentGone && !isGameOver }
  /// True when `.cancel` would close the promotion picker or drop a selection.
  public var hasCancellableSelection: Bool {
    !pendingPromotion.isEmpty || board.selectedSquare != nil
  }
  public var resultTitle: String {
    GameSession.resultTitle(result, humanColor: humanColor, localization: localization)
  }
  public var resultReason: String { termination.map { localization.string($0.reasonKey) } ?? "" }
  public var statusText: String {
    if isGameOver { return localization.string("game.status.over", resultTitle, resultReason) }
    return GameSession.turnText(
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
    visibleMessages(of: Array(chat.dropFirst(chatReadCount))).filter { $0.kind != .own }.count
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

  public func markChatRead() { chatReadCount = chat.count }

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
      hint: nil,
      pendingPromotion: pendingPromotion.first.map { move in
        PendingPromotion(
          from: move.from,
          to: move.to,
          color: side,
          choices: pendingPromotion.compactMap(\.promotion)
        )
      },
      isInputEnabled: canMove && pendingPromotion.isEmpty
    )
  }

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
  func flushPendingSave() async { await saveTask?.value }

  /// Stops reading events, the clock and the claim-victory timer.
  public func deactivate() {
    eventTask?.cancel()
    eventTask = nil
    clockTask?.cancel()
    clockTask = nil
    claimTask?.cancel()
    claimTask = nil
  }

  // MARK: - Intents

  /// Board input, resign, draws and flip. Hint, takeback, rematch and bot messages do nothing.
  public func apply(_ intent: BoardIntent) {
    switch intent {
    case .moveFocus(let direction): board.moveFocus(direction)
    case .focus(let square): board.focusedSquare = square
    case .selectFocused: select(board.focusedSquare)
    case .select(let square): select(square)
    case .cancel: cancelSelection()
    case .promote(let type): choosePromotion(type)
    case .offerDraw: offerDraw()
    case .acceptDraw: answerDraw(accept: true)
    case .declineDraw: answerDraw(accept: false)
    case .resign:
      guard start != nil, !isGameOver else { return }
      send(.resign)
    case .flipBoard:
      board.isFlipped.toggle()
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
    switch board.select(square, in: game.position, movableColor: game.position.sideToMove) {
    case .none: break
    case .illegalTarget: feedback.receive(.illegalMove)
    case .move(let move): play(move)
    case .promotion(let moves):
      if settings.value.autoPromoteToQueen,
        let queen = moves.first(where: { $0.promotion == .queen })
      {
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

  /// Plays the player's move at once, then sends it; a failed send rolls back to the server state.
  private func play(_ move: ChessMove) {
    guard canMove else { return }
    tickClock()
    let before = game.position
    let plyBefore = game.moves.count
    do { try game.makeMove(move) } catch {
      feedback.receive(.illegalMove)
      return
    }
    clock.recordMove(by: before.sideToMove, plyBeforeMove: plyBefore)
    board.complete(move)
    let uci = move.uci
    pendingMove = uci
    updateClockTurn()
    feedback.receive(.moved(MoveSound.effect(for: move, before: before, after: game.position)))
    Task { [weak self, connection] in
      do {
        try await connection.send(.move(uci))
      } catch {
        guard let self, self.pendingMove == uci, self.game.moves.count == plyBefore + 1 else {
          return
        }
        self.pendingMove = nil
        self.rebuild(self.serverMoves)
        self.feedback.receive(.illegalMove)
      }
    }
  }

  private func offerDraw() {
    guard start != nil, !isGameOver, !myDrawOfferPending else { return }
    myDrawOfferPending = true
    Task { [weak self, connection] in
      do { try await connection.send(.offerDraw) } catch { self?.myDrawOfferPending = false }
    }
  }

  private func answerDraw(accept: Bool) {
    guard let offer = pendingDrawOffer, !isGameOver else { return }
    pendingDrawOffer = nil
    Task { [weak self, connection] in
      do { try await connection.send(accept ? .acceptDraw : .declineDraw) } catch {
        guard let self, !self.isGameOver, self.pendingDrawOffer == nil else { return }
        self.pendingDrawOffer = offer
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
    case .chat(let line): chat.append(line)
    case .opponentGone(let claimWinIn): opponentLeft(claimWinIn: claimWinIn)
    case .opponentBack:
      opponentGone = false
      claimVictoryReady = false
      claimTask?.cancel()
      claimTask = nil
    }
  }

  /// Replaces all state with the server's full game.
  private func begin(_ start: OnlineGameStart) {
    let position: ChessPosition
    do { position = try start.initialFEN.map(ChessPosition.init(fen:)) ?? .initial } catch {
      connectionError = true
      return
    }
    let isNewGame = self.start?.gameID != start.gameID
    // Only a game seen ongoing in this session announces its end.
    let announcesEnd = !isNewGame && !status.isFinished
    self.start = start
    if isNewGame {
      createdAt = Date()
      board.isFlipped = initialFlip
      board.resetFocus(for: start.myColor)
      if !start.state.status.isFinished && start.state.uciMoves.isEmpty {
        feedback.receive(.gameStarted)
      }
    }
    game = ChessGame(position: position)
    serverMoves = []
    pendingMove = nil
    pendingPromotion = []
    board.cancelSelection()
    board.lastMove = nil
    chat = []
    chatReadCount = 0
    opponentGone = false
    claimVictoryReady = false
    claimTask?.cancel()
    claimTask = nil
    myDrawOfferPending = false
    pendingDrawOffer = nil
    lowTimeWarned = []
    clock = GameClock(timeControl: start.timeControl ?? .untimed)
    status = .created
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
    let incoming = state.uciMoves.map(Self.normalized)
    let local = game.moves.map(\.move.uci)
    // A state without the player's pending move keeps that move on the board.
    let awaitsPendingMove = pendingMove.map { local == incoming + [$0] } ?? false
    if !awaitsPendingMove {
      pendingMove = nil
      let extended =
        incoming.starts(with: local) && incoming.count > local.count
        && playServerMoves(incoming[local.count...])
      if !extended && incoming != local { rebuild(incoming) }
    }
    serverMoves = incoming

    clock = GameClock(
      timeControl: clock.timeControl,
      whiteRemaining: state.whiteTime.map(GameSession.seconds) ?? clock.remaining(.white),
      blackRemaining: state.blackTime.map(GameSession.seconds) ?? clock.remaining(.black)
    )
    lastTick = now()

    let opponent = start.myColor.opponent
    let opponentOffers = opponent == .white ? state.whiteOffersDraw : state.blackOffersDraw
    let myOffer = start.myColor == .white ? state.whiteOffersDraw : state.blackOffersDraw
    pendingDrawOffer = opponentOffers && !state.status.isFinished ? opponent : nil
    myDrawOfferPending = myOffer && !state.status.isFinished

    let wasFinished = status.isFinished
    status = state.status
    (result, termination) = Self.outcome(
      status: state.status,
      winner: state.winner,
      position: game.position,
      outcome: game.outcome
    )
    updateClockTurn()
    guard status.isFinished else { return }
    pendingPromotion = []
    pendingMove = nil
    board.cancelSelection()
    clockTask?.cancel()
    clockTask = nil
    claimTask?.cancel()
    claimTask = nil
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
    game = updated
    if let (move, before) = last {
      board.complete(move)
      pendingPromotion = []
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
    game = rebuilt
    pendingPromotion = []
    board.cancelSelection()
    board.lastMove = game.moves.last?.move
    updateClockTurn()
  }

  private func opponentLeft(claimWinIn: Duration?) {
    opponentGone = true
    claimVictoryReady = false
    claimTask?.cancel()
    claimTask = nil
    guard let claimWinIn else { return }
    guard claimWinIn > .zero else {
      claimVictoryReady = true
      return
    }
    claimTask = Task { [weak self, sleep] in
      try? await sleep(claimWinIn)
      guard let self, !Task.isCancelled else { return }
      self.claimTask = nil
      self.claimVictoryReady = true
    }
  }

  // MARK: - Clock

  private func startClock() {
    clockTask?.cancel()
    clockTask = nil
    lastTick = now()
    updateClockTurn()
    guard !isGameOver else { return }
    let interval = tuning.clock.tickInterval
    clockTask = Task { [weak self, sleep] in
      while !Task.isCancelled {
        try? await sleep(interval)
        guard let self, !Task.isCancelled else { return }
        self.tickClock()
      }
    }
  }

  /// Charges the side to move for the time since the last tick; never flags.
  private func tickClock() {
    let current = now()
    let elapsed = current - lastTick
    lastTick = current
    guard start != nil, status == .started, clock.runs(atPly: game.moves.count) else { return }
    let side = game.position.sideToMove
    clock.consume(GameSession.seconds(elapsed), by: side)
    if isLowTime(side), !lowTimeWarned.contains(side) {
      lowTimeWarned.insert(side)
      feedback.receive(.lowTime)
    }
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
    moveRows = GameSession.moveRows(game.moves)
    let position = game.position
    capturedPieces = [
      .white: Material.missing(.black, in: position),
      .black: Material.missing(.white, in: position),
    ]
    materialAdvantage = GameSession.materialAdvantage(in: position)
  }

  private func refreshPlayers() {
    let bottom: PieceColor = board.isFlipped ? .black : .white
    bottomPlayer = PlayerSlot(color: bottom, info: player(bottom))
    topPlayer = PlayerSlot(color: bottom.opponent, info: player(bottom.opponent))
  }

  /// Saves a finished game once; aborted games (no result) are not saved.
  private func save() {
    guard let start, status.isFinished, result != .ongoing, savedGameID != start.gameID else {
      return
    }
    savedGameID = start.gameID
    let snapshot = SavedGame(
      id: Self.savedGameID(service: connection.service, gameID: start.gameID),
      createdAt: createdAt,
      updatedAt: Date(),
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
    let previous = saveTask
    saveTask = Task { [weak self, store] in
      await previous?.value
      do {
        try await store.save(snapshot)
        self?.onSave()
      } catch {
        self?.reportSaveFailure()
      }
    }
  }

  private func reportSaveFailure() {
    guard !hasReportedSaveFailure else { return }
    hasReportedSaveFailure = true
    showsSaveFailure = true
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
    case .mate:
      if case .checkmate(let winner) = outcome { return (.win(for: winner), .checkmate) }
      return (decided, .checkmate)
    case .resign: return (decided, .resignation)
    case .stalemate: return (.draw, .stalemate)
    case .draw:
      if case (.draw, let reason)? = GameAdjudication.result(for: outcome) {
        return (.draw, reason)
      }
      return (.draw, .agreement)
    case .outoftime:
      guard let winner else { return (.draw, .timeoutVsInsufficientMaterial) }
      return (.win(for: winner), .timeout)
    case .timeout, .cheat, .noStart, .unknownFinish, .variantEnd, .other:
      return (decided, nil)
    }
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
