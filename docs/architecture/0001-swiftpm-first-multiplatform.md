# ADR 0001: SwiftPM-first multiplatform game on SpriteKit

- Status: accepted. Slices S0–S5 and CL are built. S6 and S7 are planned. Updated 2026-09-30 to
  match the code.
- Date: 2026-09-29

## Context

Kingside is a chess.com-style chess client. When this ADR was written it was a tvOS-only Xcode app:
77 Swift files in `Kingside/`, with `ChessCore` as its only SwiftPM target. It is now one
multiplatform Xcode target over the SwiftPM targets below.

The goal is to ship on iOS, iPadOS, tvOS, and macOS with this stack. Not all of it is built yet:
CloudKit and StoreKit are not used, and GameKit is used for sign-in only.

| Framework | Use |
| --- | --- |
| SpriteKit | The board |
| SwiftUI | Menus and other non-game UI |
| GameKit | Game Center |
| AVFAudio and Core Haptics | Feedback |
| CloudKit | Sync saves and puzzle progress |
| StoreKit | Only if needed |
| Metal or `SKShader` | Only for effects SpriteKit lacks |

Further constraints:

- Nothing is hard-coded.
- Code is built with SwiftPM and tested with Swift Testing.
- The minimum Swift version is 6.1; the local toolchain is 6.3.3.
- All assets are Creative Commons or otherwise non-proprietary.

The tvOS-only app had these coupling problems. The migration slices S1 to S5 replaced that code; the
list is kept as the reason for the layout.

- **Content in code.** Content lives in Swift source:
  - `BotRoster.swift` holds 12 bots, with SwiftUI `Color` values and chat lines in code.
  - `BoardTheme.swift` holds the board colors.
  - `ChessTheme.swift` holds the colors, plus unused "legacy aliases".
- **Feedback called from logic.** Game and puzzle logic call `SoundEffects.shared.play` directly:
  - `GameViewModel.swift`: 5 call sites.
  - `PuzzleBoardModel.swift`: 3 call sites.

  So the logic cannot run without AVFAudio.
- **SwiftUI in board state.** `BoardInteractionController` imports SwiftUI.
- **Loading from the app bundle.** Puzzles load from `Bundle.main`.
- **Logic tests need Xcode.** Game, review, and persistence logic live in the app target. Their
  tests are XCTest `@testable import Kingside`, so they need Xcode and a tvOS simulator.

## Decision

### Package layout

One SwiftPM package owns all code. The allowed imports of each target are
listed in `Tools/import-rules.json` and checked.

| Target | May import | Owns | Slice |
| --- | --- | --- | --- |
| `ChessCore` | Foundation | Rules, FEN/SAN/PGN, engine actor | exists |
| `ChessContent` | Foundation, ChessCore | Catalogs as bundled JSON through `Bundle.module`: bots, board themes, piece sets, time controls, puzzles, sound specs, UI strings. Colors are hex strings, not SwiftUI types. | S1 |
| `ChessPlay` | Foundation, Observation, ChessCore, ChessContent | The items below | S2 |
| `ChessBoardScene` | SpriteKit, ChessCore, ChessContent, ChessPlay | `SKScene` that renders a `BoardSnapshot` and emits `BoardIntent` values. Hit testing, focus ring, move and capture animations, arrows, accessibility elements. | S3 |
| `ChessFeedback` | AVFAudio, CoreHaptics, GameController, ChessPlay, ChessContent | Implements `FeedbackSink`. Haptics only when `CHHapticEngine.capabilitiesForHardware().supportsHaptics`. Maps controller input to `BoardIntent`. | S4 |
| `ChessUI` | SwiftUI, SpriteKit (`SpriteView`), everything above | Screens, per-platform navigation (tab view, or sidebar on macOS), `AppModel` as the composition root | S5 |
| `ChessOnline` | Foundation, GameKit, Observation | Today: Game Center sign-in (`GameCenterAccount`). Planned: Game Center matches, and the dependency on `ChessPlay` that they need. | S6 (sign-in done) |
| `ChessSync` | CloudKit, ChessPlay | `CKSyncEngine` adapter for the private database. Planned: the target does not exist. | S7 |
| `ChessComLink` | Foundation, ChessCore | Read-only Chess.com Published-Data API client: profile, stats, monthly archives, PGN import. `HTTPTransport` port (URLSession adapter and a recording fake). Requests are strictly serial, carry a caller-supplied User-Agent, and reuse `ETag`s. Usernames are validated to `[a-z0-9_-]{3,25}` before a URL is built. | CL |

`ChessPlay` owns:

- The `@Observable` sessions for games, puzzles, and review.
- The clock (the standard-library `Clock` protocol, injected) and adjudication.
- The settings model and the board interaction state.
- The `BoardSnapshot` and `BoardIntent` value types.
- Persistence stores.
- The `FeedbackSink` protocol.

A thin multiplatform Xcode app target contains only these items:

- `@main`, which calls `ChessUI`.
- A generated `Info.plist` (build settings, no file).
- The entitlements file, `Config/Kingside.entitlements`, and `PrivacyInfo.xcprivacy`.
- The asset catalog, which holds the app icon and the tvOS brand assets. There is no top-shelf image
  yet.

### Rules the layout enforces

- **SpriteKit only projects.** Scene nodes are a projection of `BoardSnapshot`. The scene never
  mutates chess state. It sends intents, and the session decides.
- **Ports need two implementations.** A port exists only when two implementations exist today. A
  test double counts.
  - `FeedbackSink` qualifies: the AV/haptics adapter plus a recording double in the tests.
  - The game store, settings store, and engine stay concrete types.
  - A `RecordSync` port arrives with CloudKit (S7), which is not built. Its two implementations are
    the `CKSyncEngine` adapter in `ChessSync` and an in-memory fake that simulates two devices in
    tests. Record mapping and merge rules are pure functions in `ChessPlay`, tested without
    CloudKit.
  - An `Opponent` port (bot, local, Game Center) is added with Game Center matches (S6). Until then
    the opponent is an enum (`Opponent` in `ChessPlay`).
- **No hard-coding.** Tunable values and content are data in `ChessContent`: bots, Elo, colors,
  timings, strings, and asset names. Code holds only rules and mechanisms.
  - Rendering constants (animation durations, z-order) live in one theme value that is loaded from
    JSON.
  - A validation test checks every catalog (see Q5).
- **Compatibility code goes.** Delete it and do not gate it. This covers:
  - The deployment floor is iOS/iPadOS 17, tvOS 17, macOS 14. No `#available` check may gate an API
    at or below it.
  - The "legacy alias" colors, the zero-XCTest validation runner, `ObservableObject`, and
    `@Published` are removed.

### Localisation

- One catalog, owned by `ChessContent`
  (`Sources/ChessContent/Resources/Localization/<locale>.lproj/Localizable.strings` and
  `.stringsdict`), read through `Localization`. No UI text is written in Swift; views pass keys.
  This follows the OpenJoystickDriver pattern.
- `en-US` is the source language and the fallback (`defaultLocalization: "en-US"`). A key missing
  from a locale resolves to source English, then to the key.
- The other 82 locales, OpenJoystickDriver's list including `C`, start as full English copies and
  are translated later.
- Plurals use `%#@count@` with all six CLDR categories filled.
- English values use ASCII `...` and `'`, and no ASCII `"`.
- Adding or removing a key: edit `en-US.lproj`, then run `Tools/sync-localizations.sh`. It adds
  missing keys as English, drops removed keys, and keeps translations. `LocalizationTests` fails
  when a locale's keys differ from the source.
- `Tools/check-localizations.sh [-v]` lists stale English: a value in a non-English locale that is
  still identical to `en-US`. It also lists missing and obsolete keys. `en-*` and `C` are skipped.
  Keys that are the same in every language go in `Tools/localization-identical-keys.txt`. The script
  exits 1 while anything is untranslated, so it is a report, not a build gate.
- SwiftPM lowercases the `.lproj` names in the built bundle, and device file systems are
  case-sensitive, so every lookup matches locale names case-insensitively.

### Accounts

- **Sign-in is Game Center.** The local player is the app's identity. Planned: iCloud (the device
  account) carries sync. The app stores no passwords and runs no account server.
- **Chess.com is a separate, optional link.** The user enters a Chess.com username, which is stored
  in `AppSettings` on the device; `ChessComLink` reads that player's public profile, ratings, and
  games from `https://api.chess.com/pub/`. It is read-only and needs no credentials, because the
  PubAPI publishes this data to anyone.
- A real Chess.com sign-in (OAuth) needs Chess.com to approve the app (application form linked from
  the PubAPI page). Until then there is no Chess.com login and no token handling.
- Chess.com's terms for the PubAPI: serial requests (parallel ones may get HTTP 429), a User-Agent
  with contact information, and no reuse of Chess.com's brand, palettes, or artwork.
  `AppStore/AppleTVPrivacyPolicy.md` names these requests.

### Toolchain

- `// swift-tools-version: 6.1`.
- Platforms: `.iOS(.v17)`, `.tvOS(.v17)`, `.macOS(.v14)`. The user asked for the lowest floor the
  stack allows. Tools version 6.1 accepts lower versions, but two required APIs set this floor
  (checked in the iOS 26.5 SDK):
  - `Observation` (`@Observable` sessions): macOS 14, iOS 17, tvOS 17.
  - `CKSyncEngine` (CloudKit sync): macOS 14, iOS 17, tvOS 17.

  A lower floor would need an `ObservableObject` fallback and hand-written CloudKit sync, which is
  exactly the compatibility code this ADR removes.
- Liquid Glass (`glassEffect`) needs OS 26. It is a progressive enhancement behind one
  `#available(iOS 26, tvOS 26, macOS 26, *)` view modifier in `ChessUI`. The design must look
  finished without it on OS 17 and 18 (materials and standard controls).
- Tests use Swift Testing (`import Testing`). XCTest remains only for `KingsideUITests`, because
  Swift Testing cannot drive UI.
- Build with Xcode's Swift toolchain (`xcrun swift`, with `TOOLCHAINS` and `SDKROOT` unset). The
  README has the commands. The swiftly 6.3.3 toolchain fails in two ways:
  - It cannot link against the Command Line Tools' `MacOSX27.0.sdk` (`tapi error: ... unknown
    architecture arm64e.x1-macos`).
  - With `SDKROOT` pointed at Xcode's SDK, it links, but it lacks Apple's SwiftUI overlays, so
    `ChessUI` fails at `\.webAuthenticationSession` (checked 2026-09-30). The same `TOOLCHAINS`
    setting also breaks package resolution in `xcodebuild`.

### Assets

All assets must be non-proprietary. Allowed sources are below. Only the cburnett pieces, the five
procedural board themes (`harbor`, `cedar`, `heather`, `terracotta`, `graphite`), the synthesized
sound pack, and the Lichess puzzle data ship today; the other piece sets and the Kenney sounds are
allowed but not added.

| Asset | Source and license |
| --- | --- |
| Pieces (several selectable sets) | Cburnett under BSD 3-clause (all 12 Wikimedia files carry `{{self \| GFDL \| migration=relicense \| BSD \| GPL}}`, author Cburnett); lichess`rhosgfx` (CC0); Maurizio Monge's `fantasy`,`spatial`,`celtic` (MIT, `maurimo/chess-art`);`chessnut` (Apache-2.0) |
| Boards (several selectable themes) | Drawn procedurally in SpriteKit. Each theme is a JSON entry in `ChessContent` (square colors, highlight colors, coordinate style), so a new theme is data only. |
| Sound | Synthesized in code from `sound-packs.json` recipes (`LicenseRef-Kingside`, shipped). Kenney "UI Audio" and "Impact Sounds" (CC0) are allowed if needed. |
| Puzzles | Lichess puzzle database (CC0-1.0, shipped) |
| Font | SF Pro, or any SIL OFL font |
| Fallback glyphs | Unicode ♔–♟, rendered at runtime |

Rejected sources:

- GPL and AGPL piece sets, such as lichess `cburnett`-as-GPL, `merida`, `mono`, and `pixel`. They
  would impose copyleft on the app.
- NC and freeware sets, such as `horsey`, `california`, `alpha`, and `leipzig`. They do not allow
  commercial use.
- All lichess sounds. They are not clearly free.
- `totoy` and `papercut`. lila's COPYING.md contradicts their stated license.
- ChessCraft art. It is CC BY-SA 4.0 (share-alike), and part of it is AI-generated, so its copyright
  status is unclear.
- SF Symbols. There are no chess piece symbols, and Apple's license forbids using SF Symbols in app
  icons or logos.
- Assets from Apple's Chess.app. No license was found that permits reuse.

Every asset gets a license, source, and attribution entry in
`Sources/ChessContent/Resources/Catalogs/attributions.json` (shown under Settings > Licenses) and in
`ACKNOWLEDGEMENTS.md`. The S1 catalog test fails when a piece set or sound pack has no entry in
`attributions.json`.

## Alternatives rejected

| Alternative | Reason |
| --- | --- |
| Pure SwiftPM app with no Xcode target | SwiftPM cannot produce signed iOS or tvOS `.app` bundles, asset catalogs, or tvOS top-shelf assets. The thin app target is the unavoidable remainder. |
| XcodeGen or Tuist to generate the app target | Adds a tool and a manifest to maintain for a target that holds four files. Revisit if the app grows extensions. |
| One app module with folders | Folders cannot enforce layering. Today's coupling (`SoundEffects.shared` in game logic, SwiftUI in board state) came from this layout. |
| Board in SwiftUI `Canvas` or views | The user chose SpriteKit. SpriteKit also provides particles, actions, and shaders, and one scene works with focus, touch, and pointer. |
| Separate SpriteKit scenes per platform | Only input differs by platform. One scene with an input adapter per platform keeps a single renderer. |
| Ports for the store, settings, and engine now | Each has one implementation. A port without a second implementation adds indirection and catches no defects. |
| GameplayKit `GKMinmaxStrategist` for the bot | `ChessEngine` already exists and is tested by perft and mate tests. GameplayKit would add a second engine without a quality gain. |
| Services, a backend, or a network hop | Nothing needs independent deployment. Game Center is Apple's service, reached through GameKit. The optional Chess.com link calls Chess.com's public API directly; there is no Kingside server. |
| Chess.com OAuth sign-in now | Needs Chess.com's approval, which the project does not have. The public API covers profile, ratings, and game import without credentials. |
| Keep XCTest | The user moved to Swift Testing. XCTest stays only where Swift Testing cannot work (UI automation). |

## Quality scenarios

| # | Scenario and measure | Test or measurement | State |
| --- | --- | --- | --- |
| Q1 | Rules correctness. Perft counts match the reference: start position depth 4 = 197,281; kiwipete depth 3 = 97,862; positions 3 and 4 as well. | `EngineAdapterTests.perft` (12 cases) and `ChessRulesTests` | passing |
| Q2 | Frame cost. Applying a snapshot with a move animation keeps 60 fps on Apple TV 4K (3rd gen) and iPhone. A snapshot update takes under 2 ms of main-thread time. | S3: `BoardSceneTests` measures `BoardScene.apply(_:animated:)` with `ContinuousClock` on 1,000 alternating snapshots and expects a mean under 2 ms. The Instruments "SpriteKit" trace on the tvOS simulator is still to do. | apply passing (0.08–0.10 ms mean, debug build, Apple silicon Mac); frame trace not run |
| Q3 | Responsiveness. Engine search never runs on the main actor, and cancelling a search throws `CancellationError`. | `EngineAdapterTests.cancellationStopsSearch`. `ChessEngine` is an actor. | passing |
| Q4 | Portability. Every non-UI target builds for the iOS, iOS Simulator, tvOS Simulator, and macOS destinations. | `xcodebuild -scheme Kingside-Package -destination 'generic/platform=tvOS Simulator' build`, and the same for iOS Simulator, run from a copy of the package without `Kingside.xcodeproj` (otherwise `xcodebuild` picks the project), with `DEVELOPER_DIR` set to Xcode 27 (Xcode 26.6 lacks the 26.5 simulator runtimes here), and with `SDKROOT` and `TOOLCHAINS` unset | passing for all package targets, 2026-09-29 |
| Q5 | No hard-coding. Adding a bot, theme, or piece set changes only JSON and assets, never Swift. Catalog ids are unique, every referenced asset exists, and every asset has an attribution entry. | S1: `ChessContentTests.catalogsAreValid`. Planting a wrong default id, a wrong chat key, and a wrong piece extension made it fail with 14 issues. | passing |
| Q6 | Layering. No target imports a module outside its rules. | `Tools/check-imports.sh` exits 0. Tested with a planted `import SwiftUI` in `ChessCore`, which makes it exit 1. Also `swift build --explicit-target-dependency-import-check error`. | passing |
| Q7 | Persistence. Saved games survive a crash during a write (atomic replace). Data written by an older build still decodes. | `ChessPlayTests.PersistenceTests`, including a legacy `saved-games-v2.json` fixture, legacy settings, and legacy `@AppStorage` key migration | passing |
| Q8 | Accessibility. The SpriteKit board exposes 64 accessibility elements with a square name and its piece, and it is fully playable with VoiceOver, Switch Control, the Siri Remote, and a game controller. | S3: `BoardSceneTests` checks the 64 elements and their labels, and macOS press activation. `KingsideUITests` has two launch-to-board smoke tests. Whether `SKView` surfaces the elements to VoiceOver on iOS was not checked. | scene elements passing; VoiceOver check not done |
| Q10 | Sync convergence. Two devices that edit offline converge to the same saved games and puzzle progress after sync. Replaying the same record twice changes nothing. | S7: Swift Testing test with two stores on the in-memory `RecordSync` fake, plus a manual check with two simulators signed in to one iCloud account | planned S7 |
| Q11 | Durable saves on tvOS. Saved games survive the OS purging local storage on Apple TV. Apple's tvOS guidance calls app-local storage limited and purgeable; this was not verified in this session. | S7: delete the app's local data on the tvOS simulator, relaunch, and check that the archive is restored from CloudKit | planned S7 |
| Q9 | Engine speed does not regress. | `swift run -c release ChessBench` reports nodes per second. Compare against the last recorded run before merging engine changes. | baseline 2026-09-29, Apple silicon Mac, Swift 6.3.3 release build: 6,985,050 nodes in 2.94 s (2.38 M nodes/s) |

## Source of truth

| State | Authoritative writer | Readers or projections |
| --- | --- | --- |
| Current game (`ChessGame`) | `GameSession` in `ChessPlay`. Its `apply(_ intent:)` is the only mutation point. | `BoardSnapshot` → SpriteKit nodes, SwiftUI panels |
| Board focus and selection | Interaction state in `ChessPlay` | SpriteKit focus ring and highlights |
| Clock | `GameSession`'s clock, driven by an injected `Clock` | UI labels |
| Settings | `SettingsStore`, UserDefaults key `Kingside.settings.v1` | Scene theme, feedback volume |
| Last bot and colour chosen | `SettingsStore`. The old `@AppStorage` keys `Kingside.playBots.botID` and `Kingside.playBots.color` are migrated from. | Play Bots screen |
| Puzzle progress | `PuzzleProgressStore`, key `Kingside.puzzleProgress.v1`. Synced from S7. Merge: the rating and streaks are taken from the newest modification; seen and solved puzzle sets are unioned. | Puzzle screens |
| Saved and unfinished games | `GamePersistenceStore` actor, file `saved-games-v2.json` in Application Support. It is the only writer on each device. From S7 it is synced through `RecordSync` to the CloudKit private database, one record per `SavedGame.id` (UUID). Merge: finished games are immutable, so the union by id wins; for the unfinished game the newest modification wins. | Archive, Review, Continue |
| Settings | Per device, not synced: a TV and a phone need different board and input settings. | |
| Content catalogs | Read-only resources of `ChessContent` | Everything |
| Linked Chess.com username | `SettingsStore`, per device. Chess.com data is fetched on demand and cached in memory by `ETag`; imported games become ordinary saved games. | Account screen, archive |
| Game Center sign-in state | GameKit (Apple), read by `GameCenterAccount` in `ChessOnline`. | Account screen |
| Game Center match state (planned, S6) | GameKit (Apple). `ChessOnline` will project turns into `GameSession`. | |

## Platform matrix

| Capability | iOS / iPadOS | tvOS | macOS |
| --- | --- | --- | --- |
| Board input | Touch and drag, pointer, game controller | Siri Remote focus, game controller | Pointer and drag, keyboard, game controller |
| Haptics | Core Haptics, where supported | none (the controller's haptics are optional) | none |
| Navigation | `TabView` of navigation stacks | `TabView` of navigation stacks | `NavigationSplitView` with a sidebar |
| Game Center | sign-in (matches planned) | sign-in (matches planned) | sign-in (matches planned) |

## Slices

Each slice leaves the app building, with its tests passing and `Tools/check-imports.sh` exiting 0.

| Slice | Work | Status |
| --- | --- | --- |
| S0 | This ADR. Tools version 6.1 and iOS 17 / tvOS 17 / macOS 14 platforms. `ChessCore` tests moved to Swift Testing. Import rules and checker. The validation runner is replaced by `ChessBench`. | done |
| S1 | Create `ChessContent`: move the bots, themes, puzzles, and time controls from Swift to JSON; add the catalog validation test. | done |
| CL | Create `ChessComLink`: the Chess.com PubAPI client and PGN import. The Link Chess.com screen is in `ChessUI`. | done |
| S2 | Create `ChessPlay`: turn `GameViewModel` into an `@Observable` `GameSession`; add the `FeedbackSink` port; move `KingsideTests` to Swift Testing. | done |
| S3 | Create `ChessBoardScene`: the SpriteKit board and its accessibility. Piece art ships as vector PDF, rasterized per square size through `CGPDFDocument`; `Tools/convert-piece-art.sh` regenerates it from the SVG sources in `Artwork/Pieces/`. | done |
| S4 | Create `ChessFeedback`: sound, haptics, and controllers. Sound is synthesized from the `sound-packs.json` recipes; haptic patterns, event cues, and controller repeat timing are in `haptics.json`. | done |
| S5 | Create `ChessUI`: the HIG redesign and the multiplatform thin app target; delete the old `Kingside/` folders. Add a Licenses screen that shows the notices from `attributions.json` and `Sources/ChessContent/Resources/Licenses/` (BSD clause 2 requires the notice in the distribution). | done |
| S6 | `ChessOnline`: GameKit and the opponent port. `ChessOnline` exists with Game Center sign-in only; matches and the port are not built. | partly done |
| S7 | `ChessSync`: CloudKit sync through `CKSyncEngine` and the `RecordSync` port. No code and no CloudKit entitlement yet. | planned |

## Open decisions

| Decision | Who decides | Default if nobody decides |
| --- | --- | --- |
| Default piece set and board theme for first launch | User | Cburnett pieces, `harbor` board (sea-green-grey on stone). The old green/cream, brown, icy-blue and purple palettes were removed because they resemble Chess.com's. |
| Project license | User. The synthesized sound pack's attribution says `LicenseRef-Kingside` until the repository has a `LICENSE`. There is no `LICENSE` file yet. | Unset |
| iCloud container and Game Center setup | User (paid Apple Developer account). A setup guide, `docs/setup/apple-services.md`, is planned with S6 and S7 and does not exist yet. It covers the App ID capabilities, the `iCloud.io.github.xsyetopz.Kingside` container (app ID `io.github.xsyetopz.Kingside`, team `9PQP6CDMQT`), the App Store Connect record for Game Center, and signing and notarization. | Code for S6 and S7 is built and tested against fakes; the user enables the services from the guide |
| Whether StoreKit is needed | User | Not built |
| Thin Xcode target vs. XcodeGen | User | Thin Xcode target |
