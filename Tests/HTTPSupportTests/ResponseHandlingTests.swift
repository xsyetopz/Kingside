import Foundation
import Testing

import HTTPSupport

private enum ClientError: Error, Equatable {
  case decoding(String)
  case status(Int)
}

private struct Stamp: Decodable, Equatable {
  let at: Date
}

private func response(status: Int) throws -> HTTPURLResponse {
  let url = try #require(URL(string: "https://api.example.test/"))
  return try #require(
    HTTPURLResponse(
      url: url,
      statusCode: status,
      httpVersion: nil,
      headerFields: nil
    )
  )
}

@Suite
struct JSONBodyDecoderTests {
  @Test
  func decodesWithTheDateStrategy() throws {
    let decoder = JSONBodyDecoder(
      dateDecodingStrategy: .secondsSince1970,
      failure: ClientError.decoding
    )
    let stamp = try decoder.decode(Stamp.self, from: Data(#"{"at": 1700000000}"#.utf8))
    #expect(stamp == Stamp(at: Date(timeIntervalSince1970: 1_700_000_000)))
  }

  @Test
  func malformedBodyThrowsTheClientError() {
    let decoder = JSONBodyDecoder(failure: ClientError.decoding)
    #expect {
      try decoder.decode(Stamp.self, from: Data("not json".utf8))
    } throws: { error in
      guard case .decoding(let description) = error as? ClientError else { return false }
      return description.contains("dataCorrupted")
    }
  }
}

@Suite
struct StatusValidationTests {
  @Test(arguments: [200, 204, 299])
  func successStatusPasses(status: Int) throws {
    try response(status: status).validateStatus { ClientError.status($0.statusCode) }
  }

  @Test(arguments: [199, 300, 304, 404, 429, 500])
  func otherStatusThrowsTheClientError(status: Int) throws {
    let response = try response(status: status)
    #expect(throws: ClientError.status(status)) {
      try response.validateStatus { ClientError.status($0.statusCode) }
    }
  }
}

@Suite
struct URLSessionTransportTests {
  @Test
  func nonHTTPResponseThrowsInvalidResponse() async throws {
    let request = URLRequest(url: try #require(URL(string: "data:,hello")))
    await #expect(throws: HTTPTransportError.invalidResponse) {
      try await URLSessionTransport().data(for: request)
    }
  }
}
