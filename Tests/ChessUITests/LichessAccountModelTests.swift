import Foundation
import LichessLink
import Testing
@testable import ChessUI

/// Answers by path, records every request, and lets a test push lines into the open event stream.
private actor FakeTransport: LichessTransport {
    typealias Handler = @Sendable (URLRequest) -> (Int, Data)

    private(set) var requests: [URLRequest] = []
    private var continuations: [String: AsyncThrowingStream<String, Error>.Continuation] = [:]
    private var terminatedPaths: [String] = []
    private let handler: Handler

    init(handler: @escaping Handler) { self.handler = handler }

    var paths: [String] { requests.map { $0.httpMethod! + " " + $0.url!.path() } }
    var authorizations: [String?] { requests.map { $0.value(forHTTPHeaderField: "Authorization") } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let (status, body) = handler(request)
        return (body, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func lines(for request: URLRequest) async throws -> (HTTPURLResponse, AsyncThrowingStream<String, Error>) {
        requests.append(request)
        let (status, _) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        let path = request.url!.path()
        return (response, AsyncThrowingStream { continuation in
            continuations[path] = continuation
            continuation.onTermination = { _ in Task { await self.markTerminated(path) } }
        })
    }

    private func markTerminated(_ path: String) { terminatedPaths.append(path) }

    /// Whether the consumer of the stream at `path` has gone away or the stream has finished.
    func didTerminate(_ path: String) -> Bool { terminatedPaths.contains(path) }

    func push(_ line: String, to path: String = "/api/stream/event") { continuations[path]?.yield(line) }

    /// Ends the stream at `path`, as the server does when a seek is matched.
    func finish(_ path: String) { continuations[path]?.finish() }
}

private let accountJSON = Data(#"{"id":"georges","username":"Georges"}"#.utf8)
private let playingJSON = Data(
    #"{"nowPlaying":[{"gameId":"rCRw1Auv","color":"black","fen":"8/8/8/8/8/8/8/K6k w - - 0 60","opponent":{"id":"philippe","username":"Philippe","rating":1790},"isMyTurn":true}]}"#.utf8)

private func challengeLine(type: String = "challenge", id: String, direction: String = "in") -> String {
    #"{"type":"\#(type)","challenge":{"id":"\#(id)","status":"created","challenger":{"id":"philippe","name":"Philippe"},"rated":false,"speed":"blitz","timeControl":{"type":"clock","limit":300,"increment":3},"color":"white","direction":"\#(direction)"}}"#
}

/// Accepts the token `good`; any other answers 401.
private func lichessAPI(_ request: URLRequest) -> (Int, Data) {
    guard request.value(forHTTPHeaderField: "Authorization") == "Bearer good" else { return (401, Data()) }
    switch request.url!.path() {
    case "/api/account": return (200, accountJSON)
    case "/api/account/playing": return (200, playingJSON)
    default: return (200, Data("{}".utf8))
    }
}

private let outgoingChallengeJSON = Data(
    #"{"id":"chal1234","status":"created","challenger":{"id":"georges","name":"Georges"},"destUser":{"id":"philippe","name":"Philippe"},"rated":false,"speed":"blitz","timeControl":{"type":"clock","limit":180,"increment":2},"color":"random","direction":"out"}"#.utf8)

private func challengeAPI(_ request: URLRequest) -> (Int, Data) {
    request.url!.path() == "/api/challenge/Philippe" ? (200, outgoingChallengeJSON) : lichessAPI(request)
}

@MainActor
struct LichessAccountModelTests {
    private let configuration = LichessConfiguration(
        baseURL: URL(string: "https://lichess.example.test")!, userAgent: "KingsideTests/1.0 (+tests)",
        clientID: "kingside-tests", redirectURI: URL(string: "kingside://oauth")!)

    private func makeModel(
        token: String? = nil, handler: @escaping @Sendable (URLRequest) -> (Int, Data) = lichessAPI
    ) -> (LichessAccountModel, InMemoryTokenStore, FakeTransport) {
        let store = InMemoryTokenStore(token: token)
        let transport = FakeTransport(handler: handler)
        let configuration = configuration
        // No real pause between reconnects.
        let model = LichessAccountModel(
            store: store,
            makeClient: { LichessClient(configuration: configuration, transport: transport, tokenProvider: $0) },
            sleep: { _ in try await Task.sleep(for: .milliseconds(1)) })
        return (model, store, transport)
    }

    /// Polls until `condition` holds; the test's time limit cancels it.
    private func wait(until condition: () async -> Bool) async throws {
        while !(await condition()) {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func signInWithValidTokenSavesItAndOpensTheStream() async throws {
        let (model, store, transport) = makeModel()
        await model.signIn(token: " good\n")
        #expect(model.phase == .signedIn(username: "Georges"))
        #expect(store.token() == "good")
        try await wait { await transport.paths.contains("GET /api/stream/event") }
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func signInWithRejectedTokenSavesNothing() async {
        let (model, store, _) = makeModel()
        await model.signIn(token: "bad")
        #expect(model.phase == .failed(.unauthorized))
        #expect(store.token() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func startWithStoredTokenSignsInAndLoadsOngoingGames() async throws {
        let (model, _, transport) = makeModel(token: "good")
        await model.start()
        #expect(model.phase == .signedIn(username: "Georges"))
        try await wait { model.ongoingGames.count == 1 }
        #expect(model.ongoingGames.first?.gameId == "rCRw1Auv")
        try await wait { await transport.paths.contains("GET /api/stream/event") }
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func startWithoutTokenMakesNoRequest() async {
        let (model, _, transport) = makeModel()
        await model.start()
        #expect(model.phase == .signedOut)
        #expect(await transport.paths.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func startWithRevokedTokenDeletesIt() async {
        let (model, store, _) = makeModel(token: "revoked")
        await model.start()
        #expect(model.phase == .signedOut)
        #expect(store.token() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func signOutRevokesThenDeletesTheToken() async throws {
        let (model, store, transport) = makeModel(token: "good")
        await model.start()
        try await wait { await transport.paths.contains("GET /api/stream/event") }
        await model.signOut()
        #expect(model.phase == .signedOut)
        #expect(store.token() == nil)
        #expect(await transport.paths.contains("DELETE /api/token"))
        // The revoke request still carried the token.
        #expect(await transport.authorizations.last == "Bearer good")
    }

    @Test(.timeLimit(.minutes(1)))
    func signOutIgnoresRevokeFailure() async {
        let (model, store, _) = makeModel(token: "good") { request in
            request.httpMethod == "DELETE" ? (500, Data()) : lichessAPI(request)
        }
        await model.start()
        await model.signOut()
        #expect(model.phase == .signedOut)
        #expect(store.token() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func eventsAddAndRemoveChallengesAndReportStartedGames() async throws {
        let (model, _, transport) = makeModel(token: "good")
        await model.start()
        try await wait { await transport.paths.contains("GET /api/stream/event") }
        // The stream opens after the request is recorded; give the continuation a moment to exist.
        try await wait {
            await transport.push(challengeLine(id: "c1"))
            return model.incomingChallenges.count == 1
        }
        await transport.push(challengeLine(id: "c2"))
        await transport.push(challengeLine(id: "c3", direction: "out"))
        // The user's own challenge without `direction` is outgoing too; events arrive in order,
        // so the empty list below also shows that it was dropped.
        await transport.push(challengeLine(id: "c4", direction: "out")
            .replacing(#""direction":"out""#, with: #""x":0"#)
            .replacing(#""id":"philippe","name":"Philippe""#, with: #""id":"georges","name":"Georges""#))
        try await wait { model.incomingChallenges.count == 2 }
        await transport.push(challengeLine(type: "challengeCanceled", id: "c1"))
        await transport.push(challengeLine(type: "challengeDeclined", id: "c2"))
        try await wait { model.incomingChallenges.isEmpty }

        await transport.push(
            #"{"type":"gameStart","game":{"gameId":"abcd1234","color":"white","fen":"x","isMyTurn":true}}"#)
        try await wait { model.startedGameID == "abcd1234" }
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func unauthorizedOnTheStreamSignsOut() async throws {
        let (model, store, _) = makeModel(token: "good") { request in
            request.url!.path() == "/api/stream/event" ? (401, Data()) : lichessAPI(request)
        }
        await model.start()
        try await wait { model.phase == .signedOut }
        #expect(store.token() == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func streamReconnectsAfterADisconnectAndWaitsAMinuteAfterRateLimit() async throws {
        let waits = Waits()
        let store = InMemoryTokenStore(token: "good")
        let transport = FakeTransport { request in
            request.url!.path() == "/api/stream/event" ? (429, Data()) : lichessAPI(request)
        }
        let configuration = configuration
        let model = LichessAccountModel(
            store: store,
            makeClient: { LichessClient(configuration: configuration, transport: transport, tokenProvider: $0) },
            sleep: { duration in
                waits.record(duration)
                try await Task.sleep(for: .milliseconds(1))
            })
        await model.start()
        try await wait { waits.all.count >= 2 }
        await model.signOut()
        #expect(waits.all.allSatisfy { $0 >= .seconds(60) })
    }

    // MARK: - Lobby

    /// A model that is signed in with its event stream open.
    private func signedInModel(
        handler: @escaping @Sendable (URLRequest) -> (Int, Data) = lichessAPI
    ) async throws -> (LichessAccountModel, FakeTransport) {
        let (model, _, transport) = makeModel(token: "good", handler: handler)
        await model.start()
        try await wait { await transport.paths.contains("GET /api/stream/event") }
        return (model, transport)
    }

    @Test(.timeLimit(.minutes(1)))
    func seekSendsTheRequestAndKeepsWaiting() async throws {
        let (model, transport) = try await signedInModel()
        model.seek(rated: true, minutes: 10, increment: 5)
        #expect(model.isSeeking)
        try await wait { await transport.paths.contains("POST /api/board/seek") }
        let request = try #require(await transport.requests.first { $0.url!.path() == "/api/board/seek" })
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self) == "rated=true&time=10&increment=5")
        #expect(model.isSeeking)
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellingTheSeekClosesTheStream() async throws {
        let (model, transport) = try await signedInModel()
        model.seek(rated: false, minutes: 10, increment: 0)
        try await wait { await transport.paths.contains("POST /api/board/seek") }
        model.cancelSeek()
        #expect(!model.isSeeking)
        try await wait { await transport.didTerminate("/api/board/seek") }
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func theSeekStreamEndingEndsTheWaitingState() async throws {
        let (model, transport) = try await signedInModel()
        model.seek(rated: false, minutes: 15, increment: 10)
        try await wait { await transport.paths.contains("POST /api/board/seek") }
        try await wait {
            await transport.finish("/api/board/seek")
            return !model.isSeeking
        }
        #expect(model.lobbyFailure == nil)
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func aRefusedSeekShowsNotAllowed() async throws {
        let (model, _) = try await signedInModel { request in
            request.url!.path() == "/api/board/seek" ? (400, Data()) : lichessAPI(request)
        }
        model.seek(rated: true, minutes: 3, increment: 0)
        try await wait { !model.isSeeking }
        #expect(model.lobbyFailure == .notAllowed)
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func aGameStartEndsTheSeekAndRefreshesTheGames() async throws {
        let (model, transport) = try await signedInModel()
        model.seek(rated: false, minutes: 10, increment: 0)
        try await wait { await transport.paths.contains("POST /api/board/seek") }
        let before = await transport.paths.count { $0 == "GET /api/account/playing" }
        try await wait {
            await transport.push(#"{"type":"gameStart","game":{"gameId":"abcd1234","color":"white","fen":"x","isMyTurn":true}}"#)
            return model.startedGameID == "abcd1234"
        }
        #expect(!model.isSeeking)
        try await wait { await transport.paths.count { $0 == "GET /api/account/playing" } > before }
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func challengeIsSentAndTrackedUntilItIsCancelled() async throws {
        let (model, transport) = try await signedInModel(handler: challengeAPI)
        await model.challenge(username: "Philippe", rated: true, limitSeconds: 180, increment: 2, color: .black)
        #expect(model.outgoingChallengeID == "chal1234")
        let request = try #require(await transport.requests.first { $0.url!.path() == "/api/challenge/Philippe" })
        #expect(String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            == "rated=true&clock.limit=180&clock.increment=2&color=black")

        await model.cancelChallenge()
        #expect(model.outgoingChallengeID == nil)
        #expect(!model.challengeWasDeclined)
        #expect(await transport.paths.contains("POST /api/challenge/chal1234/cancel"))
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func aDeclinedChallengeClearsTheTrackingAndShowsDeclined() async throws {
        let (model, transport) = try await signedInModel(handler: challengeAPI)
        await model.challenge(username: "Philippe", rated: false, limitSeconds: 180, increment: 2, color: .random)
        try await wait {
            await transport.push(challengeLine(type: "challengeDeclined", id: "other", direction: "out"))
            await transport.push(challengeLine(type: "challengeDeclined", id: "chal1234", direction: "out"))
            return model.challengeWasDeclined
        }
        #expect(model.outgoingChallengeID == nil)
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func aGameStartClearsTheOutgoingChallenge() async throws {
        let (model, transport) = try await signedInModel(handler: challengeAPI)
        await model.challenge(username: "Philippe", rated: false, limitSeconds: 180, increment: 2, color: .random)
        try await wait {
            await transport.push(#"{"type":"gameStart","game":{"gameId":"chal1234","color":"white","fen":"x","isMyTurn":true}}"#)
            return model.startedGameID == "chal1234"
        }
        #expect(model.outgoingChallengeID == nil)
        #expect(!model.challengeWasDeclined)
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func acceptAndDeclineHitTheirPathsAndDropTheChallenge() async throws {
        let (model, transport) = try await signedInModel()
        try await wait {
            await transport.push(challengeLine(id: "c1"))
            await transport.push(challengeLine(id: "c2"))
            return model.incomingChallenges.count == 2
        }
        await model.accept(challengeID: "c1")
        await model.decline(challengeID: "c2")
        #expect(await transport.paths.contains("POST /api/challenge/c1/accept"))
        #expect(await transport.paths.contains("POST /api/challenge/c2/decline"))
        #expect(model.incomingChallenges.isEmpty)
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func aFailedAcceptKeepsTheChallengeAndShowsTheFailure() async throws {
        let (model, transport) = try await signedInModel { request in
            request.url!.path() == "/api/challenge/c1/accept" ? (429, Data()) : lichessAPI(request)
        }
        try await wait {
            await transport.push(challengeLine(id: "c1"))
            return model.incomingChallenges.count == 1
        }
        await model.accept(challengeID: "c1")
        #expect(model.lobbyFailure == .rateLimited)
        #expect(model.incomingChallenges.count == 1)
        await model.signOut()
    }

    @Test(.timeLimit(.minutes(1)))
    func gameFinishRefreshesTheOngoingGames() async throws {
        let (model, transport) = try await signedInModel()
        try await wait { model.ongoingGames.count == 1 }
        let before = await transport.paths.count { $0 == "GET /api/account/playing" }
        try await wait {
            await transport.push(#"{"type":"gameFinish","game":{"gameId":"rCRw1Auv"}}"#)
            return await transport.paths.count { $0 == "GET /api/account/playing" } > before
        }
        await model.signOut()
    }

    @Test func failuresMapToTheirCauses() {
        #expect(LichessFailure(LichessError.http(status: 400)) == .notAllowed)
        #expect(LichessFailure(LichessError.http(status: 500)) == .network)
        #expect(LichessFailure(LichessError.rateLimited) == .rateLimited)
        #expect(LichessFailure(URLError(.notConnectedToInternet)) == .network)
    }
}

private final class Waits: @unchecked Sendable {
    private let lock = NSLock()
    private var durations: [Duration] = []

    var all: [Duration] { lock.withLock { durations } }
    func record(_ duration: Duration) { lock.withLock { durations.append(duration) } }
}
