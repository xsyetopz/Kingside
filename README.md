# Kingside

Kingside is an original chess application for iOS, iPadOS, tvOS, and macOS in the style of a modern
online chess service. It uses SwiftUI for screens, a SpriteKit chessboard, a platform-neutral chess
rules and engine module, local persistence, and structured concurrency. Kingside is not affiliated
with or endorsed by Chess.com.

One multiplatform Xcode target (`Kingside`, bundle ID `io.github.xsyetopz.Kingside`) is a thin
shell. All other code is in the SwiftPM package `Kingside`.

## What is implemented

- Native SwiftUI shell with five sections (Play, Puzzles, Games, Account, Settings): a tab view on
  iOS, iPadOS, and tvOS and a sidebar on macOS. Play has a Continue Game card for an unfinished game
- **Play Bots**: a roster of original bot personalities grouped Beginner, Intermediate, Advanced,
  and Master, from 250 to 2200 Elo, that comment on the game
- **Pass and Play**: two players on one device with bullet, blitz, rapid, or untimed clocks and
  optional automatic board flip
- Resign, draw offers, takeback, hint, and flip actions during a game; rematch and review from the
  game-over card
- **Play Online**: games on Lichess through the Board API after you sign in: a quick seek, a
  challenge to a friend, incoming challenges, and resuming ongoing games. There are no hints,
  takeback, or engine help in online games. In-game chat can be turned off in Settings. Finished
  online games are saved to the archive
- **Puzzles**: rated puzzles with a persisted rating and streak, Puzzle Rush (3 Minutes, 5 Minutes,
  Survival), and a Daily Puzzle, all from a bundled puzzle set
- **Game Review**: engine analysis with accuracy, per-move classifications (brilliant through
  blunder), an evaluation graph, and best-line preview
- **Games**: finished games saved on the device, each openable in Game Review
- **Settings**: board themes, cburnett pieces, board orientation, gameplay toggles (legal moves,
  coordinates, last-move highlight, move animation, always promote to queen), sound and haptics
  toggles, and a Licenses screen
- **Account**: sign-in with Game Center (GameKit), an optional read-only Chess.com link, and an
  optional Lichess sign-in for online play (see below)
- Complete legal move generation for normal moves, captures, castling, en passant, and all four
  promotions
- Check, checkmate, stalemate, fifty-move, threefold-repetition, and insufficient-material detection
- A built-in asynchronous alpha-beta search engine with Elo-scaled strength, also used for hints and
  Game Review
- A SpriteKit board (`ChessBoardScene`) with 64 accessibility elements, driven by touch, pointer,
  keyboard, Siri Remote, and game controller input
- Persisted settings, puzzle progress, archive, and unfinished-game restoration
- FEN, SAN, PGN parse/export, and replay primitives
- Sound effects synthesized in code, and haptics where the device supports them
- Swift Testing suites for the package, XCTest UI tests in `KingsideUITests/`, a layering check
  (`Tools/check-imports.sh`), and an engine benchmark (`ChessBench`)
- English source strings with 82 other locale folders that are English copies until translated

### Network use

Play, puzzles, and review need no network. The app makes network requests only when you use the
Account section or Play Online:

- Game Center sign-in goes through GameKit. `ChessOnline` has the sign-in only.
- The Chess.com link stores the public Chess.com username you type. It reads public data from
  `https://api.chess.com/pub/` (profile, ratings, and the latest monthly game archive, which you can
  import). It uses no password and no OAuth.
- The Lichess sign-in uses OAuth with PKCE in a browser session on iOS, iPadOS, and macOS. On tvOS,
  you use a token that iCloud Keychain syncs from another device, or paste a personal access token.
  The token is stored in the Keychain. While you are signed in, your moves, game actions, chat, and
  seek and challenge settings go to `https://lichess.org` under your account, and Lichess's privacy
  policy applies to them. Signing out asks Lichess to revoke the token. Online requests carry a
  `User-Agent` built from the `contact` value in `services.json`, which is still a placeholder.

There is no CloudKit or other sync in the code. The only cross-device copy is the Lichess token in
iCloud Keychain.

Kingside uses only the official Chess.com interfaces. Online play is on the Lichess Board API.
[ADR 0002](docs/architecture/0002-online-services-and-partner-access.md) has the rules, the risks,
and the reasons.

## Requirements

- Xcode 26 or later
- A simulator or device for one of: iOS or iPadOS 17, tvOS 17, macOS 14
- Swift 6.1 or later

## Build and run

1. Open `Kingside.xcodeproj` in Xcode.
1. Choose the `Kingside` scheme.
1. Select an iOS, iPadOS, tvOS, or macOS destination.
1. Set your development team and change the bundle identifier if deploying to hardware. The project
   uses team `9PQP6CDMQT` and the `com.apple.developer.game-center` entitlement
   (`Config/Kingside.entitlements`).
1. Build and run with **Command-R**.

Command-line builds need the Swift toolchain that ships with Xcode. A swift.org toolchain, such as
one installed with swiftly, does not work:

- It lacks Apple's SwiftUI overlays, so `swift build` fails in `ChessUI`
  (`LichessAccountSection.swift`: "cannot infer key path type from context" at
  `\.webAuthenticationSession`).
- With its `TOOLCHAINS` variable set, `xcodebuild` fails to resolve packages ("link command failed
  with exit code 1").

swiftly sets `TOOLCHAINS` in your shell profile, so unset it and `SDKROOT` in the shell that
builds, and select Xcode (or set `DEVELOPER_DIR` to its `Contents/Developer` folder):

```sh
unset TOOLCHAINS SDKROOT
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
```

Command-line app build (this example builds for the tvOS Simulator; change `-destination` for other
platforms, for example `'platform=macOS'`):

```sh
xcodebuild -project Kingside.xcodeproj \
  -scheme Kingside \
  -destination 'platform=tvOS Simulator,name=Apple TV' \
  CODE_SIGNING_ALLOWED=NO build
```

Run the package checks without a simulator, in the same shell. `xcrun swift` runs Xcode's `swift`
even when swiftly's `swift` is first on `PATH`:

```sh
xcrun swift build --build-tests --explicit-target-dependency-import-check error
xcrun swift test                # Swift Testing suites
Tools/check-imports.sh          # per-target import rules in Tools/import-rules.json
Tools/check-localizations.sh    # missing, obsolete, and stale locale entries
xcrun swift run -c release ChessBench # engine nodes per second
```

## Controls

tvOS:

| Action | Siri Remote | Game controller |
| --- | --- | --- |
| Move board cursor | Directional surface | D-pad / left stick |
| Select piece/destination | Select | A |
| Cancel selection / close overlay | Back | B |

The board retains focus while playing. Promotion and game-menu overlays establish their own initial
focus and return control to the board when closed.

iOS and iPadOS: tap a square to select it, then tap the destination. You can also drag a piece.

macOS: click a square or drag a piece, or use the arrow keys to move the cursor, Return or Space to
select, and Escape to cancel a selection.

## Branding and assets

The UI palette, layout, and generated knight/television master icon are original to Kingside. The
project does not contain Chess.com logos, sounds, or board and piece art. The board pieces are the
cburnett set (BSD-3-Clause) and the puzzles come from the Lichess puzzle database. Licenses and
attribution are in [`ACKNOWLEDGEMENTS.md`](ACKNOWLEDGEMENTS.md) and in the app under Settings >
Licenses (data in `Sources/ChessContent/Resources/Catalogs/attributions.json` and
`Sources/ChessContent/Resources/Licenses/`).

The icon master is at `Artwork/Brand/KingsideIconMaster.png`. The app icon (`AppIcon.appiconset`)
and the two-layer tvOS icon stack (`AppIconTV.brandassets`) are in
`Kingside/Resources/Assets.xcassets`. Validate the tvOS parallax and safe zone on target hardware
before submission.

## Project layout

```text
Kingside/
├── App/                    # @main; calls ChessUI
└── Resources/              # Assets.xcassets, PrivacyInfo.xcprivacy
Config/                     # Kingside.entitlements
Sources/
├── ChessCore/              # UI-independent rules, notation, and engine
├── ChessContent/           # JSON catalogs, localisation, pieces, licenses
├── ChessComLink/           # read-only Chess.com public API client
├── LichessLink/            # Lichess Board API client, PKCE sign-in, Keychain token
├── ChessOnline/            # Game Center sign-in
├── ChessPlay/              # game, puzzle, and review sessions; stores
├── ChessBoardScene/        # SpriteKit board
├── ChessFeedback/          # sound, haptics, controller input
└── ChessUI/                # SwiftUI screens and the app model
Tests/<Target>Tests/       # Swift Testing suites, one per target
KingsideUITests/          # XCTest UI tests
Tools/ChessBench/          # engine benchmark executable
Tools/check-imports.sh     # layering check, rules in Tools/import-rules.json
Tools/check-localizations.sh, Tools/sync-localizations.sh
docs/architecture/         # decision records
```

## Localisation

English (`en-US`) is the only source. Add keys only to
`Sources/ChessContent/Resources/Localization/en-US.lproj/Localizable.strings`, then run
`Tools/sync-localizations.sh`. It copies missing keys to every other locale as English.
`Tools/check-localizations.sh` reports missing and obsolete keys and stale lines (entries still
identical to English). Stale lines are expected until a locale is translated, so the script exits 1
while any exist.

See [ARCHITECTURE.md](ARCHITECTURE.md) for the dependency graph and extension points, and [ADR
0001](docs/architecture/0001-swiftpm-first-multiplatform.md) for the multiplatform SwiftPM and
SpriteKit decision and the slices still planned.
