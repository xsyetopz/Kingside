import ChessComLink
import ChessContent
import ChessOnline
import SwiftUI

/// The Account tab: the Game Center and Lichess sign-ins, and the optional read-only Chess.com
/// link.
struct AccountHome: View {
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  @State
  private var chessCom: ChessComAccountModel?

  private var linkedUsername: String? { model.settings.value.chessComUsername }

  var body: some View {
    WidthAdaptive {
      list
    } wide: {
      // As in Settings: the artwork beside the list, which keeps a readable width.
      let style = model.catalog.interface
      HStack(alignment: .top, spacing: style.sectionGap) {
        badge(side: style.home.heroThumbnailSize * style.platformScale)
          .padding(.top, style.sectionGap)
        list.frame(maxWidth: style.home.formMaxWidth * style.platformScale)
      }
      .padding(.leading, style.sectionGap)
      .frame(maxWidth: .infinity)
    }
    .screenTitle(localization("section.account.title"))
    .task(id: linkedUsername) {
      guard let name = linkedUsername else {
        chessCom = nil
        return
      }
      let account = ChessComAccountModel(
        username: name,
        client: model.chessCom,
        gameLimit: model.catalog.interface.account.recentGamesLimit
      )
      chessCom = account
      await account.load()
    }
  }

  private var list: some View {
    List {
      GameCenterSection()
      LichessAccountSection()
      if let linkedUsername, let chessCom, chessCom.username == linkedUsername {
        ChessComLinkedSections(account: chessCom)
      } else if linkedUsername == nil {
        ChessComNotLinkedSection()
      }
    }
    .iconColumnLabels(model.catalog.interface)
  }

  /// The account symbol and the name the player is known by: Game Center's, else Chess.com's.
  private func badge(side: Double) -> some View {
    var name = linkedUsername
    if case .signedIn(let displayName) = model.gameCenter.state { name = displayName }
    return VStack(spacing: model.catalog.interface.gap) {
      Image(systemName: "person.crop.circle.fill")
        .font(.system(size: side / 2))
        .foregroundStyle(.tint)
      if let name {
        Text(name).font(.title2.bold()).lineLimit(1)
      }
    }
    .frame(width: side)
    .accessibilityElement(children: .combine)
  }
}

private struct GameCenterSection: View {
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization

  var body: some View {
    Section(localization("account.gameCenter.title")) {
      switch model.gameCenter.state {
      case .signedOut:
        Text(localization("account.gameCenter.signedOut.detail"))
        Button(
          localization("account.gameCenter.signIn"),
          systemImage: "person.crop.circle.badge.checkmark"
        ) {
          model.gameCenter.authenticate()
        }
      case .signingIn:
        Label {
          Text(localization("account.gameCenter.signingIn.detail"))
        } icon: {
          ProgressView()
        }
      case .signedIn(let displayName):
        Label(
          localization.string("account.gameCenter.signedIn.detail", displayName),
          systemImage: "checkmark.circle.fill"
        )
        Button(localization("account.gameCenter.open"), systemImage: "gamecontroller") {
          model.gameCenter.openDashboard()
        }
      case .unavailable(let reason):
        VStack(alignment: .leading) {
          Text(localization("account.gameCenter.unavailable.title"))
          Text(localization(AccountLayout.gameCenterDetailKey(reason)))
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
      }
    }
  }
}

private struct ChessComNotLinkedSection: View {
  @Environment(\.localization)
  private var localization

  var body: some View {
    Section {
      Text(localization("account.chessCom.notLinked.detail"))
      NavigationLink(value: AppRoute.chessComLink) {
        Label(localization("account.chessCom.link"), systemImage: "link")
      }
    } header: {
      Text(localization("account.chessCom.title"))
    } footer: {
      Text(localization("account.chessCom.privacy"))
    }
  }
}

/// The linked account: profile, ratings, and the recent games with Import.
private struct ChessComLinkedSections: View {
  let account: ChessComAccountModel
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  @Environment(\.locale)
  private var locale

  var body: some View {
    Section {
      profileRow
      switch account.phase {
      case .loading:
        ProgressView().frame(maxWidth: .infinity)
      case .failed(let failure):
        Text(localization(failure.messageKey))
        Button(localization("common.retry"), systemImage: "arrow.clockwise") {
          Task { await account.load() }
        }
      case .loaded:
        EmptyView()
      }
      Button(localization("account.chessCom.unlink"), role: .destructive) {
        model.settings.value.chessComUsername = nil
      }
    } header: {
      Text(localization("account.chessCom.title"))
    } footer: {
      Text(localization("account.chessCom.privacy"))
    }

    if account.phase == .loaded {
      if let stats = account.stats {
        Section(localization("account.chessCom.ratings")) {
          ForEach(AccountLayout.ratings(stats)) { row in
            LabeledContent {
              Text(row.rating.formatted())
            } label: {
              VStack(alignment: .leading) {
                Text(AccountLayout.timeClassName(row.timeClass, localization: localization))
                if let record = row.record {
                  Text(AccountLayout.record(record, localization: localization))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
              }
            }
          }
        }
      }
      recentGames
    }
  }

  private var profileRow: some View {
    let size = model.catalog.interface.account.avatarSize
    return HStack(spacing: model.catalog.interface.gap) {
      AsyncImage(url: account.profile?.avatar) { image in
        image.resizable().scaledToFill()
      } placeholder: {
        Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
      }
      .frame(width: size, height: size)
      .clipShape(Circle())
      .accessibilityHidden(true)
      VStack(alignment: .leading) {
        Text(account.profile?.username ?? account.username).font(.headline)
        if let name = account.profile?.name {
          Text(name).foregroundStyle(.secondary)
        }
      }
    }
  }

  @ViewBuilder
  private var recentGames: some View {
    Section {
      if account.games.isEmpty {
        Text(localization("account.chessCom.recentGames.empty")).foregroundStyle(.secondary)
      } else {
        Button(
          localization("account.chessCom.importAll"),
          systemImage: "square.and.arrow.down.on.square"
        ) {
          importGames(account.games)
        }
        ForEach(account.games) { game in
          Button {
            importGames([game])
          } label: {
            HStack {
              VStack(alignment: .leading) {
                Text(
                  AccountLayout.title(game, username: account.username, localization: localization)
                )
                Text(
                  AccountLayout.detail(
                    game,
                    username: account.username,
                    localization: localization,
                    locale: locale
                  )
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
              }
              Spacer(minLength: 0)
              Text(localization("account.chessCom.import")).foregroundStyle(.tint)
            }
          }
        }
      }
    } header: {
      Text(localization("account.chessCom.recentGames"))
    } footer: {
      if let summary = account.importSummary {
        Text(
          AccountLayout.summaryLines(summary, localization: localization).joined(separator: "\n")
        )
      }
    }
  }

  private func importGames(_ games: [ChessComGame]) {
    Task {
      await account.importGames(games, into: model.gameStore)
      await model.reloadGames()
    }
  }
}
