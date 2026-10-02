import Foundation
import HTTPSupportTests
import Testing
@testable import ChessComLink

let testConfiguration = ChessComConfiguration(
  baseURL: URL(string: "https://pub.example.test/pub/")!,
  userAgent: "KingsideTests/1.0 (contact: tests@example.invalid)"
)

func fixture(_ name: String) throws -> Data {
  let url = try #require(
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
  )
  return try Data(contentsOf: url)
}

func makeClient(_ handler: @escaping FakeTransport.Handler) -> (ChessComClient, FakeTransport) {
  let transport = FakeTransport(handler: handler)
  return (ChessComClient(configuration: testConfiguration, transport: transport), transport)
}
