# OpenChess

OpenChess is an original chess application for iOS, iPadOS, tvOS, and macOS in the style of a modern online chess service. It uses SwiftUI for screens, a SpriteKit chessboard, a platform-neutral chess rules and engine module, local persistence, and structured concurrency. OpenChess is not affiliated with or endorsed by Chess.com.

One multiplatform Xcode target (`OpenChess`, bundle ID `io.github.xsyetopz.OpenChess`) is a thin shell. All other code is in the SwiftPM package `OpenChess`.

## What is implemented

- Native SwiftUI shell with five sections (Play, Puzzles, Games, Account, Settings): a tab view on iOS, iPadOS, and tvOS and a sidebar on macOS. Play has a Continue Game card for an unfinished game
- **Play Bots**: a roster of original bot personalities grouped Beginner, Intermediate, Advanced, and Master, from 250 to 2200 Elo, that comment on the game
- **Pass and Play**: two players on one device with bullet, blitz, rapid, or untimed clocks and optional automatic board flip
- Resign, draw offers, takeback, hint, and flip actions during a game; rematch and review from the game-over card
- **Puzzles**: rated puzzles with a persisted rating and streak, Puzzle Rush (3 Minutes, 5 Minutes, Survival), and a Daily Puzzle, all from a bundled puzzle set
- **Game Review**: engine analysis with accuracy, per-move classifications (brilliant through blunder), an evaluation graph, and best-line preview
- **Games**: finished games saved on the device, each openable in Game Review
- **Settings**: board themes, cburnett pieces, board orientation, gameplay toggles (legal moves, coordinates, last-move highlight, move animation, always promote to queen), sound and haptics toggles, and a Licenses screen
- **Account**: sign-in with Game Center (GameKit), and an optional read-only Chess.com link (see below)
- Complete legal move generation for normal moves, captures, castling, en passant, and all four promotions
- Check, checkmate, stalemate, fifty-move, threefold-repetition, and insufficient-material detection
- A built-in asynchronous alpha-beta search engine with Elo-scaled strength, also used for hints and Game Review
- A SpriteKit board (`ChessBoardScene`) with 64 accessibility elements, driven by touch, pointer, keyboard, Siri Remote, and game controller input
- Persisted settings, puzzle progress, archive, and unfinished-game restoration
- FEN, SAN, PGN parse/export, and replay primitives
- Sound effects synthesized in code, and haptics where the device supports them
- Swift Testing suites for the package, XCTest UI tests in `OpenChessUITests/`, a layering check (`Tools/check-imports.sh`), and an engine benchmark (`ChessBench`)
- English source strings with 82 other locale folders that are English copies until translated

### Network use

Play, puzzles, and review need no network. The app makes network requests only when you use the Account section:

- Game Center sign-in goes through GameKit. `ChessOnline` has the sign-in only. There is no online play yet.
- The Chess.com link stores the public Chess.com username you type. It reads public data from `https://api.chess.com/pub/` (profile, ratings, and the latest monthly game archive, which you can import). It uses no password and no OAuth.

There is no CloudKit or other sync yet.

## Requirements

- Xcode 26 or later
- A simulator or device for one of: iOS or iPadOS 17, tvOS 17, macOS 14
- Swift 6.1 or later

## Build and run

1. Open `OpenChess.xcodeproj` in Xcode.
1. Choose the `OpenChess` scheme.
1. Select an iOS, iPadOS, tvOS, or macOS destination.
1. Set your development team and change the bundle identifier if deploying to hardware. The project uses team `9PQP6CDMQT` and the `com.apple.developer.game-center` entitlement (`Config/OpenChess.entitlements`).
1. Build and run with **Command-R**.

Command-line build after installing Xcode (this example builds for the tvOS Simulator; change `-destination` for other platforms):

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
xcodebuild -project OpenChess.xcodeproj \
  -scheme OpenChess \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the package checks without a simulator. With a swiftly toolchain, point `SDKROOT` at an Xcode macOS SDK first, because the Command Line Tools' macOS 27 SDK fails to link (`unknown architecture arm64e.x1-macos`):

```sh
export SDKROOT=$(DEVELOPER_DIR=/Applications/Xcode-26.6.0.app/Contents/Developer xcrun --sdk macosx --show-sdk-path)
swift build --build-tests --explicit-target-dependency-import-check error
swift test                      # Swift Testing suites
Tools/check-imports.sh          # per-target import rules in Tools/import-rules.json
Tools/check-localizations.sh    # missing, obsolete, and stale locale entries
swift run -c release ChessBench # engine nodes per second
```

## Controls

tvOS:

| Action | Siri Remote | Game controller |
| --- | --- | --- |
| Move board cursor | Directional surface | D-pad / left stick |
| Select piece/destination | Select | A |
| Cancel selection / close overlay | Back | B |

The board retains focus while playing. Promotion and game-menu overlays establish their own initial focus and return control to the board when closed.

iOS and iPadOS: tap a square to select it, then tap the destination. You can also drag a piece.

macOS: click a square or drag a piece, or use the arrow keys to move the cursor, Return or Space to select, and Escape to cancel a selection.

## Branding and assets

The UI palette, layout, and generated knight/television master icon are original to OpenChess. The project does not contain Chess.com logos, sounds, or board and piece art. The board pieces are the cburnett set (BSD-3-Clause) and the puzzles come from the Lichess puzzle database. Licenses and attribution are in [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md) and in the app under Settings > Licenses (data in `Sources/ChessContent/Resources/Catalogs/attributions.json` and `Sources/ChessContent/Resources/Licenses/`).

The icon master is at `Artwork/Brand/OpenChessIconMaster.png`. The app icon (`AppIcon.appiconset`) and the two-layer tvOS icon stack (`AppIconTV.brandassets`) are in `OpenChess/Resources/Assets.xcassets`. Validate the tvOS parallax and safe zone on target hardware before submission.

## Project layout

```text
OpenChess/
├── App/                    # @main; calls ChessUI
└── Resources/              # Assets.xcassets, PrivacyInfo.xcprivacy
Config/                     # OpenChess.entitlements
Sources/
├── ChessCore/              # UI-independent rules, notation, and engine
├── ChessContent/           # JSON catalogs, localisation, pieces, licenses
├── ChessComLink/           # read-only Chess.com public API client
├── ChessOnline/            # Game Center sign-in
├── ChessPlay/              # game, puzzle, and review sessions; stores
├── ChessBoardScene/        # SpriteKit board
├── ChessFeedback/          # sound, haptics, controller input
└── ChessUI/                # SwiftUI screens and the app model
Tests/<Target>Tests/       # Swift Testing suites, one per target
OpenChessUITests/          # XCTest UI tests
Tools/ChessBench/          # engine benchmark executable
Tools/check-imports.sh     # layering check, rules in Tools/import-rules.json
Tools/check-localizations.sh, Tools/sync-localizations.sh
docs/architecture/         # decision records
```

## Localisation

English (`en-US`) is the only source. Add keys only to `Sources/ChessContent/Resources/Localization/en-US.lproj/Localizable.strings`, then run `Tools/sync-localizations.sh`. It copies missing keys to every other locale as English. `Tools/check-localizations.sh` reports missing and obsolete keys and stale lines (entries still identical to English). Stale lines are expected until a locale is translated, so the script exits 1 while any exist.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the dependency graph and extension points, and [ADR 0001](docs/architecture/0001-swiftpm-first-multiplatform.md) for the multiplatform SwiftPM and SpriteKit decision and the slices still planned.
