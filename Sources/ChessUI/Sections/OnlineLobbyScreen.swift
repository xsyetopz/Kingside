import ChessContent
import ChessPlay
import LichessLink
import SwiftUI

/// The Lichess lobby: a quick seek, a challenge to a friend, the challenges to answer, and the
/// games to resume.
struct OnlineLobbyScreen: View {
  @Environment(AppModel.self)
  private var model
  @Environment(\.localization)
  private var localization
  @State
  private var seekPreset = OnlineLobby.seekPresets[0]
  @State
  private var seekRated = false
  @State
  private var challengePreset = OnlineLobby.challengePresets[2]
  @State
  private var challengeRated = false
  @State
  private var challengeColor = BotColorChoice.random
  @State
  private var username = ""

  private var account: LichessAccountModel { model.lichess }
  private var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    Form {
      ScreenHeading(title: localization("online.lobby.title")).listRowBackground(Color.clear)
      if let failure = account.lobbyFailure {
        Text(localization(failure.messageKey)).foregroundStyle(.red)
      }
      seekSection
      challengeSection
      if !account.incomingChallenges.isEmpty { incomingSection }
      if !account.ongoingGames.isEmpty { ongoingSection }
    }
    .readableRows(model.catalog.interface)
    .screenTitle(localization("online.lobby.title"), chrome: .pushed)
  }

  // MARK: Quick seek

  @ViewBuilder
  private var seekSection: some View {
    Section(localization("online.seek.title")) {
      if account.isSeeking {
        waiting(localization("online.seek.waiting"))
        Button(localization("common.cancel"), role: .cancel) { account.cancelSeek() }
          .accessibilityIdentifier("online.seek.cancel")
      } else {
        presetRows(OnlineLobby.seekPresets, selection: $seekPreset)
        Toggle(localization("online.rated"), isOn: $seekRated)
        Button(localization("online.seek.start"), systemImage: "magnifyingglass") {
          account.seek(
            rated: seekRated,
            minutes: seekPreset.minutes,
            increment: seekPreset.increment
          )
        }
        .accessibilityIdentifier("online.seek.start")
      }
    }
  }

  // MARK: Challenge a friend

  @ViewBuilder
  private var challengeSection: some View {
    Section(localization("online.challenge.title")) {
      if account.outgoingChallengeID != nil {
        waiting(localization("online.challenge.waiting"))
        Button(localization("common.cancel"), role: .cancel) {
          Task { await account.cancelChallenge() }
        }
        .accessibilityIdentifier("online.challenge.cancel")
      } else {
        if account.challengeWasDeclined {
          Label(localization("online.challenge.declined"), systemImage: "hand.raised")
            .foregroundStyle(.red)
        }
        TextField(localization("online.challenge.username"), text: $username)
          .autocorrectionDisabled()
          #if os(iOS)
            .textInputAutocapitalization(.never)
          #endif
          .onSubmit(sendChallenge)
        presetRows(OnlineLobby.challengePresets, selection: $challengePreset)
        Picker(localization("playBots.color.title"), selection: $challengeColor) {
          ForEach(BotColorChoice.allCases) { choice in
            Text(localization(choice.titleKey)).tag(choice)
          }
        }
        .pickerStyle(.segmented)
        Toggle(localization("online.rated"), isOn: $challengeRated)
        Button(
          localization("online.challenge.send"),
          systemImage: "paperplane",
          action: sendChallenge
        )
        .disabled(!OnlineLobby.isValidUsername(trimmedUsername))
        .accessibilityIdentifier("online.challenge.send")
      }
    }
  }

  private func sendChallenge() {
    guard OnlineLobby.isValidUsername(trimmedUsername) else { return }
    let preset = challengePreset
    Task {
      await account.challenge(
        username: trimmedUsername,
        rated: challengeRated,
        limitSeconds: preset.limitSeconds,
        increment: preset.increment,
        color: challengeColor.lichessColor
      )
    }
  }

  // MARK: Incoming challenges and ongoing games

  private var incomingSection: some View {
    Section(localization("online.incoming.title")) {
      ForEach(account.incomingChallenges, id: \.id) { challenge in
        VStack(alignment: .leading, spacing: model.catalog.interface.gap / 2) {
          Text(OnlineLobby.name(challenge.challenger, localization: localization)).font(.headline)
          Text(challengeDetail(challenge)).font(.subheadline).foregroundStyle(.secondary)
          HStack {
            Button(localization("online.challenge.accept")) {
              Task { await account.accept(challengeID: challenge.id) }
            }
            Button(localization("online.challenge.decline"), role: .destructive) {
              Task { await account.decline(challengeID: challenge.id) }
            }
          }
          .buttonStyle(.bordered)
        }
      }
    }
  }

  private func challengeDetail(_ challenge: LichessChallenge) -> String {
    localization.string(
      "online.challenge.detail",
      OnlineLobby.label(challenge.timeControl, localization: localization),
      localization(challenge.rated ? "online.rated" : "online.casual")
    )
  }

  private var ongoingSection: some View {
    Section(localization("online.ongoing.title")) {
      ForEach(account.ongoingGames, id: \.gameId) { game in
        NavigationLink(value: AppRoute.onlineGame(id: game.gameId)) {
          VStack(alignment: .leading) {
            Text(game.opponent.username).font(.headline)
            Text(
              localization.string(
                "online.ongoing.detail",
                localization(OnlineLobby.colorKey(game.color)),
                localization(OnlineLobby.turnKey(game))
              )
            )
            .font(.subheadline).foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  // MARK: Pieces

  private func waiting(_ text: String) -> some View {
    Label {
      Text(text)
    } icon: {
      ProgressView()
    }
  }

  /// The presets grouped by speed, one row each; the selected one has a checkmark.
  @ViewBuilder
  private func presetRows(
    _ presets: [OnlineLobby.Preset],
    selection: Binding<OnlineLobby.Preset>
  ) -> some View {
    ForEach(OnlineLobby.categories(of: presets), id: \.self) { category in
      ForEach(OnlineLobby.presets(presets, in: category)) { preset in
        SetupRow(
          title: OnlineLobby.label(preset, localization: localization),
          subtitle: localization(category.nameKey),
          isSelected: preset == selection.wrappedValue
        ) {
          selection.wrappedValue = preset
        } leading: {
          EmptyView()
        }
      }
    }
  }
}
