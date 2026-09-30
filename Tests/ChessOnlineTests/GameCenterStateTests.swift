import Foundation
import GameKit
import Testing
@testable import ChessOnline

@Suite
struct GameCenterStateTests {
  private func resolve(
    authenticated: Bool = false,
    screen: Bool = false,
    error: (any Error)? = nil
  ) -> GameCenterState {
    GameCenterState.resolve(
      isAuthenticated: authenticated,
      displayName: "Magnus",
      needsUserInterface: screen,
      error: error
    )
  }

  private func gameKitError(_ code: GKError.Code) -> NSError {
    NSError(
      domain: GKError.errorDomain,
      code: code.rawValue,
      userInfo: [NSLocalizedDescriptionKey: "Not allowed"]
    )
  }

  @Test
  func authenticatedPlayerIsSignedIn() {
    #expect(resolve(authenticated: true) == .signedIn(displayName: "Magnus"))
    #expect(resolve(authenticated: true, screen: true) == .signedIn(displayName: "Magnus"))
  }

  @Test
  func signInScreenMeansSigningIn() {
    #expect(resolve(screen: true) == .signingIn)
  }

  @Test
  func noPlayerAndNoScreenIsSignedOut() {
    #expect(resolve() == .signedOut)
  }

  @Test
  func cancelledSignInIsSignedOut() {
    #expect(resolve(error: gameKitError(.cancelled)) == .signedOut)
  }

  @Test
  func gameKitErrorsMapToTheReasonThePlayerCanActOn() {
    #expect(resolve(error: gameKitError(.parentalControlsBlocked)) == .unavailable(.restricted))
    #expect(resolve(error: gameKitError(.underage)) == .unavailable(.restricted))
    #expect(resolve(error: gameKitError(.communicationsFailure)) == .unavailable(.offline))
    #expect(resolve(error: gameKitError(.gameUnrecognized)) == .unavailable(.notSetUp))
    #expect(resolve(error: gameKitError(.unknown)) == .unavailable(.other))
  }

  @Test
  func networkErrorIsOffline() {
    #expect(resolve(error: URLError(.notConnectedToInternet)) == .unavailable(.offline))
  }

  @Test
  func errorOutsideGameKitAndTheNetworkIsOther() {
    #expect(resolve(error: CocoaError(.fileNoSuchFile)) == .unavailable(.other))
  }
}
