import Foundation

/// Client for the Lichess Board API. Non-stream requests run strictly one at a time.
public actor LichessClient {
    /// How long every request is refused after Lichess answers 429.
    static let rateLimitBackoff: TimeInterval = 60

    private let configuration: LichessConfiguration
    private let transport: any LichessTransport
    private let tokenProvider: @Sendable () async -> String?
    private let now: @Sendable () -> Date
    private var rateLimitedUntil: Date?
    /// Completes when the most recently queued request has finished.
    private var tail: Task<Void, Never>?

    public init(
        configuration: LichessConfiguration,
        transport: any LichessTransport = URLSessionLichessTransport(),
        tokenProvider: @escaping @Sendable () async -> String?,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.tokenProvider = tokenProvider
        self.now = now
    }

    // MARK: Account

    public func account() async throws -> LichessAccount {
        try decode(LichessAccount.self, from: try await send("GET", "api/account"))
    }

    public func ongoingGames() async throws -> [LichessOngoingGame] {
        try decode(LichessOngoingGamesResponse.self, from: try await send("GET", "api/account/playing")).nowPlaying
    }

    /// Revokes the access token the client is using.
    public func revokeToken() async throws {
        _ = try await send("DELETE", "api/token")
    }

    // MARK: Streams

    public func eventStream() -> AsyncThrowingStream<LichessEvent, Error> {
        stream(method: "GET", path: "api/stream/event", form: nil, parse: LichessEvent.parse(line:))
    }

    public func gameStream(id: String) throws -> AsyncThrowingStream<LichessGameEvent, Error> {
        let id = try Self.validGameID(id)
        return stream(method: "GET", path: "api/board/game/stream/\(id)", form: nil, parse: LichessGameEvent.parse(line:))
    }

    /// Creates a seek. The connection stays open while the seek is active; the stream finishes when the
    /// seek is matched, and cancelling the consumer cancels the seek.
    public func seek(rated: Bool, minutes: Int, increment: Int) -> AsyncThrowingStream<Void, Error> {
        stream(
            method: "POST", path: "api/board/seek",
            form: [("rated", String(rated)), ("time", String(minutes)), ("increment", String(increment))],
            parse: { _ in Optional<Void>.none })
    }

    // MARK: Board

    public func move(gameID: String, uci: String) async throws {
        let id = try Self.validGameID(gameID)
        guard Self.isValidUCI(uci) else { throw LichessError.invalidArgument("uci") }
        _ = try await send("POST", "api/board/game/\(id)/move/\(uci)")
    }

    public func resign(gameID: String) async throws { try await gameAction(gameID, "resign") }
    public func abort(gameID: String) async throws { try await gameAction(gameID, "abort") }
    public func claimVictory(gameID: String) async throws { try await gameAction(gameID, "claim-victory") }
    public func claimDraw(gameID: String) async throws { try await gameAction(gameID, "claim-draw") }

    /// Offers a draw, or answers the opponent's offer.
    public func draw(gameID: String, accept: Bool) async throws {
        try await gameAction(gameID, accept ? "draw/yes" : "draw/no")
    }

    public func chat(gameID: String, text: String) async throws {
        let id = try Self.validGameID(gameID)
        _ = try await send("POST", "api/board/game/\(id)/chat", form: [("room", "player"), ("text", text)])
    }

    // MARK: Challenges

    public func challenge(
        username: String, rated: Bool, limitSeconds: Int, increment: Int, color: LichessChallengeColor
    ) async throws -> LichessChallenge {
        let name = try Self.validUsername(username)
        let data = try await send(
            "POST", "api/challenge/\(name)",
            form: [
                ("rated", String(rated)), ("clock.limit", String(limitSeconds)),
                ("clock.increment", String(increment)), ("color", color.rawValue),
            ])
        return try decode(LichessChallenge.self, from: data)
    }

    /// Starts a game against Stockfish; returns the game id.
    public func challengeAI(
        level: Int, limitSeconds: Int, increment: Int, color: LichessChallengeColor
    ) async throws -> String {
        guard (1...8).contains(level) else { throw LichessError.invalidArgument("level") }
        struct Game: Decodable { var id: String }
        let data = try await send(
            "POST", "api/challenge/ai",
            form: [
                ("level", String(level)), ("clock.limit", String(limitSeconds)),
                ("clock.increment", String(increment)), ("color", color.rawValue),
            ])
        return try decode(Game.self, from: data).id
    }

    public func acceptChallenge(id: String) async throws { try await challengeAction(id, "accept") }
    public func declineChallenge(id: String) async throws { try await challengeAction(id, "decline") }
    public func cancelChallenge(id: String) async throws { try await challengeAction(id, "cancel") }

    // MARK: Validation

    private static func validGameID(_ id: String) throws -> String {
        guard isAlphanumeric(id) else { throw LichessError.invalidArgument("id") }
        return id
    }

    private static func isAlphanumeric(_ s: String) -> Bool {
        !s.isEmpty && s.utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x41 && $0 <= 0x5A) || ($0 >= 0x61 && $0 <= 0x7A) }
    }

    private static func validUsername(_ name: String) throws -> String {
        guard (2...30).contains(name.utf8.count),
              name.utf8.allSatisfy({ isAlphanumeric(String(UnicodeScalar($0))) || $0 == 0x5F || $0 == 0x2D })
        else { throw LichessError.invalidArgument("username") }
        return name
    }

    /// `[a-h][1-8][a-h][1-8][qrbn]?`
    static func isValidUCI(_ uci: String) -> Bool {
        let b = Array(uci.utf8)
        guard b.count == 4 || b.count == 5 else { return false }
        guard (0x61...0x68).contains(b[0]), (0x31...0x38).contains(b[1]),
              (0x61...0x68).contains(b[2]), (0x31...0x38).contains(b[3])
        else { return false }
        return b.count == 4 || "qrbn".utf8.contains(b[4])
    }

    private func gameAction(_ gameID: String, _ action: String) async throws {
        let id = try Self.validGameID(gameID)
        _ = try await send("POST", "api/board/game/\(id)/\(action)")
    }

    private func challengeAction(_ id: String, _ action: String) async throws {
        guard Self.isAlphanumeric(id) else { throw LichessError.invalidArgument("id") }
        _ = try await send("POST", "api/challenge/\(id)/\(action)")
    }

    // MARK: Transport

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw LichessError.decoding(String(describing: error))
        }
    }

    private func makeRequest(method: String, path: String, form: [(String, String)]?, accept: String) async throws -> URLRequest {
        try checkBackoff()
        var request = URLRequest(url: configuration.baseURL.appending(path: path))
        request.httpMethod = method
        request.setValue(configuration.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let form {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = LichessForm.encode(form)
        }
        return request
    }

    private func checkBackoff() throws {
        if let until = rateLimitedUntil {
            if now() < until { throw LichessError.rateLimited }
            rateLimitedUntil = nil
        }
    }

    private func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401: throw LichessError.unauthorized
        case 429:
            rateLimitedUntil = now().addingTimeInterval(Self.rateLimitBackoff)
            throw LichessError.rateLimited
        default: throw LichessError.http(status: response.statusCode)
        }
    }

    /// Queues behind every earlier request. Actor isolation alone would interleave requests
    /// at each `await`, so the requests are chained explicitly.
    private func send(_ method: String, _ path: String, form: [(String, String)]? = nil) async throws -> Data {
        let previous = tail
        let task = Task {
            await previous?.value
            return try await fetch(method: method, path: path, form: form)
        }
        tail = Task { _ = await task.result }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func fetch(method: String, path: String, form: [(String, String)]?) async throws -> Data {
        let request = try await makeRequest(method: method, path: path, form: form, accept: "application/json")
        let (data, response) = try await transport.data(for: request)
        try validate(response)
        return data
    }

    /// Streams are long-lived, so they bypass the one-at-a-time chain but honour the rate-limit back-off.
    private func stream<Element: Sendable>(
        method: String, path: String, form: [(String, String)]?,
        parse: @escaping @Sendable (String) throws -> Element?
    ) -> AsyncThrowingStream<Element, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try await makeRequest(method: method, path: path, form: form, accept: "application/x-ndjson")
                    let (response, lines) = try await transport.lines(for: request)
                    try validate(response)
                    for try await line in lines {
                        if let element = try parse(line) { continuation.yield(element) }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

enum LichessForm {
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ fields: [(String, String)]) -> Data {
        let body = fields.map { "\(escape($0.0))=\(escape($0.1))" }.joined(separator: "&")
        return Data(body.utf8)
    }

    private static func escape(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
