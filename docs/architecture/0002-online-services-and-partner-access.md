# ADR 0002: Online services, Chess.com partner access, and Lichess play

- Status: accepted. Lichess play is built; the open items below are not yet checked.
- Date: 2026-09-30

## Context

Kingside is a proprietary, closed-source app in a private repository. It plays like a modern online
chess service, but it is not affiliated with or endorsed by Chess.com. Users want to sign in and
play real games online. The repository stays private, and no part of the app is open source.

A client that only sends legal moves does not cheat, because the server enforces the rules. But
whether a client may connect at all depends on the service's terms, not on the moves it sends.

### Chess.com (checked 2026-09-30)

- The [Published-Data API](https://www.chess.com/news/view/published-data-api) is read-only: "You
  cannot send game-moves or other commands to Chess.com from this system." It has no login.
- Login and board access are partner-only. [Chess.com
  support](https://support.chess.com/en/articles/9650547-published-data-api) says: "If you are
  interested in building an app or service for members of Chess.com and would like to authenticate
  users, access public user data, or set up a connected board, please fill out this form". There
  is no self-service OAuth. The form is drafted in `docs/partners/chess-com-oauth-request.txt`.
- The [User Agreement](https://www.chess.com/legal/user-agreement), section 4.C: "You agree not to
  access the Service by any means other than through the interface that is provided by Chess.com
  for use in accessing the Service." The same section forbids reverse engineering the Services and
  using bots or scrapers to retrieve data.
- User Agreement, section 2.B: "You agree not to display or use our trademarks in any manner without
  our prior permission."
- Risks of any other route: Chess.com can ban the users' accounts and block the app, and it can
  change its private protocol at any time, which breaks the app.

### App Store (checked 2026-09-30)

From the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/):

- 5.2.2: "If your app uses, accesses, monetizes access to, or displays content from a third-party
  service, ensure that you are specifically permitted to do so under the service's terms of use.
  Authorization must be provided upon request."
- 5.2.1: "Don't use protected third-party material such as trademarks … without permission, and
  don't include misleading, false, or copycat representations, names, or metadata".
- 4.1(c): "You cannot use another developer's icon, brand, or product name in your app's icon or
  name, without approval from the developer."
- 4.8: a third-party login needs an equivalent private login option, except when "Your app is a
  client for a specific third-party service and users are required to sign in to … [that]
  third-party account directly to access their content." Game Center is the app's own sign-in.

### Lichess (checked 2026-09-30)

From the [API spec](https://github.com/lichess-org/api) and the
[terms](https://lichess.org/terms-of-service):

- The Board API is for "physical boards and third-party clients. Works with normal Lichess accounts.
  Engine play or assistance is forbidden."
- Public seeks: "Rapid, Classical and Correspondence only. For direct challenges, games vs AI, and
  bulk pairing, Blitz is also possible." Bullet is not confirmed.
- OAuth is authorization code with PKCE (`S256`). Unregistered public clients choose any unique
  `client_id`. Tokens last about one year, with no refresh tokens. Scopes: `board:play`,
  `challenge:read`, `challenge:write`.
- Only one event stream (`/api/stream/event`) per token can be open. Make one request at a time.
  After a `429`, wait at least a minute.
- The terms allow "personal or commercial use, such as in your own applications". They require no
  open source code and no free app.
- There is no device-authorization flow, so tvOS cannot sign in by browser. Personal access tokens
  are the documented fallback.

## Decision

1. **The repository and the app stay proprietary.** Do not publish the source, and do not add an
   open-source license.
1. **Chess.com: official interfaces only.** Kingside uses the Published-Data API (`ChessComLink`)
   and nothing else until Chess.com approves partner access in writing:
   - Use no private or undocumented endpoints, no scraping, no web-view login, and no reverse
     engineering of the Chess.com site or apps.
   - Use no Chess.com logo, icon, colors, or artwork. Name Chess.com only in plain text, where it
     says which account is linked. Keep the "not affiliated" statement in the README and the store
     metadata.
   - Keep all Chess.com code in `ChessComLink`, behind the same kind of port that other online
     services use. Then an approved OAuth or play client replaces the read-only client without
     changing the screens.
   - Keep the approval email, because App Review can ask for it under 5.2.2.
1. **Online play uses the Lichess Board API** with PKCE sign-in (`LichessLink`).
   - Online play goes through a service-neutral port (`OnlineGameConnection`), so Chess.com can be a
     second provider later. `LichessGameConnection` is the Lichess adapter.
   - During a Lichess game, disable hints, engine evaluation, and any other move help. Lichess
     forbids "any kind of outside help". `OnlineGameSession` has no engine, and hint and takeback do
     nothing in it. Game Review stays available after the game ends, and finished games are saved to
     the archive.
   - Offer the time controls that Lichess allows for each path: seeks for Rapid and Classical, and
     challenges for Blitz, Rapid, and Classical. The app offers no Bullet.
   - Scopes are `board:play`, `challenge:read`, and `challenge:write`. The client id and redirect
     URI (a custom URL scheme) are in `services.json`.
   - Send one request at a time, and block all requests for 60 seconds after a `429`. Open one event
     stream per token: `LichessAccountModel` owns it.
   - Send a `User-Agent` built from the `contact` value in `services.json`.
   - Store the token in the Keychain as a synchronizable item (`KeychainTokenStore`). On iOS,
     iPadOS, and macOS, sign in with `ASWebAuthenticationSession`. On tvOS, which has no browser
     sign-in, use the token synced through iCloud Keychain, or a personal access token that the user
     pastes.
   - In-game chat is on by default and can be turned off (`chatEnabled`). Incoming lines pass a
     local word list (`chat-filter.json`), the user can mute the opponent, and a link opens the
     Lichess report page. Lichess moderates chat on its side.
1. **The App Privacy answer is "Data Not Collected".** `NSPrivacyCollectedDataTypes` in
   `Kingside/Resources/PrivacyInfo.xcprivacy` stays empty. Apple's [App privacy
   details](https://developer.apple.com/app-store/app-privacy-details/) (checked 2026-09-30) say:
   - "'Collect' refers to transmitting data off the device in a way that allows you and/or your
     third-party partners to access it for a period longer than what is necessary to service the
     transmitted request in real time."
   - "'Third-party partners' refers to analytics tools, advertising networks, third-party SDKs, or
     other external vendors whose code you've added to your app."

   The developer runs no server, and the app contains no code from Lichess or Chess.com. Moves,
   chat, and usernames go from the device to the service that the user signs in to, under that
   service's privacy policy, so the developer never has access to them. Apple does not rule on
   this case directly; this is a reading of the definitions. Revisit the answer if the app adds a
   third-party SDK, a developer server, or any other path by which the developer can read user
   data.

## Consequences

- A user can link Chess.com for read-only data only. Online play is on Lichess.
- Signing in to Lichess or Chess.com does not replace Game Center, which stays the app's own
  account (4.8).

## Open items

- Chess.com and Lichess ask for a contact in the User-Agent. The contact is `contact` in
  `Sources/ChessContent/Resources/Catalogs/services.json` and is still `CONTACT_EMAIL_PLACEHOLDER`.
  Replace it with a contact email address.
- Check that Lichess accepts the custom URL scheme as the redirect URI with
  `ASWebAuthenticationSession`. This has not been tried against Lichess.
- Check on a signed build that iCloud Keychain syncs the token to Apple TV.
- Check the endpoints and fields that are guessed, not confirmed against Lichess:
  the `id` in the response to a challenge against the AI (`challengeAI`, which no screen uses yet),
  the claim-victory path, the challenge accept, decline, and cancel paths, and `access_token` in the
  token response.
- Check the 140-character chat limit. It is the limit Lichess is believed to enforce
  (`OnlineChat.maxLength`).
- Review the word list in `chat-filter.json` (imported from LDNOOBW) before release.
- Find the rules for the Lichess name and logo in app UI.
- Check whether Board API challenges allow bullet. The app offers none.
