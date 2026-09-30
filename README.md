# Kingside

[English](README.md) | [اردو](README.ur.md)

Kingside is a chess app for iPhone, iPad, Mac, and Apple TV. Play bots or a friend, play online on
Lichess, solve puzzles, and review your games. Kingside is not affiliated with or endorsed by
Chess.com.

## Features

- **Play Bots**: original bot personalities from 250 to 2200 Elo, grouped Beginner, Intermediate,
  Advanced, and Master, that comment on the game
- **Pass and Play**: two players on one device with bullet, blitz, rapid, or untimed clocks and an
  optional automatic board flip
- **Play Online**: sign in to Lichess to seek a game, challenge a friend, accept challenges, and
  resume ongoing games. Online games have no hints, takebacks, or engine help. You can turn chat
  off in Settings
- **Puzzles**: rated puzzles, Puzzle Rush (3 Minutes, 5 Minutes, Survival), and a Daily Puzzle
- **Game Review**: accuracy, move classifications from brilliant to blunder, an evaluation graph,
  and the best line
- **Games**: your finished games, saved on the device, each one ready to review
- **Account**: Game Center sign-in, an optional read-only Chess.com link that shows your public
  ratings and imports your recent games, and an optional Lichess sign-in
- Resign, draw offers, takeback, hints, and board flip in games against bots and in Pass and Play
- An unfinished game is restored the next time you open the app
- Board themes, and options for legal-move dots, coordinates, last-move highlight, move animation,
  auto-promotion to a queen, sound, and haptics
- English, plus 71 other languages that are machine-translated and not yet reviewed by native
  speakers

## Devices

| Device | Requires |
| --- | --- |
| iPhone and iPad | iOS or iPadOS 17 or later |
| Mac | macOS 14 or later |
| Apple TV | tvOS 17 or later |

## Controls

- **iPhone and iPad**: tap a piece, then tap its destination, or drag the piece.
- **Mac**: click or drag, or use the arrow keys to move the cursor, Return or Space to select, and
  Escape to cancel.
- **Apple TV**:

| Action | Siri Remote | Game controller |
| --- | --- | --- |
| Move the board cursor | Touch surface | D-pad or left stick |
| Select a piece or square | Select | A |
| Cancel or close a menu | Back | B |

## Privacy

Bots, Pass and Play, puzzles, and Game Review work offline. Kingside connects to the internet only
for Game Center sign-in, the optional Chess.com link, and the optional Lichess sign-in and online
play. The developer runs no server and collects no data. Details are in the
[privacy policy](AppStore/PrivacyPolicy.md).

## Build from source

1. Install Xcode 26 or later.
1. Open `Kingside.xcodeproj`, choose the `Kingside` scheme, and pick an iPhone, iPad, Mac, or
   Apple TV destination.
1. To run on your own device, set your development team and a bundle identifier of your own under
   Signing & Capabilities.
1. Press **Command-R**.

## Credits

The chess pieces are the cburnett set (BSD 3-Clause), and the puzzles come from the Lichess puzzle
database (CC0). Full notices are in [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md) and in the app under
Settings > Licenses.
