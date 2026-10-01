import ChessContent
import ChessCore
import ChessPlay
import Foundation
import LichessLink
import Testing
@testable import ChessUI

/// Answers by path, records every request, and lets a test push lines into the open game stream.
private actor FakeTransport: LichessTransport {
  private(set) var requests: [URLRequest] = []
  private var continuation: AsyncThrowingStream<String, Error>.Continuation?

  var paths: [String] { requests.map { $0.httpMethod! + " " + $0.url!.path() } }

  /// Returns once a request `path` ("GET /api/…") has arrived; a cancelled test throws.
  func waitForRequest(_ path: String) async throws {
    while !paths.contains(path) {
      try Task.checkCancellation()
      await Task.yield()
    }
  }

  private func record(_ request: URLRequest) { requests.append(request) }

  func data(for request: URLRequest) throws -> (Data, HTTPURLResponse) {
    record(request)
    let body =
      request.url!.path() == "/api/account"
      ? Data(#"{"id":"georges","username":"Georges"}"#.utf8) : Data("{}".utf8)
    return (
      body,
      HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
    )
  }

  func lines(
    for request: URLRequest
  ) throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
    record(request)
    let response = HTTPURLResponse(
      url: request.url!,
      statusCode: 200,
      httpVersion: nil,
      headerFields: nil
    )!
    return (response, AsyncThrowingStream { continuation = $0 })
  }

  func push(_ line: String) { continuation?.yield(line) }
}

private let gameFullLine =
  #"{"type":"gameFull","id":"rCRw1Auv","clock":{"initial":300000,"increment":3000},"#
  + #""speed":"blitz","rated":true,"white":{"id":"georges","name":"Georges","title":null,"#
  + #""rating":1838},"#
  + #""black":{"id":"philippe","name":"Philippe","title":"FM","rating":1790},"#
  + #""initialFen":"startpos","state":{"type":"gameState","moves":"e2e4 e7e5","wtime":300000,"#
  + #""btime":298000,"winc":3000,"binc":3000,"status":"started","bdraw":true}}"#
private let correspondenceLine =
  #"{"type":"gameFull","id":"corr0001","speed":"correspondence","rated":false,"#
  + #""white":{"id":"philippe","name":"Philippe"},"black":{"id":"georges","name":"Georges"},"#
  + #""initialFen":"8/8/8/8/8/8/8/K6k w - - 0 60","#
  + #""state":{"type":"gameState","moves":"","wtime":2147483647,"btime":2147483647,"winc":0,"#
  + #""binc":0,"status":"started"}}"#

private let aiGameLine =
  #"{"type":"gameFull","id":"aiGame01","speed":"rapid","rated":false,"#
  + #""white":{"id":"georges","name":"Georges","rating":1838},"#
  + #""black":{"aiLevel":3,"id":null},"initialFen":"startpos","#
  + #""state":{"type":"gameState","moves":"","wtime":2147483647,"btime":2147483647,"winc":0,"#
  + #""binc":0,"status":"started"}}"#

private func event(
  _ line: String,
  userID: String = "georges",
  timed: Bool = true
) throws -> OnlineGameEvent? {
  let parsed = try #require(try LichessGameEvent.parse(line: line))
  return try LichessGameConnection.map(
    parsed,
    userID: userID,
    timed: timed,
    localization: Localization(preferredLanguages: ["en-US"])
  )
}

struct LichessGameConnectionMappingTests {
  @Test
  func gameFullMapsPlayersClockAndState() throws {
    let mapped = try #require(try event(gameFullLine))
    guard case .started(let start) = mapped else { Issue.record("not started: \(mapped)"); return }
    #expect(start.gameID == "rCRw1Auv")
    #expect(start.initialFEN == nil)
    #expect(start.white == OnlinePlayer(name: "Georges", rating: 1838))
    #expect(start.black == OnlinePlayer(name: "Philippe", rating: 1790))
    #expect(start.myColor == .white)
    #expect(start.timeControl == TimeControl(initialSeconds: 300, incrementSeconds: 3))
    #expect(start.state.uciMoves == ["e2e4", "e7e5"])
    #expect(start.state.whiteTime == .milliseconds(300_000))
    #expect(start.state.blackTime == .milliseconds(298_000))
    #expect(start.state.status == .started)
    #expect(start.state.blackOffersDraw && !start.state.whiteOffersDraw)
  }

  @Test
  func anAIOpponentIsNamedByItsLocalizedStockfishLevel() throws {
    guard case .started(let start)? = try event(aiGameLine) else {
      Issue.record("not started")
      return
    }
    #expect(start.black == OnlinePlayer(name: "Stockfish level 3", rating: nil))
  }

  @Test
  func myColorFollowsTheSignedInUser() throws {
    guard case .started(let start)? = try event(gameFullLine, userID: "philippe") else {
      Issue.record("not started")
      return
    }
    #expect(start.myColor == .black)
  }

  @Test
  func aGameTheUserDoesNotPlayThrowsNotAPlayer() {
    #expect(throws: LichessGameConnection.NotAPlayer.self) {
      try event(gameFullLine, userID: "someone")
    }
    #expect(throws: LichessGameConnection.NotAPlayer.self) { try event(gameFullLine, userID: "") }
  }

  @Test
  func aCorrespondenceGameHasNoTimeControlNorClocks() throws {
    guard case .started(let start)? = try event(correspondenceLine, timed: false) else {
      Issue.record("not started")
      return
    }
    #expect(start.myColor == .black)
    #expect(start.timeControl == nil)
    #expect(start.initialFEN == "8/8/8/8/8/8/8/K6k w - - 0 60")
    #expect(start.state.whiteTime == nil && start.state.blackTime == nil)
  }

  @Test
  func gameStateMapsMovesWinnerAndStatus() throws {
    let line =
      #"{"type":"gameState","moves":"f2f3 e7e5 g2g4 d8h4","#
      + #""wtime":1000,"btime":2500,"winc":0,"binc":0,"status":"mate","winner":"black"}"#
    #expect(
      try event(line)
        == .state(
          OnlineGameState(
            uciMoves: ["f2f3", "e7e5", "g2g4", "d8h4"],
            whiteTime: .seconds(1),
            blackTime: .milliseconds(2500),
            status: .mate,
            winner: .black
          )
        )
    )
    #expect(
      try event(line, timed: false)
        == .state(
          OnlineGameState(
            uciMoves: ["f2f3", "e7e5", "g2g4", "d8h4"],
            status: .mate,
            winner: .black
          )
        )
    )
  }

  @Test
  func noMovesMapToAnEmptyList() throws {
    let line =
      #"{"type":"gameState","moves":"","wtime":1,"btime":1,"winc":0,"binc":0,"status":"started"}"#
    guard case .state(let state)? = try event(line) else { Issue.record("not a state"); return }
    #expect(state.uciMoves.isEmpty)
  }

  @Test
  func statusNamesMapToStatuses() {
    let names = [
      "created", "started", "aborted", "mate", "resign", "stalemate", "timeout", "draw",
      "outoftime",
      "cheat", "noStart", "unknownFinish", "variantEnd",
    ]
    let expected: [OnlineGameStatus] = [
      .created, .started, .aborted, .mate, .resign, .stalemate, .timeout, .draw,
      .outoftime, .cheat, .noStart, .unknownFinish, .variantEnd,
    ]
    #expect(names.map(LichessGameConnection.status) == expected)
    #expect(LichessGameConnection.status("newThing") == .other("newThing"))
  }

  @Test
  func opponentGoneAndBack() throws {
    #expect(
      try event(#"{"type":"opponentGone","gone":true,"claimWinInSeconds":20}"#)
        == .opponentGone(claimWinIn: .seconds(20))
    )
    #expect(try event(#"{"type":"opponentGone","gone":true}"#) == .opponentGone(claimWinIn: nil))
    #expect(try event(#"{"type":"opponentGone","gone":false}"#) == .opponentBack)
  }

  @Test
  func onlyPlayerChatIsMapped() throws {
    guard
      case .chat(let line)? = try event(
        #"{"type":"chatLine","username":"philippe","text":"hi","room":"player"}"#
      )
    else {
      Issue.record("not chat")
      return
    }
    #expect(line.username == "philippe" && line.text == "hi")
    #expect(try event(#"{"type":"chatLine","username":"x","text":"hi","room":"spectator"}"#) == nil)
  }
}

@MainActor
struct LichessGameConnectionTests {
  private func makeConnection(
    id: String = "rCRw1Auv"
  ) async throws -> (LichessGameConnection, FakeTransport) {
    let transport = FakeTransport()
    let configuration = LichessConfiguration(
      baseURL: URL(string: "https://lichess.example.test")!,
      userAgent: "KingsideTests/1.0 (+tests)",
      clientID: "kingside-tests",
      redirectURI: URL(string: "kingside://oauth")!
    )
    let model = LichessAccountModel(
      store: InMemoryTokenStore(token: nil),
      makeClient: {
        LichessClient(configuration: configuration, transport: transport, tokenProvider: $0)
      },
      sleep: { _ in await Task.yield() }
    )
    await model.signIn(token: "good")
    // The account's event stream opens first, so the game stream is the one the fake pushes into.
    try await transport.waitForRequest("GET /api/stream/event")
    return (model.gameConnection(id: id), transport)
  }

  @Test(.timeLimit(.minutes(1)))
  func streamsStartedThenStateAndStopsOnCancel() async throws {
    let (connection, transport) = try await makeConnection()
    #expect(connection.userID == "georges")
    var iterator = connection.events().makeAsyncIterator()
    try await transport.waitForRequest("GET /api/board/game/stream/rCRw1Auv")
    await transport.push(gameFullLine)
    await transport.push(
      #"{"type":"gameState","moves":"e2e4 e7e5 g1f3","#
        + #""wtime":1,"btime":2,"winc":0,"binc":0,"status":"started"}"#
    )
    guard case .started(let start)? = try await iterator.next() else {
      Issue.record("no start"); return
    }
    #expect(start.myColor == .white)
    guard case .state(let state)? = try await iterator.next() else {
      Issue.record("no state"); return
    }
    #expect(state.uciMoves.count == 3)
  }

  @Test(.timeLimit(.minutes(1)))
  func actionsCallTheBoardApi() async throws {
    let (connection, transport) = try await makeConnection()
    let actions: [OnlineAction] = [
      .move("e2e4"), .resign, .abort, .claimVictory, .offerDraw, .acceptDraw,
      .declineDraw, .chat("hello"),
    ]
    for action in actions { try await connection.send(action) }
    let game = "/api/board/game/rCRw1Auv"
    #expect(
      await transport.paths.suffix(actions.count) == [
        "POST \(game)/move/e2e4", "POST \(game)/resign", "POST \(game)/abort",
        "POST \(game)/claim-victory",
        "POST \(game)/draw/yes", "POST \(game)/draw/yes",
        "POST \(game)/draw/no",
        "POST \(game)/chat",
      ]
    )
  }

  @Test(.timeLimit(.minutes(1)))
  func signedOutModelGivesAConnectionThatMatchesNoPlayer() {
    let model = LichessAccountModel(
      store: InMemoryTokenStore(token: nil)
    ) {
      LichessClient(
        configuration: .init(
          baseURL: URL(string: "https://lichess.example.test")!,
          userAgent: "KingsideTests/1.0 (+tests)",
          clientID: "kingside-tests",
          redirectURI: URL(string: "kingside://oauth")!
        ),
        transport: FakeTransport(),
        tokenProvider: $0
      )
    }
    #expect(model.gameConnection(id: "rCRw1Auv").userID.isEmpty)
  }
}
