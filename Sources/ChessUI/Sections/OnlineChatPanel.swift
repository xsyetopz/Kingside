import ChessContent
import ChessPlay
import SwiftUI

extension EnvironmentValues {
  /// True while `GameBoardLayout` shows the panel beside the board.
  @Entry
  var isWideGameLayout = false
}

/// The chat of an online game: a button that opens the chat as a sheet on narrow screens and on
/// tvOS, and the chat itself in the side panel on wide ones. Nothing shows while chat is off in the
/// settings.
struct OnlineChatControls: View {
  let session: OnlineGameSession
  @Environment(\.isWideGameLayout)
  private var isWide
  @Environment(\.localization)
  private var localization
  @State
  private var showsSheet = false

  /// The height of the inline chat in the side panel.
  private static let inlineHeight: CGFloat = 220

  var body: some View {
    if session.isChatEnabled {
      #if os(tvOS)
        sheetButton
      #else
        if isWide {
          OnlineChatPanel(session: session).frame(height: Self.inlineHeight)
        } else {
          sheetButton
        }
      #endif
    }
  }

  private var sheetButton: some View {
    Button {
      showsSheet = true
    } label: {
      HStack {
        Label(localization("chat.title"), systemImage: "bubble.left.and.bubble.right").lineLimit(1)
        if session.unreadChatCount > 0 {
          Text(session.unreadChatCount, format: .number)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .background(.red, in: Capsule())
            .foregroundStyle(.white)
            .accessibilityIdentifier("chat.unread")
        }
      }
    }
    #if os(tvOS)
      .buttonStyle(.bordered)
    #endif
    .accessibilityIdentifier("chat.open")
    .sheet(isPresented: $showsSheet) {
      NavigationStack {
        OnlineChatPanel(session: session)
          .padding()
          .navigationTitle(localization("chat.title"))
          #if !os(tvOS)
            .toolbar {
              ToolbarItem(placement: .confirmationAction) {
                Button(localization("common.done")) { showsSheet = false }
              }
            }
          #endif
      }
      #if os(macOS)
        .frame(minWidth: 360, minHeight: 420)
      #endif
    }
  }
}

/// The message list with the mute and report controls and the text field.
private struct OnlineChatPanel: View {
  let session: OnlineGameSession
  @Environment(\.localization)
  private var localization
  @Environment(AppModel.self)
  private var model
  @Environment(\.openURL)
  private var openURL
  @State
  private var draft = ""

  var body: some View {
    VStack(spacing: 8) {
      safetyControls
      messages
      HStack {
        TextField(localization("chat.placeholder"), text: $draft)
          .onSubmit(send)
          .onChange(of: draft) { _, text in
            if text.count > OnlineChat.maxLength {
              draft = String(text.prefix(OnlineChat.maxLength))
            }
          }
          .accessibilityIdentifier("chat.field")
        Button(localization("chat.send"), action: send)
          .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .accessibilityIdentifier("chat.send")
      }
    }
    .onAppear { session.markChatRead() }
  }

  private func send() {
    session.sendChat(draft)
    draft = ""
  }

  private var reportURL: URL? {
    session.opponentName.flatMap { model.catalog.services.lichess.reportURL(username: $0) }
  }

  @ViewBuilder
  private var safetyControls: some View {
    if session.opponentName != nil {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Button(localization(session.isOpponentMuted ? "chat.unmute" : "chat.mute")) {
            session.setOpponentMuted(!session.isOpponentMuted)
          }
          .accessibilityIdentifier("chat.mute")
          #if !os(tvOS)
            if let reportURL {
              Button(localization("chat.report")) { openURL(reportURL) }
                .accessibilityIdentifier("chat.report")
            }
          #endif
        }
        #if os(tvOS)
          // tvOS cannot open a web page, so the address is shown to open on another device.
          if let reportURL {
            Text(localization.string("chat.report.tv", reportURL.absoluteString))
              .font(.footnote)
              .accessibilityIdentifier("chat.reportURL")
          }
        #endif
      }
      .buttonStyle(.borderless)
      .font(.footnote)
    }
  }

  private var messages: some View {
    let lines = session.chatMessages
    return ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 4) {
          if lines.isEmpty {
            Text(localization("chat.empty")).foregroundStyle(.secondary)
          }
          ForEach(lines) { line in row(line).id(line.id) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .onChange(of: lines.last?.id) { _, id in
        session.markChatRead()
        if let id { proxy.scrollTo(id, anchor: .bottom) }
      }
    }
    .frame(maxHeight: .infinity)
  }

  @ViewBuilder
  private func row(_ line: OnlineChatMessage) -> some View {
    switch line.kind {
    case .system:
      Text("\(line.username): \(line.text)").italic().foregroundStyle(.secondary)
    case .own:
      Text("\(Text(localization.string("chat.line.own", line.username)).bold()) \(line.text)")
    case .opponent:
      Text("\(Text(line.username).bold()) \(line.text)")
    }
  }
}
