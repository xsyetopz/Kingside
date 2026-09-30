# OpenChess Architecture

This describes the current app: one multiplatform Xcode target (iOS/iPadOS 17, tvOS 17, macOS 14) over a SwiftPM package. The decision and the slices still planned are in [ADR 0001](docs/architecture/0001-swiftpm-first-multiplatform.md).

## Package targets

```text
OpenChess app ──> ChessUI ──> ChessBoardScene ──┐
 (OpenChess/App)     │        ChessFeedback ────┼──> ChessPlay ──> ChessContent ──> ChessCore
                     │                          │
                     ├──> ChessComLink ─────────┼──────────────────────────────────> ChessCore
                     └──> ChessOnline (GameKit)
```

Each target may import only what `Tools/import-rules.json` allows. `Tools/check-imports.sh` checks system frameworks, and `swift build --explicit-target-dependency-import-check error` checks target edges.

| Target | Owns |
|---|---|
| `ChessCore` | Rules, FEN/SAN/PGN, engine actor. Imports only Foundation. |
| `ChessContent` | Bundled JSON catalogs (bots, board themes, piece sets, time controls, puzzles, sound packs, attributions, services), localisation, piece art, licenses. |
| `ChessPlay` | `@Observable` sessions for games, puzzles, and review; the game clock; board interaction state; settings, puzzle progress, and game stores; the `FeedbackSink` protocol. |
| `ChessBoardScene` | The SpriteKit board. Renders a `BoardSnapshot` and emits `BoardIntent` values. |
| `ChessFeedback` | Sound, haptics, and game controller input. |
| `ChessComLink` | Read-only Chess.com public API client and PGN import. |
| `ChessOnline` | Game Center sign-in (`GameCenterAccount`). No matches yet. |
| `ChessUI` | SwiftUI screens, navigation, and `AppModel`, which builds everything. |
| `ChessBench` (`Tools/ChessBench`) | Engine benchmark executable. |

The app target holds `OpenChess/App/OpenChessApp.swift` (`@main`, which calls `ChessUI`) and `OpenChess/Resources` (`Assets.xcassets`, `PrivacyInfo.xcprivacy`). The entitlements are in `Config/OpenChess.entitlements`.

`ChessCore` has no dependency on SwiftUI, UIKit, GameController, or persistence. A position is a value; applying a move returns a new value. This makes search, PGN replay, persistence snapshots, and tests deterministic.

## Chess rules

`ChessPosition` owns piece placement, side to move, castling rights, en-passant target, and move counters. Move generation has two stages:

1. Piece-specific pseudo-legal generation, including castling and en passant.
2. Apply each candidate to a copy and remove moves that leave the moving king attacked.

Attack detection is independent of legal-move generation, avoiding recursion and correctly handling pinned pieces and castling transit squares. `ChessGame` layers SAN history and undo on top of positions and reports checkmate, stalemate, fifty-move, threefold-repetition, and insufficient-material outcomes.

## Board input and focus

`BoardScene` (SpriteKit) draws the board from a `BoardSnapshot`. It never changes chess state. It sends `BoardIntent` values (move focus, select, cancel, promote, and game actions such as hint and takeback), and `GameSession` decides what they do. `BoardInteraction` in `ChessPlay` holds the interaction state:

- `focusedSquare`
- `selectedSquare`
- `legalMoves`

Every input source produces the same intents:

- tvOS: Siri Remote directional surface, Select, and Back through `BoardSceneView`, and game controllers through `ChessFeedback`.
- iOS and iPadOS: tap a square, or drag a piece.
- macOS: pointer press or drag, and the arrow, Return, Space, and Escape keys.

The scene exposes 64 accessibility elements (square name and piece). On tvOS the board is one focusable view, so focus cannot leak into side controls while the user navigates squares.

## Local game lifecycle

`AppModel` (in `ChessUI`) owns the `SettingsStore`, the `PuzzleProgressStore`, the `GamePersistenceStore`, one shared `ChessEngine`, the `ChessComClient`, and the `GameCenterAccount`. Play Bots and Pass and Play each build a `GameSetup` and navigate to the game screen through `AppRoute.game`; the Continue Game card on Play reopens the saved unfinished game.

`GameSession` is main-actor isolated because it publishes UI state. It drives a `GameClock`, asks `ChessEngine` for bot moves and hints asynchronously, and handles resign, draw offers, and takeback. Obsolete searches are cancelled. Finished games are saved as `SavedGame` values, which the Games section lists and Game Review opens through `AppRoute.review`.

## Computer engine

`ChessEngine` (`Sources/ChessCore/ChessEngine.swift`) is an actor in `ChessCore` running an alpha-beta search over an internal 0x88 board with a transposition table. Search never runs on the main actor and stops when its task is cancelled.

- `bestMove(game:strength:)` plays for bots. `EngineStrength` maps an Elo value (250 to 2200) to search depth, think time, evaluation noise, and a chance of choosing a weaker candidate move.
- `analyze(position:history:limit:)` returns the best line and evaluation, used for hints and Game Review.

## Puzzles

`puzzles.json` (Lichess puzzle database) is a `ChessContent` catalog loaded from the bundle. `PuzzleSelector` picks puzzles for rated play, Puzzle Rush, and the Daily Puzzle. `PuzzleRating` computes rating changes, and `PuzzleRushRun` holds the score, strikes, and clock of a Puzzle Rush run (3 Minutes, 5 Minutes, or Survival).

## Game Review

`GameReviewModel` (`ChessPlay`) analyzes each position of a saved game with `ChessEngine.analyze` and caches the results in memory for the app session. The pure logic in `ReviewClassification.swift` (win probability, move classification, accuracy) is separate from the UI and tested in `ReviewTests`.

## Persistence

- `SettingsStore`: `AppSettings` (board theme, piece set, orientation, gameplay toggles, sound and haptics toggles, linked Chess.com username) as JSON in `UserDefaults` under `OpenChess.settings.v1`. Settings are per device.
- `PuzzleProgressStore`: puzzle rating, streaks, Puzzle Rush bests, seen puzzles, and solved daily puzzles in `UserDefaults` under `OpenChess.puzzleProgress.v1`.
- `GamePersistenceStore`: an actor that writes `saved-games-v2.json` in `OpenChess/` under Application Support atomically. It keeps at most one unfinished game and the newest 200 finished games.

## Network use

Only two features touch the network, both from the Account section:

- `ChessOnline` signs in through GameKit. It has no match code.
- `ChessComLink` reads `https://api.chess.com/pub/` (profile, stats, game archives) for the username the user typed. Base URL and contact URL come from `services.json`. Requests carry a `User-Agent`, the client reuses `ETag` responses through an in-memory cache, and it validates the username before building a URL. The username is the only Chess.com data stored, in `AppSettings`. Imported games become ordinary `SavedGame`s in the archive.

There is no CloudKit or other sync in the code.

## Testing strategy

- Swift Testing suites under `Tests/<Target>Tests` for every package target except `ChessBench`:
  - `ChessCoreTests`: rules, FEN, SAN/PGN, and the engine (perft counts, mate-finding, strength scaling, cancellation).
  - `ChessContentTests`: catalog validation and localisation.
  - `ChessPlayTests`: game rules, sessions, puzzles, Game Review logic, and persistence round trips.
  - `ChessBoardSceneTests`, `ChessFeedbackTests`, `ChessComLinkTests` (recorded fixtures), `ChessOnlineTests`, `ChessUITests` (layout and model logic).
- `OpenChessUITests` (XCTest, the only XCTest target): launches the app with `--uitesting` and checks that Play shows Play Bots and Pass and Play, and that a Pass and Play game opens a board and Back returns to setup.
- `ChessBench`: fixed-depth engine searches reporting nodes per second (`swift run -c release ChessBench`).
- `Tools/check-imports.sh`: fails when a package target imports a module not allowed by `Tools/import-rules.json`.
- `Tools/check-localizations.sh`: reports missing, obsolete, and stale locale entries.
