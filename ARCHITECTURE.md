# Kingside Architecture

This describes the current app: one multiplatform Xcode target (iOS/iPadOS 17, tvOS 17, macOS 14)
over a SwiftPM package. The decision and the slices still planned are in [ADR
0001](docs/architecture/0001-swiftpm-first-multiplatform.md). The rules for online services
(Chess.com and Lichess) are in [ADR
0002](docs/architecture/0002-online-services-and-partner-access.md).

## Package targets

```text
Kingside app ──> ChessUI ──> ChessBoardScene ──┐
 (Kingside/App)     │        ChessFeedback ────┼──> ChessPlay ──> ChessContent ──> ChessCore
                     │                          │
                     ├──> ChessComLink ─────────┼──────────────────────────────────> ChessCore
                     ├──> LichessLink ──────────┼──────────────────────────────────> ChessCore
                     └──> ChessOnline (GameKit)
```

Each target may import only what `Tools/import-rules.json` allows. `Tools/check-imports.sh` checks
system frameworks, and `swift build --explicit-target-dependency-import-check error` checks target
edges.

| Target | Owns |
| --- | --- |
| `ChessCore` | Rules, FEN/SAN/PGN, engine actor. Imports only Foundation. |
| `ChessContent` | Bundled JSON catalogs (bots, board themes, piece sets, time controls, puzzles, sound packs, attributions, services), localisation, piece art, licenses. |
| `ChessPlay` | `@Observable` sessions for games, puzzles, online games, and review; the game clock; board interaction state; settings, puzzle progress, and game stores; the `FeedbackSink` and `OnlineGameConnection` protocols; the online chat rules (`OnlineChat`). |
| `ChessBoardScene` | The SpriteKit board. Renders a `BoardSnapshot` and emits `BoardIntent` values. |
| `ChessFeedback` | Sound, haptics, and game controller input. |
| `ChessComLink` | Read-only Chess.com public API client and PGN import. |
| `LichessLink` | Lichess Board API client (`LichessClient` actor), NDJSON streams, models, PKCE sign-in (`LichessOAuth`), and the token store (`KeychainTokenStore`). Imports Foundation, ChessCore, CryptoKit, and Security. |
| `ChessOnline` | Game Center sign-in (`GameCenterAccount`). No matches yet. |
| `ChessUI` | SwiftUI screens, navigation, and `AppModel`, which builds everything. |
| `ChessBench` (`Tools/ChessBench`) | Engine benchmark executable. |

The app target holds `Kingside/App/KingsideApp.swift` (`@main`, which calls `ChessUI`) and
`Kingside/Resources` (`Assets.xcassets`, `PrivacyInfo.xcprivacy`). The entitlements are in
`Config/Kingside.entitlements`.

`ChessCore` has no dependency on SwiftUI, UIKit, GameController, or persistence. A position is a
value; applying a move returns a new value. This makes search, PGN replay, persistence snapshots,
and tests deterministic.

## Chess rules

`ChessPosition` owns piece placement, side to move, castling rights, en-passant target, and move
counters. Move generation has two stages:

1. Piece-specific pseudo-legal generation, including castling and en passant.
1. Apply each candidate to a copy and remove moves that leave the moving king attacked.

Attack detection is independent of legal-move generation, avoiding recursion and correctly handling
pinned pieces and castling transit squares. `ChessGame` layers SAN history and undo on top of
positions and reports checkmate, stalemate, fifty-move, threefold-repetition, and
insufficient-material outcomes.

## Board input and focus

`BoardScene` (SpriteKit) draws the board from a `BoardSnapshot`. It never changes chess state. It
sends `BoardIntent` values (move focus, select, cancel, promote, and game actions such as hint and
takeback), and `GameSession` decides what they do. `BoardInteraction` in `ChessPlay` holds the
interaction state:

- `focusedSquare`
- `selectedSquare`
- `legalMoves`

Every input source produces the same intents:

- tvOS: Siri Remote directional surface, Select, and Back through `BoardSceneView`, and game
  controllers through `ChessFeedback`.
- iOS and iPadOS: tap a square, or drag a piece.
- macOS: pointer press or drag, and the arrow, Return, Space, and Escape keys.

The scene exposes 64 accessibility elements (square name and piece). On tvOS the board is one
focusable view, so focus cannot leak into side controls while the user navigates squares.

## Local game lifecycle

`AppModel` (in `ChessUI`) owns the `SettingsStore`, the `PuzzleProgressStore`, the
`GamePersistenceStore`, one shared `ChessEngine`, the `ChessComClient`, the `GameCenterAccount`, and
the `LichessAccountModel`.
Play Bots and Pass and Play each build a `GameSetup` and navigate to the game screen through
`AppRoute.game`; the Continue Game card on Play reopens the saved unfinished game.

`GameSession` is main-actor isolated because it publishes UI state. It drives a `GameClock`, asks
`ChessEngine` for bot moves and hints asynchronously, and handles resign, draw offers, and takeback.
Obsolete searches are cancelled. Finished games are saved as `SavedGame` values, which the Games
section lists and Game Review opens through `AppRoute.review`.

## Online games

Online play is on Lichess, through the Board API. It is built as a port, a session, and an adapter:

- `OnlineGameConnection` (`ChessPlay`) is the port for one game on one service. `events()` returns
  a new stream that starts with `.started` (the full game); calling it again reconnects.
  `send(_:)` takes an `OnlineAction` (move in UCI, resign, abort, draw offer and answers, claim
  victory or draw, chat). No Lichess type appears in it.
- `OnlineGameSession` (`ChessPlay`, main actor) plays one game through a connection. The server
  is the source of truth: `.started` replaces all state, and `.state` brings moves, clocks, draw
  offers, and status. The player's move shows at once and stays pending until a server state has
  it; a failed send rolls the board back. The local clock counts down between server states and
  never flags. There is no engine, so hint, takeback, and rematch do nothing. A finished game is
  saved once to the archive as `GameMode.online`, with an id derived from the service and game id.
  Aborted games are not saved.
- `LichessGameConnection` (`ChessUI/Online`) is the adapter. It maps the Board API game stream to
  `OnlineGameEvent`s, and `OnlineAction`s to `LichessClient` calls.
- `LichessAccountModel` (`ChessUI`) holds the sign-in state, incoming and outgoing challenges,
  ongoing games, and the quick seek. It gives out a `LichessGameConnection` for a game id. Lichess
  allows one event stream (`/api/stream/event`) per token, so this model owns the only one, and
  nothing else opens it. The model reconnects after a drop with a back-off that starts at 1 s and
  doubles up to 30 s, and waits at least 60 s after a 429. A 401 signs the user out locally.
- The lobby (`OnlineLobbyScreen`) offers a quick seek (Rapid and Classical presets), a challenge
  to a named user (Blitz, Rapid, and Classical presets), incoming challenges, and ongoing games to
  resume. `OnlineGameScreen` shows a game with the same panels as a local game through the
  `PlayableGame` protocol, which both session types adopt.
- Chat: `OnlineChat` (`ChessPlay`) decides which lines show. Chat is off when `chatEnabled` is
  false, a muted opponent's lines are dropped, and other opponent lines pass through the word list
  in `chat-filter.json`. Sent text is cut to 140 characters. `OnlineChatPanel` also links to the
  Lichess report page for the opponent.

Sign-in (`LichessAccountSection`, `LichessSignIn`):

- iOS, iPadOS, and macOS: `ASWebAuthenticationSession` opens the Lichess authorization page
  (PKCE, `S256`, scopes `board:play challenge:read challenge:write`). The redirect is a custom URL
  scheme from `services.json`. The app exchanges the code for a token.
- tvOS: no browser sign-in. The user either signs in on another device and lets iCloud Keychain
  sync the token, or pastes a personal access token created on the Lichess website.

`LichessClient` runs its one-shot requests one at a time. A 429 blocks every request for 60
seconds. Streams do not wait in that queue, but they honour the block. Every request carries the
`User-Agent` built from `services.json` `contact` (`<product>/<version> (+<contact>)`), the same one
`ChessComLink` uses.

## Computer engine

`ChessEngine` (`Sources/ChessCore/ChessEngine.swift`) is an actor in `ChessCore` running an
alpha-beta search over an internal 0x88 board with a transposition table. Search never runs on the
main actor and stops when its task is cancelled.

- `bestMove(game:strength:)` plays for bots. `EngineStrength` maps an Elo value (250 to 2200) to
  search depth, think time, evaluation noise, and a chance of choosing a weaker candidate move.
- `analyze(position:history:limit:)` returns the best line and evaluation, used for hints and Game
  Review.

## Puzzles

`puzzles.json` (Lichess puzzle database) is a `ChessContent` catalog loaded from the bundle.
`PuzzleSelector` picks puzzles for rated play, Puzzle Rush, and the Daily Puzzle. `PuzzleRating`
computes rating changes, and `PuzzleRushRun` holds the score, strikes, and clock of a Puzzle Rush
run (3 Minutes, 5 Minutes, or Survival).

## Game Review

`GameReviewModel` (`ChessPlay`) analyzes each position of a saved game with `ChessEngine.analyze`
and caches the results in memory for the app session. The pure logic in `ReviewClassification.swift`
(win probability, move classification, accuracy) is separate from the UI and tested in
`ReviewTests`.

## Persistence

- `SettingsStore`: `AppSettings` (board theme, piece set, orientation, gameplay toggles, sound and
  haptics toggles, online chat toggle `chatEnabled`, linked Chess.com username) as JSON in
  `UserDefaults` under `Kingside.settings.v1`. Settings are per device.
- `PuzzleProgressStore`: puzzle rating, streaks, Puzzle Rush bests, seen puzzles, and solved daily
  puzzles in `UserDefaults` under `Kingside.puzzleProgress.v1`.
- `GamePersistenceStore`: an actor that writes `saved-games-v2.json` in `Kingside/` under
  Application Support atomically. It keeps at most one unfinished game and the newest 200 finished
  games. Finished online games are saved here too.
- `KeychainTokenStore` (`LichessLink`): the Lichess access token, as a generic-password Keychain
  item (service `io.github.xsyetopz.Kingside.lichess`, account `access-token`). It is
  synchronizable, so iCloud Keychain can copy it to other devices, and accessible after first
  unlock. UI tests use an in-memory store instead.

## Network use

Play, puzzles, and review need no network. Three features use it:

- `ChessOnline` signs in through GameKit. It has no match code.
- `ChessComLink` reads `https://api.chess.com/pub/` (profile, stats, game archives) for the username
  the user typed. Base URL and contact URL come from `services.json`. Requests carry a `User-Agent`,
  the client reuses `ETag` responses through an in-memory cache, and it validates the username
  before building a URL. The username is the only Chess.com data stored, in `AppSettings`. Imported
  games become ordinary `SavedGame`s in the archive.
- `LichessLink` talks to `https://lichess.org` (`services.json`, `lichess.baseURL`) once the user
  signs in. At launch, if a token is stored, the app checks it (`/api/account`) and opens the event
  stream. The token is sent as a bearer token. The token lives in the Keychain (see Persistence).
  Signing out asks Lichess to revoke it and deletes it locally.

Data sent to Lichess: the token; the user's moves, resign, abort, draw, and claim actions; chat
text; seek and challenge settings (rated, time control, colour, opponent username); and the
`User-Agent` with the app name, version, and contact. Lichess also sees the device's IP address. No
data goes to the developer; the code has no server of its own. The report link opens the Lichess
report page in the browser.

There is no CloudKit or other sync in the code. The only cross-device copy is the Keychain token.

## Testing strategy

- Swift Testing suites under `Tests/<Target>Tests` for every package target except `ChessBench`:
  - `ChessCoreTests`: rules, FEN, SAN/PGN, and the engine (perft counts, mate-finding, strength
    scaling, cancellation).
  - `ChessContentTests`: catalog validation, localisation, and the chat filter.
  - `ChessPlayTests`: game rules, sessions, puzzles, Game Review logic, persistence round trips,
    `OnlineGameSession` (against a fake connection), and `OnlineChat`.
  - `LichessLinkTests`: the client (request order, back-off, validation), NDJSON streams, and PKCE,
    with recorded fixtures and a fake transport.
  - `ChessBoardSceneTests`, `ChessFeedbackTests`, `ChessComLinkTests` (recorded fixtures),
    `ChessOnlineTests`, `ChessUITests` (layout and model logic, including
    `LichessAccountModel`, `LichessGameConnection`, sign-in callbacks, and the lobby).
- `KingsideUITests` (XCTest, the only XCTest target): launches the app with `--uitesting` and
  checks that Play shows Play Bots and Pass and Play, and that a Pass and Play game opens a board
  and Back returns to setup.
- `ChessBench`: fixed-depth engine searches reporting nodes per second
  (`swift run -c release ChessBench`).
- `Tools/check-imports.sh`: fails when a package target imports a module not allowed by
  `Tools/import-rules.json`.
- `Tools/check-localizations.sh`: reports missing, obsolete, and stale locale entries.
