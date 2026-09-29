# ChessTV Architecture

## Dependency direction

```text
SwiftUI Features ──> View models ──> ChessCore
       │                    │             ▲
       │                    ├──> ChessEngine
       │                    ├──> GamePersistenceStore
       │                    └──> PuzzleProgressStore / SettingsStore
       └──> BoardInteractionController
```

`ChessCore` has no dependency on SwiftUI, UIKit, GameController, or persistence. The app has no networking layer. A position is a value; applying a move returns a new value. This makes search, PGN replay, persistence snapshots, and tests deterministic.

## Chess rules

`ChessPosition` owns piece placement, side to move, castling rights, en-passant target, and move counters. Move generation has two stages:

1. Piece-specific pseudo-legal generation, including castling and en passant.
2. Apply each candidate to a copy and remove moves that leave the moving king attacked.

Attack detection is independent of legal-move generation, avoiding recursion and correctly handling pinned pieces and castling transit squares. `ChessGame` layers SAN history and undo on top of positions and reports checkmate, stalemate, fifty-move, threefold-repetition, and insufficient-material outcomes.

## Board input and focus

`ChessBoardView` is one focusable view. `BoardInteractionController` owns exactly the board interaction state:

- `focusedSquare`
- `selectedSquare`
- `legalMoves`

Remote and game-controller input both call the same directional/select/cancel methods. Focus cannot leak into side controls while the user navigates squares because squares are rendered shapes, not separate buttons. Modal overlays establish explicit initial focus; dismissing them reveals the still-focused board.

The board renderer derives square coordinates from orientation and uses stable render identities to animate movement and capture removal. Chess state remains authoritative in `ChessPosition`.

## Local game lifecycle

`AppContainer` (in `ChessTVApp.swift`) owns the `SettingsStore`, the `GamePersistenceStore`, and one shared `ChessEngine`. Play Bots and Play a Friend each build a `GameSetup` (mode, players, `TimeControl`, auto-flip) and navigate to the game screen through `AppRoute.game`; Continue on Home reopens the saved unfinished game.

`GameViewModel` is main-actor isolated because it publishes UI state. It drives a `GameClock`, asks `ChessEngine` for bot moves and hints asynchronously, and handles resign, draw offers, and takeback. Position equality rejects stale engine results after undo/restart, and cancellation stops obsolete searches. Finished games are saved as `SavedGame` values, which the Archive lists and Game Review opens through `AppRoute.review`.

## Computer engine

`ChessEngine` is an actor in `ChessCore` running an alpha-beta search over an internal 0x88 board with a transposition table. Search never runs on the main actor and stops when its task is cancelled.

- `bestMove(game:strength:)` plays for bots. `EngineStrength` maps an Elo value (250 to 2200) to search depth, think time, evaluation noise, and a chance of choosing a weaker candidate move.
- `analyze(position:history:limit:)` returns the best line and evaluation, used for hints and Game Review.

## Puzzles

`Puzzles.json` is bundled and loaded locally. `PuzzleSelector` picks puzzles for rated play, Puzzle Rush, and the Daily Puzzle. `PuzzleRating` computes rating changes, and `PuzzleRushRun` holds the score, strikes, and clock of a Puzzle Rush run (3 Minutes, 5 Minutes, or Survival).

## Game Review

`GameReviewModel` analyzes each position of a saved game with `ChessEngine.analyze` and caches the results for the app session. The pure logic in `ReviewClassification.swift` (win probability, move classification, accuracy) is separate from the UI and unit-tested in `ReviewTests`.

## Persistence

- `SettingsStore`: `AppSettings` (board theme, piece set, orientation, gameplay toggles) as JSON in `UserDefaults`.
- `PuzzleProgressStore`: puzzle rating, streaks, Puzzle Rush bests, seen puzzles, and solved daily puzzles in `UserDefaults`.
- `GamePersistenceStore`: an actor that writes `saved-games-v2.json` in Application Support atomically. It keeps at most one unfinished game and the newest 200 finished games.

## Testing strategy

- `ChessCoreTests`: legal movement, captures, check/mate/stalemate, castling, en passant, promotion, pins, discovered/double check, king safety, draw rules, FEN, SAN/PGN, and the engine (perft counts, mate-finding, strength scaling, cancellation).
- `ChessTVTests`: game rules, puzzles, Game Review logic, and persistence round trips.
- `ChessTVUITests`: Home shows Play Bots, starting a Play a Friend game and returning home with the Menu button, and returning from Settings.
- `ChessCoreValidation`: a zero-XCTest smoke runner for restricted machines.
