import ChessContent
import SwiftUI

/// Asks for a Chess.com username and links it once the profile exists.
struct ChessComLinkScreen: View {
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  @Environment(\.dismiss)
  private var dismiss
  @State
  private var username = ""
  @State
  private var failure: ChessComFailure?
  @State
  private var isChecking = false

  private var trimmed: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    Form {
      ScreenHeading(title: localization("account.chessCom.link")).listRowBackground(Color.clear)
      Section {
        TextField(localization("account.chessCom.username"), text: $username)
          .autocorrectionDisabled()
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
          .onSubmit(link)
      } footer: {
        VStack(alignment: .leading) {
          if let failure {
            Text(localization(failure.messageKey)).foregroundStyle(.red)
          }
          Text(localization("account.chessCom.privacy"))
        }
      }
      Section {
        Button(action: link) {
          if isChecking {
            ProgressView().frame(maxWidth: .infinity)
          } else {
            Text(localization("account.chessCom.link.confirm")).frame(maxWidth: .infinity)
          }
        }
        .disabled(trimmed.isEmpty || isChecking)
      }
    }
    .readableRows(model.catalog.interface)
    .screenTitle(localization("account.chessCom.link"), chrome: .pushed)
  }

  private func link() {
    guard !trimmed.isEmpty, !isChecking else { return }
    isChecking = true
    failure = nil
    Task {
      failure = await model.chessComAccount.link(username: trimmed)
      isChecking = false
      if failure == nil { dismiss() }
    }
  }
}
