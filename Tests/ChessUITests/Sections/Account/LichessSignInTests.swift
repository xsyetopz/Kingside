import Foundation
import Testing
@testable import ChessUI

@Suite
struct LichessSignInTests {
  @Test
  func buildsThePersonalTokenAddress() {
    #expect(
      LichessSignIn.tokenCreationURL(baseURL: URL(string: "https://lichess.org")!)
        == "https://lichess.org/account/oauth/token/create?scopes[]=board:play&scopes[]=challenge:read&scopes[]=challenge:write&description=Kingside"
    )
  }
}
