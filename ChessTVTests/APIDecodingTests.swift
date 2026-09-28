import XCTest
import Foundation
@testable import ChessTV

private struct StubHTTPClient: HTTPClient {
    let data: Data
    let status: Int
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (data, response)
    }
}

final class APIDecodingTests: XCTestCase {
    func testPlayerDecoding() async throws {
        let json = #"{"username":"sample_player","name":"Sample","joined":1700000000}"#.data(using: .utf8)!
        let client = ChessComAPIClient(http: StubHTTPClient(data: json, status: 200))
        let player = try await client.getPlayer(username: "sample_player")
        XCTAssertEqual(player.username, "sample_player")
        XCTAssertEqual(player.name, "Sample")
        XCTAssertNotNil(player.joined)
    }

    func testFriendlyNotFoundError() async {
        let client = ChessComAPIClient(http: StubHTTPClient(data: Data(), status: 404))
        do {
            _ = try await client.getPlayer(username: "missing")
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? APIError, .notFound)
        }
    }
}
