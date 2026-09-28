import Foundation

struct ChessComAPIClient: ChessAPI {
    private let http: any HTTPClient
    private let decoder = JSONDecoder()
    private let baseURL = URL(string: "https://api.chess.com/pub")!

    init(http: any HTTPClient = URLSessionHTTPClient()) { self.http = http }

    func getPlayer(username: String) async throws -> Player {
        try await request(path: "player/\(safe(username))", as: Player.self)
    }

    func getGames(username: String) async throws -> [OnlineGame] {
        struct Archives: Decodable { let archives: [URL] }
        struct Games: Decodable { let games: [OnlineGame] }
        let archive = try await request(path: "player/\(safe(username))/games/archives", as: Archives.self)
        guard let latest = archive.archives.last else { return [] }
        var request = URLRequest(url: latest)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await http.data(for: request)
        try validate(response)
        return (try? decoder.decode(Games.self, from: data).games) ?? []
    }

    func getTournaments() async throws -> [Tournament] {
        // PubAPI tournaments are identifier/round scoped and provide no documented global feed.
        throw APIError.unsupported
    }

    private func request<T: Decodable>(path: String, as type: T.Type) async throws -> T {
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let (data, response) = try await http.data(for: request)
                try validate(response)
                do { return try decoder.decode(T.self, from: data) }
                catch { throw APIError.decoding }
            } catch let error as APIError where attempt == 0 && [.timedOut, .server(500), .server(502), .server(503)].contains(error) {
                lastError = error
                try await Task.sleep(for: .milliseconds(350))
            }
        }
        throw lastError ?? APIError.invalidResponse
    }

    private func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300: return
        case 401, 403: throw APIError.unauthorized
        case 404: throw APIError.notFound
        case 429: throw APIError.rateLimited
        case 500...599: throw APIError.server(response.statusCode)
        default: throw APIError.invalidResponse
        }
    }

    private func safe(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ""
    }

    private var userAgent: String { "ChessTV/1.0 (tvOS)" }
}

struct MockChessAPIClient: ChessAPI {
    var player: Player?
    var games: [OnlineGame] = []
    var error: APIError?

    func getPlayer(username: String) async throws -> Player {
        if let error { throw error }
        guard let player else { throw APIError.notFound }
        return player
    }
    func getGames(username: String) async throws -> [OnlineGame] { if let error { throw error }; return games }
    func getTournaments() async throws -> [Tournament] { if let error { throw error }; return [] }
}
