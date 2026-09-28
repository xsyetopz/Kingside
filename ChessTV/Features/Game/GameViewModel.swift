import Foundation
import ChessCore

@MainActor
final class GameViewModel: ObservableObject {
    @Published private(set) var game = ChessGame()
    @Published private(set) var configuration = GameConfiguration()
    @Published private(set) var whiteTime: TimeInterval = 300
    @Published private(set) var blackTime: TimeInterval = 300
    @Published private(set) var isThinking = false
    @Published private(set) var timeWinner: PieceColor?
    @Published var message: String?
    @Published var pendingPromotion: [ChessMove] = []
    @Published var showsGameMenu = false

    let board = BoardInteractionController()
    private let engine: any ChessEngine
    private let settings: SettingsStore
    private let store: GamePersistenceStore
    private var clockTask: Task<Void, Never>?
    private var engineTask: Task<Void, Never>?
    private var savedID = UUID()
    private var isSuspended = false
    private var clockTicksSinceSave = 0

    init(engine: any ChessEngine, settings: SettingsStore, store: GamePersistenceStore) {
        self.engine = engine
        self.settings = settings
        self.store = store
    }

    func start(configuration: GameConfiguration) {
        self.configuration = configuration
        game = ChessGame()
        whiteTime = configuration.initialTime
        blackTime = configuration.initialTime
        savedID = UUID()
        timeWinner = nil
        isSuspended = false
        clockTicksSinceSave = 0
        board.isFlipped = resolvedFlip
        board.resetFocus(for: configuration.humanColor)
        startClock()
        save()
        if configuration.humanColor == .black { requestComputerMove() }
    }

    func restore(_ saved: SavedLocalGame) {
        savedID = saved.id
        game = saved.game
        configuration = GameConfiguration(
            difficulty: saved.difficulty,
            humanColor: saved.humanColor,
            initialTime: saved.initialTime,
            increment: saved.increment
        )
        whiteTime = saved.whiteTime
        blackTime = saved.blackTime
        timeWinner = nil
        isSuspended = false
        clockTicksSinceSave = 0
        board.isFlipped = resolvedFlip
        board.lastMove = game.moves.last?.move
        board.resetFocus(for: configuration.humanColor)
        startClock()
        if game.position.sideToMove != configuration.humanColor { requestComputerMove() }
    }

    var resolvedFlip: Bool {
        switch settings.value.orientation {
        case .white: false
        case .black: true
        case .automatic: configuration.humanColor == .black
        }
    }

    var statusText: String {
        if let timeWinner { return "Time — \(timeWinner.rawValue.capitalized) wins" }
        switch game.position.outcome {
        case .ongoing:
            if isThinking { return "Computer is thinking…" }
            let color = game.position.sideToMove == .white ? "White" : "Black"
            return game.position.isInCheck(game.position.sideToMove) ? "\(color) to move — Check" : "\(color) to move"
        case .checkmate(let winner): return "Checkmate — \(winner.rawValue.capitalized) wins"
        case .stalemate: return "Draw by stalemate"
        case .drawFiftyMove: return "Draw by fifty-move rule"
        }
    }

    func selectSquare() {
        guard !isThinking, !game.position.outcome.isFinished, timeWinner == nil else { return }
        switch board.selectFocused(in: game.position, movableColor: configuration.humanColor) {
        case .none: break
        case .move(let move): makeHumanMove(move)
        case .promotion(let moves): pendingPromotion = moves
        }
    }

    func choosePromotion(_ type: PieceType) {
        guard let move = pendingPromotion.first(where: { $0.promotion == type }) else { return }
        pendingPromotion = []
        makeHumanMove(move)
    }

    func cancelSelection() {
        if !pendingPromotion.isEmpty { pendingPromotion = [] }
        else if board.selectedSquare != nil { board.cancelSelection() }
        else { showsGameMenu = true }
    }

    func undo() {
        let minimumMoves = configuration.humanColor == .black ? 2 : 1
        guard game.moves.count >= minimumMoves else { return }
        engineTask?.cancel()
        isThinking = false
        if game.position.sideToMove == configuration.humanColor {
            _ = game.undo()
        }
        _ = game.undo()
        board.lastMove = game.moves.last?.move
        board.cancelSelection()
        save()
    }

    func restart() { start(configuration: configuration) }

    func flipBoard() {
        board.isFlipped.toggle()
        objectWillChange.send()
    }

    /// Pauses local activity and persists a coherent snapshot before tvOS
    /// backgrounds or terminates the application.
    func suspendAndSave() {
        guard !isSuspended else { return }
        isSuspended = true
        clockTask?.cancel()
        clockTask = nil
        engineTask?.cancel()
        engineTask = nil
        isThinking = false
        save()
    }

    /// Continues a suspended game without charging the player for time spent
    /// outside the app. If the computer was on move, its calculation restarts.
    func resumeAfterInterruption() {
        guard isSuspended, !game.position.outcome.isFinished, timeWinner == nil else { return }
        isSuspended = false
        startClock()
        if game.position.sideToMove != configuration.humanColor {
            requestComputerMove()
        }
    }

    private func makeHumanMove(_ move: ChessMove) {
        do {
            try game.makeMove(move)
            addIncrement(to: configuration.humanColor)
            board.complete(move)
            save()
            if !game.position.outcome.isFinished { requestComputerMove() }
        } catch { message = error.localizedDescription }
    }

    private func requestComputerMove() {
        guard game.position.sideToMove != configuration.humanColor, !game.position.outcome.isFinished, timeWinner == nil else { return }
        isThinking = true
        let position = game.position
        let difficulty = configuration.difficulty
        engineTask = Task { [weak self, engine = self.engine] in
            do {
                let move = try await engine.bestMove(position: position, difficulty: difficulty)
                guard !Task.isCancelled, let self, self.game.position == position else { return }
                try self.game.makeMove(move)
                self.addIncrement(to: position.sideToMove)
                self.board.complete(move)
                self.isThinking = false
                self.save()
            } catch is CancellationError {
                self?.isThinking = false
            } catch {
                self?.message = "The computer could not complete its move."
                self?.isThinking = false
            }
        }
    }

    private func startClock() {
        clockTask?.cancel()
        guard configuration.initialTime > 0 else { return }
        clockTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard let self, !self.game.position.outcome.isFinished, self.timeWinner == nil else { return }
                if self.game.position.sideToMove == .white { self.whiteTime = max(0, self.whiteTime - 1) }
                else { self.blackTime = max(0, self.blackTime - 1) }
                self.clockTicksSinceSave += 1
                if self.clockTicksSinceSave >= 5 {
                    self.clockTicksSinceSave = 0
                    self.save()
                }
                if self.whiteTime == 0 {
                    self.timeWinner = .black
                    self.engineTask?.cancel()
                    self.isThinking = false
                    self.save()
                    return
                }
                if self.blackTime == 0 {
                    self.timeWinner = .white
                    self.engineTask?.cancel()
                    self.isThinking = false
                    self.save()
                    return
                }
            }
        }
    }

    private func addIncrement(to color: PieceColor) {
        if color == .white { whiteTime += configuration.increment }
        else { blackTime += configuration.increment }
    }

    private func save() {
        let saved = SavedLocalGame(
            id: savedID,
            game: game,
            humanColor: configuration.humanColor,
            difficulty: configuration.difficulty,
            whiteTime: whiteTime,
            blackTime: blackTime,
            initialTime: configuration.initialTime,
            increment: configuration.increment,
            updatedAt: Date(),
            isFinished: game.position.outcome.isFinished || timeWinner != nil
        )
        Task { try? await store.save(saved) }
    }
}
