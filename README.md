# CHESS

CHESS is an original, television-first chess application for tvOS in the style of a modern online chess service. It uses SwiftUI focus navigation, a single-surface directional chessboard, a platform-neutral chess rules and engine module, local persistence, and structured concurrency. CHESS is not affiliated with or endorsed by Chess.com. The Xcode project and internal target retain the `ChessTV` name for build continuity.

## What is implemented

- Native tvOS SwiftUI shell: a Home screen with a sidebar (Play, Puzzles, Archive, Settings) and a Continue button for an unfinished game
- **Play Bots**: a roster of original bot personalities grouped Beginner, Intermediate, Advanced, and Master, from 250 to 2200 Elo, that comment on the game
- **Play a Friend**: pass-and-play on one Apple TV with bullet, blitz, rapid, or untimed clocks and optional automatic board flip
- Resign, draw offers, takeback, hint, and flip actions during a game; rematch and review from the game-over card
- **Puzzles**: rated puzzles with a persisted rating and streak, Puzzle Rush (3 Minutes, 5 Minutes, Survival), and a Daily Puzzle, all from a bundled puzzle set
- **Game Review**: engine analysis with accuracy, per-move classifications (brilliant through blunder), an evaluation graph, and best-line preview
- **Archive**: finished games saved on the device, each openable in Game Review
- **Settings**: board themes, cburnett pieces, gameplay toggles (legal moves, coordinates, last-move highlight, move animation, auto-promote to queen, sounds), and a live board preview
- Complete legal move generation for normal moves, captures, castling, en passant, and all four promotions
- Check, checkmate, stalemate, fifty-move, threefold-repetition, and insufficient-material detection
- A built-in asynchronous alpha-beta search engine with Elo-scaled strength, also used for hints and Game Review
- A reusable `ChessBoardView` that is one focus surface, not 64 buttons
- Siri Remote directional/select/back interaction and Bluetooth D-pad/stick/A/B mappings
- Persisted settings, puzzle progress, archive, and unfinished-game restoration
- FEN, SAN, PGN parse/export, and replay primitives
- Sound effects synthesized in code
- XCTest unit/UI test sources plus a framework-independent rules validation executable
- No network access: the app contains no networking code

## Requirements

- Current stable Xcode with the tvOS 17 or later SDK
- A tvOS Simulator or Apple TV
- Swift 6 toolchain

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

## Branding and assets

The UI palette, focus treatment, layout, and generated knight/television master icon are original to ChessTV. The project does not contain Chess.com logos, sounds, or board and piece art. The board pieces are the cburnett set and the puzzles come from the Lichess puzzle database; licenses and attribution are in [`ChessTV/Resources/ACKNOWLEDGEMENTS.md`](ChessTV/Resources/ACKNOWLEDGEMENTS.md).

The original icon master is at `ChessTV/Resources/Brand/ChessTVIconMaster.png`. A two-layer tvOS Home/App Store icon stack is included in `ChessTV/Resources/Assets.xcassets`; validate its parallax and safe zone on target hardware before submission.

## Project layout

```text
ChessTV/
├── App/
├── Core/
│   ├── Audio/
│   └── Persistence/
├── Features/
│   ├── Archive/
│   ├── Bots/
│   ├── Game/
│   ├── Home/
│   ├── Puzzle/
│   ├── Review/
│   └── Settings/
├── Resources/
└── UI/
    ├── ChessBoard/
    ├── Components/
    ├── Focus/
    └── Theme/
Sources/ChessCore/       # UI-independent rules, notation, and engine
Tests/ChessCoreTests/    # chess, engine, and PGN XCTest suite
ChessTVTests/            # game, puzzle, review, and persistence XCTest suite
ChessTVUITests/          # tvOS focus/interaction UI tests
Tools/ChessCoreValidation/  # rules validation executable
```

See [ARCHITECTURE.md](ARCHITECTURE.md) for the dependency graph and extension points.
