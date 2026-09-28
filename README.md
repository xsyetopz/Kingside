# CHESS

CHESS is an original, television-first chess application for tvOS. It uses SwiftUI focus navigation, a single-surface directional chessboard, a platform-neutral chess rules module, local persistence, and structured concurrency. CHESS is not affiliated with or endorsed by Chess.com. The Xcode project and internal target retain the `ChessTV` name for build continuity.

## What is implemented

- Native tvOS SwiftUI shell with large focusable home cards
- Local play against an asynchronous built-in alpha-beta search engine
- Complete legal move generation for normal moves, captures, castling, en passant, and all four promotions
- Check, checkmate, stalemate, fifty-move detection, pins, discovered check, double check, and king-safety filtering
- A reusable `ChessBoardView` that is one focus surface—not 64 buttons
- Siri Remote directional/select/back interaction and Bluetooth D-pad/stick/A/B mappings
- Focus, selected-square, legal-move, last-move, and check visualization
- Animated moves/captures, promotion chooser, board flip, undo, restart, clocks, and move list
- Persisted settings, recent games, and unfinished-game restoration
- FEN, SAN, PGN parse/export, and replay primitives
- Locally bundled puzzle provider and playable puzzle flow
- Read-only Chess.com public-profile/game import through documented PubAPI endpoints
- Networking abstractions, friendly error mapping, cancellation, timeout, and conservative retry
- `ChessEngine`, `StockfishEngine`, `StockfishBridge`, `ChessAPI`, `GameService`, and `PuzzleProviding` dependency boundaries
- XCTest unit/UI test sources plus a framework-independent rules validation executable

## Requirements

- Current stable Xcode with the tvOS 17 or later SDK
- A tvOS Simulator or Apple TV
- Swift 6 toolchain

This repository machine currently has only Apple Command Line Tools, not full Xcode. The domain package builds here, but tvOS simulator builds and XCTest require a full Xcode installation.

## Build and run

1. Open `ChessTV.xcodeproj` in Xcode.
2. Choose the `ChessTV` scheme.
3. Select an Apple TV simulator or a provisioned Apple TV.
4. Set your development team and replace the example bundle identifiers if deploying to hardware.
5. Build and run with **Command-R**.

Command-line build after installing Xcode:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -project ChessTV.xcodeproj \
  -scheme ChessTV \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the domain verification available without a simulator:

```sh
swift run ChessCoreValidation
```

Run the package XCTest suite with full Xcode selected:

```sh
swift test
```

## Controls

| Action | Siri Remote | Game controller |
|---|---|---|
| Move board cursor | Directional surface | D-pad / left stick |
| Select piece/destination | Select | A |
| Cancel selection / close overlay | Back | B |

The board retains focus while playing. Promotion and game-menu overlays establish their own initial focus and return control to the board when closed.

## Chess.com account connection

Chess.com's documented PubAPI is read-only and does not authenticate members or accept moves. ChessTV therefore supports a safe public-profile connection by username and never requests or stores a Chess.com password.

Full **Log in with Chess.com** support requires Chess.com to approve the application for OAuth and issue a client ID. The `ChessComAccountAuthorizing` boundary and `ChessComOAuthConfiguration` configuration points are included, but an authorization flow is intentionally not fabricated without approved credentials and confirmed authorization endpoints. Apply through the [official Chess.com developer community OAuth form](https://www.chess.com/club/chess-com-developer-community). Once approved, put non-secret client configuration into generated build settings; any client secret/token exchange should live on a backend and access tokens should be stored in Keychain.

ChessTV uses only the [official read-only PubAPI](https://support.chess.com/en/articles/9650547-what-is-the-pubapi-and-how-do-i-use-it) today.

## Stockfish

`ChessCore` contains a functional async `NativeSearchEngine`, so computer play works offline immediately. It also contains the requested `StockfishEngine` adapter, which validates UCI moves and consumes any injected `StockfishBridge` without coupling GPL engine code to the UI.

An embedded Stockfish binary is not vendored. Stockfish is GPL-3.0, and the currently inspected third-party Swift wrapper declares iOS rather than tvOS. Before distribution, choose one of these explicit product decisions:

1. Distribute ChessTV under GPL-3.0 with complete corresponding source and link a reviewed tvOS Stockfish build through `StockfishBridge`.
2. Keep the built-in engine and do not ship Stockfish.

Do not silently add an unreviewed binary dependency. See the [official Stockfish repository and license](https://github.com/official-stockfish/Stockfish).

## Branding and assets

The UI palette, focus treatment, layout, and generated knight/television master icon are original to ChessTV. The project does not contain Chess.com logos, colors, sounds, board art, or piece assets. The current board pieces use Unicode chess glyphs as replaceable scalable placeholders.

The original icon master is at `ChessTV/Resources/Brand/ChessTVIconMaster.png`. A two-layer tvOS Home/App Store icon stack is included in `ChessTV/Resources/Assets.xcassets`; validate its parallax and safe zone on target hardware before submission.

## Project layout

```text
ChessTV/
├── App/
├── Core/
│   ├── Networking/
│   └── Persistence/
├── Features/
│   ├── Game/
│   ├── Games/
│   ├── Home/
│   ├── Players/
│   ├── Puzzle/
│   └── Settings/
├── Resources/
└── UI/
    ├── ChessBoard/
    ├── Focus/
    └── Theme/
Sources/ChessCore/       # UI-independent domain and engine APIs
Tests/ChessCoreTests/    # chess and PGN XCTest suite
ChessTVTests/            # API and persistence XCTest suite
ChessTVUITests/          # tvOS focus/interaction UI tests
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the dependency graph and extension points.
