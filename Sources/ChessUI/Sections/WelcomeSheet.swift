import ChessContent
import SwiftUI

/// Shown once at first launch: the app, and the two accounts it can use.
struct WelcomeSheet: View {
  /// Called after the sheet is done, when the player chose to link Chess.com.
  let onLinkChessCom: () -> Void
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    let style = model.catalog.interface
    VStack(spacing: style.sectionGap) {
      VStack(spacing: style.gap) {
        Image(systemName: "checkerboard.rectangle")
          .font(.system(size: style.account.welcomeIconSize))
          .foregroundStyle(.tint)
          .accessibilityHidden(true)
        Text(localization("app.name")).font(.largeTitle.bold())
        Text(localization("account.welcome.pitch"))
          .multilineTextAlignment(.center)
          .foregroundStyle(.secondary)
      }
      VStack(spacing: style.gap) {
        Button {
          model.finishWelcome()
          model.gameCenter.authenticate()
        } label: {
          Label(localization("account.welcome.signIn"), systemImage: "gamecontroller")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        Button {
          model.finishWelcome()
          onLinkChessCom()
        } label: {
          Label(localization("account.chessCom.link"), systemImage: "link")
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        Button(localization("account.welcome.notNow")) { model.finishWelcome() }
      }
    }
    .padding(style.sectionGap)
    .interactiveDismissDisabled()
  }
}
