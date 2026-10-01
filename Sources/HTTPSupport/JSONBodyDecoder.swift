import Foundation

/// Decodes JSON response bodies and reports a malformed body as the client's own error.
public struct JSONBodyDecoder<Failure: Error>: Sendable {
  private let dateDecodingStrategy: JSONDecoder.DateDecodingStrategy
  private let failure: @Sendable (String) -> Failure

  // @preconcurrency would weaken Sendable checks for Swift 6 callers; this API has no older ones.
  // swiftlint:disable incompatible_concurrency_annotation
  /// `failure` receives a description of the decoding error.
  public init(
    dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .deferredToDate,
    failure: @escaping @Sendable (String) -> Failure
  ) {
    self.dateDecodingStrategy = dateDecodingStrategy
    self.failure = failure
  }
  // swiftlint:enable incompatible_concurrency_annotation

  public func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(Failure) -> T {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = dateDecodingStrategy
    do {
      return try decoder.decode(type, from: data)
    } catch {
      throw failure(String(describing: error))
    }
  }
}
