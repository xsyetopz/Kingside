import Foundation
import Testing
@testable import ChessUI

@Suite struct LichessSignInTests {
    private func code(_ query: String, state: String = "s1") -> Result<String, LichessSignIn.CallbackFailure> {
        LichessSignIn.code(from: URL(string: "io.github.xsyetopz.kingside://oauth?\(query)")!, expectedState: state)
    }

    @Test func returnsTheCodeWhenStateMatches() {
        #expect(code("code=abc&state=s1") == .success("abc"))
    }

    @Test func rejectsAWrongOrMissingState() {
        #expect(code("code=abc&state=other") == .failure(.stateMismatch))
        #expect(code("code=abc") == .failure(.stateMismatch))
    }

    @Test func reportsAnErrorParameter() {
        #expect(code("error=access_denied&state=s1") == .failure(.denied))
        // A forged error does not get past the state check.
        #expect(code("error=access_denied&state=x") == .failure(.stateMismatch))
    }

    @Test func rejectsAMissingOrEmptyCode() {
        #expect(code("state=s1") == .failure(.missingCode))
        #expect(code("code=&state=s1") == .failure(.missingCode))
    }

    @Test func buildsThePersonalTokenAddress() {
        #expect(
            LichessSignIn.tokenCreationURL(baseURL: URL(string: "https://lichess.org")!)
                == "https://lichess.org/account/oauth/token/create?scopes[]=board:play&scopes[]=challenge:read&scopes[]=challenge:write&description=Kingside")
    }
}
