import Foundation

/// Error codes surfaced to Dart as `PlatformException.code`.
///
/// Keep in sync with `NaturalLanguageErrorCode` in `lib/src/errors.dart`.
enum ErrorCode: String {
  case unsupported
  case invalidHandle = "invalid_handle"
  case invalidArgument = "invalid_argument"
  case notFound = "not_found"
  case assetsUnavailable = "assets_unavailable"
  case naturalLanguageError = "natural_language_error"
}

extension AppleNaturalLanguagePigeonError {
  convenience init(_ code: ErrorCode, _ message: String, details: String? = nil) {
    self.init(code: code.rawValue, message: message, details: details)
  }
}

enum Errors {
  static func invalidArgument(_ message: String) -> AppleNaturalLanguagePigeonError {
    AppleNaturalLanguagePigeonError(.invalidArgument, message)
  }

  static func notFound(_ message: String) -> AppleNaturalLanguagePigeonError {
    AppleNaturalLanguagePigeonError(.notFound, message)
  }

  static func invalidHandle(_ handle: Int64, expected: String) -> AppleNaturalLanguagePigeonError
  {
    AppleNaturalLanguagePigeonError(
      .invalidHandle,
      "Handle \(handle) is not a live \(expected). It may have been disposed.")
  }

  /// Converts any error into a `AppleNaturalLanguagePigeonError`.
  static func translate(_ error: any Error) -> AppleNaturalLanguagePigeonError {
    if let error = error as? AppleNaturalLanguagePigeonError { return error }
    let nsError = error as NSError
    return AppleNaturalLanguagePigeonError(
      .naturalLanguageError, nsError.localizedDescription,
      details: "\(nsError.domain) \(nsError.code)")
  }
}

/// Runs [body], translating any thrown error.
func translatingErrors<T>(_ body: () throws -> T) throws -> T {
  do { return try body() } catch { throw Errors.translate(error) }
}

/// Async variant of `translatingErrors`.
func translatingErrors<T>(_ body: () async throws -> T) async throws -> T {
  do { return try await body() } catch { throw Errors.translate(error) }
}
