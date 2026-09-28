# ChessTV Architecture

## Dependency direction

```text
SwiftUI Features ──> View models ──> ChessCore
       │                    │             ▲
       │                    ├──> ChessEngine
       │                    ├──> GamePersistenceStore
       │                    └──> ChessAPI / GameService
       └──> BoardInteractionController
```

`ChessCore` has no dependency on SwiftUI, UIKit, GameController, URLSession, or persistence. A position is a value; applying a move returns a new value. This makes search, PGN replay, persistence snapshots, and tests deterministic.

## Chess rules

`ChessPosition` owns piece placement, side to move, castling rights, en-passant target, and move counters. Move generation has two stages:

1. Piece-specific pseudo-legal generation, including castling and en passant.
2. Apply each candidate to a copy and remove moves that leave the moving king attacked.

Attack detection is independent of legal-move generation, avoiding recursion and correctly handling pinned pieces and castling transit squares. `ChessGame` layers SAN history and undo on top of positions.

## Board input and focus

`ChessBoardView` is one focusable view. `BoardInteractionController` owns exactly the board interaction state:

- `focusedSquare`
- `selectedSquare`
- `legalMoves`

Remote and game-controller input both call the same directional/select/cancel methods. Focus cannot leak into side controls while the user navigates squares because squares are rendered shapes, not separate buttons. Modal overlays establish explicit initial focus; dismissing them reveals the still-focused board.

The board renderer derives square coordinates from orientation and uses stable render identities to animate movement and capture removal. Chess state remains authoritative in `ChessPosition`.

## Local game lifecycle

`GameViewModel` is main-actor isolated because it publishes UI state. It starts an independent clock task and calls `ChessEngine` asynchronously. Position equality rejects stale engine results after undo/restart, and cancellation stops obsolete searches. Game snapshots are written atomically by the `GamePersistenceStore` actor.

`LocalGameService` demonstrates the backend-ready contract. A future `RemoteGameService` can emit the same `GameEvent` stream without changing the board or game screen.

## Computer engine

`NativeSearchEngine` is an actor-backed deterministic negamax/alpha-beta implementation with depth-based difficulty. It is the default offline engine.

`StockfishEngine` is an adapter around `StockfishBridge`. A reviewed embedded implementation supplies FEN/UCI transport and evaluation while the UI continues to depend only on `ChessEngine`. Search never runs on the main actor.

## Persistence

- `SettingsStore`: small user preferences in `UserDefaults`.
- `GamePersistenceStore`: versionable Codable snapshots in Application Support, written atomically; retains the latest 50 games.
- Public Chess.com username: a non-secret preference in `UserDefaults`.
- Future OAuth access/refresh tokens: Keychain only, after authorized integration.

## Networking

`HTTPClient` isolates URLSession and makes API decoding testable. `ChessComAPIClient` uses documented `/pub` endpoints only, supplies an identifiable user agent, maps HTTP failures to user-safe errors, supports task cancellation, and retries once only for transient conditions. SwiftUI never creates URL requests.

## Testing strategy

- `ChessCoreTests`: legal movement, captures, check/mate/stalemate, castling, en passant, promotion, pins, discovered/double check, king safety, FEN, SAN/PGN.
- `ChessTVTests`: API decoding/error mapping and persistence round trips.
- `ChessTVUITests`: home focus navigation, starting a game, remote board movement/select, overlays, and returning from screens.
- `ChessCoreValidation`: a zero-XCTest smoke runner for restricted machines.

Perft suites, repetition/insufficient-material draws, richer clock controls, Keychain-backed approved OAuth, and a GPL-reviewed embedded Stockfish bridge are logical next increments.
