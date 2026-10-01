import Foundation

extension HTTPURLResponse {
  /// Returns when the status is 2xx. Otherwise throws the error that `failure` makes from the
  /// response, so each client keeps its own error type.
  public func validateStatus<Failure: Error>(
    _ failure: (HTTPURLResponse) -> Failure
  ) throws(Failure) {
    guard (200..<300).contains(statusCode) else { throw failure(self) }
  }
}
