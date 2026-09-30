import AuthenticationServices
import ChessContent
import LichessLink
import SwiftUI

/// The Lichess sign-in on the Account screen.
struct LichessAccountSection: View {
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  #if !os(tvOS)
    @Environment(\.webAuthenticationSession)
    private var webAuthenticationSession
  #endif
  /// The browser sign-in is open, or its code is being exchanged.
  @State
  private var isAuthorizing = false
  /// A failure from before the model has a token to check.
  @State
  private var flowFailure: LichessFailure?
  #if os(tvOS)
    @State
    private var token = ""
  #endif

  private var account: LichessAccountModel { model.lichess }

  var body: some View {
    Section {
      content
    } header: {
      Text(localization("account.lichess.title"))
    }
  }

  @ViewBuilder
  private var content: some View {
    if isAuthorizing {
      progress
    } else {
      switch account.phase {
      case .signedOut:
        if let flowFailure { failure(flowFailure) } else { signedOutDetail }
        signInControls
      case .signingIn:
        progress
      case .signedIn(let username):
        Label(
          localization.string("account.lichess.signedIn.detail", username),
          systemImage: "checkmark.circle.fill"
        )
        Button(localization("account.lichess.signOut"), role: .destructive) {
          Task { await account.signOut() }
        }
      case .failed(let reason):
        failure(flowFailure ?? reason)
        signInControls
      }
    }
  }

  private var progress: some View {
    Label {
      Text(localization("account.lichess.signingIn.detail"))
    } icon: {
      ProgressView()
    }
  }

  private var signedOutDetail: some View {
    Text(localization("account.lichess.signedOut.detail"))
  }

  private func failure(_ reason: LichessFailure) -> some View {
    Text(localization(reason.messageKey))
  }

  private var isRetry: Bool {
    if case .failed = account.phase { return true }
    return flowFailure != nil
  }

  #if os(tvOS)
    @ViewBuilder
    private var signInControls: some View {
      Text(localization("account.lichess.tv.appleAccount"))
      Button(localization("account.lichess.tv.checkAgain"), systemImage: "arrow.clockwise") {
        Task { await account.start() }
      }
      Text(localization("account.lichess.tv.token.title")).font(.headline)
      Text(LichessSignIn.tokenCreationURL(baseURL: model.catalog.services.lichess.baseURL))
        .font(.footnote.monospaced())
        .foregroundStyle(.secondary)
      SecureField(localization("account.lichess.tv.token.field"), text: $token)
      Button(localization("account.lichess.tv.token.signIn"), systemImage: "key") {
        let pasted = token
        token = ""
        Task { await account.signIn(token: pasted) }
      }
      .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
  #else
    private var signInControls: some View {
      Button(
        localization(isRetry ? "common.retry" : "account.lichess.signIn"),
        systemImage: isRetry ? "arrow.clockwise" : "person.crop.circle.badge.checkmark"
      ) {
        signIn()
      }
    }

    /// Opens Lichess in the system browser session, then trades the returned code for a token.
    private func signIn() {
      guard !isAuthorizing else { return }
      isAuthorizing = true
      flowFailure = nil
      Task {
        defer { isAuthorizing = false }
        do {
          let oauth = model.lichessOAuth
          let verifier = try LichessOAuth.makeVerifier()
          let state = try LichessOAuth.makeState()
          let url = oauth.authorizeURL(
            state: state,
            challenge: LichessOAuth.challenge(for: verifier)
          )
          let callback = try await webAuthenticationSession.authenticate(
            using: url,
            callbackURLScheme: model.catalog.services.lichess.redirectURI.scheme ?? "",
            preferredBrowserSession: .shared
          )
          switch LichessSignIn.code(from: callback, expectedState: state) {
          case .success(let code):
            await account.signIn(token: try await oauth.exchange(code: code, verifier: verifier))
          case .failure:
            flowFailure = .unauthorized
          }
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
          // The player closed the sign-in: back to signed out, with no message.
        } catch {
          flowFailure = LichessFailure(error)
        }
      }
    }
  #endif
}
