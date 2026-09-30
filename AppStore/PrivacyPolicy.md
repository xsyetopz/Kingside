# Kingside Privacy Policy

Kingside is designed to keep local play local.

## Information stored on your device

Kingside stores your saved and finished games, puzzle progress, and application preferences on the
device (Apple TV, iPhone, iPad, or Mac) so games can be resumed and reviewed. This information is
not uploaded to the developer and can be removed by deleting the application.

## Game Center

You can sign in to Game Center from the Account screen; the app works without it. Game Center is an
Apple service, and Apple handles your Game Center account under Apple's privacy policy. Kingside
uses GameKit to ask Apple whether you are signed in and to read your Game Center display name, which
it shows on the Account screen. Kingside does not send this information to the developer.

## Chess.com link (optional)

You can link a Chess.com account from the Account screen. Kingside stores only the public Chess.com
username that you type, on your device. It does not ask for a Chess.com password and does not use
Chess.com sign-in.

When a Chess.com account is linked, Kingside sends requests to Chess.com's public API
(`https://api.chess.com/pub/`) to read that player's public profile, ratings, and recent games. You
can import those games into the archive on your device. Chess.com receives the username and your
device's IP address with each request and handles them under [Chess.com's privacy
policy](https://www.chess.com/legal/privacy). Unlinking
removes the stored username.

## Lichess sign-in (optional)

You can sign in to Lichess from the Account screen to play online; the app works without it. On
Apple TV you either use a sign-in that iCloud Keychain syncs from another of your devices, or paste
a Lichess personal access token. Kingside does not see your Lichess password.

Kingside stores the Lichess access token in the Keychain on your device. It is a synchronizable
Keychain item, so iCloud Keychain can copy it to your other devices. Signing out asks Lichess to
revoke the token and deletes it from the Keychain.

While you are signed in, Kingside sends your moves, resign, draw, and other game actions, chat
messages, and the settings of the games you seek or challenge (time control, rated or casual, and
the opponent's username) to Lichess (`https://lichess.org`) under your account. Each request also
carries the app name, version, and a contact address in the `User-Agent`, and Lichess receives your
device's IP address. Lichess handles this data under [Lichess's privacy
policy](https://lichess.org/privacy). Kingside saves your
finished online games to the archive on your device. You can turn chat off in Settings.

## Network access

Games, bots, puzzles, and Game Review run on the device without an internet connection. Kingside
makes network requests only for Game Center sign-in (through Apple), to the Chess.com public API if
you link a Chess.com account, and to Lichess if you sign in to Lichess. The developer runs no server
and collects no data.

## Tracking and advertising

Kingside does not include advertising, behavioral tracking, or third-party analytics SDKs. It does
not sell personal information.

## Contact

Before submission, replace this section with the developer’s public support email or support
website.

Last updated: September 30, 2026
