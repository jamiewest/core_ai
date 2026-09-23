import Foundation

#if canImport(Translation)
  import Translation
#endif

/// Error codes surfaced to Dart as `PlatformException.code`.
///
/// Keep in sync with `TranslationErrorCode` in `lib/src/errors.dart`.
enum ErrorCode: String {
  case unsupported
  case invalidHandle = "invalid_handle"
  case invalidArgument = "invalid_argument"
  case unsupportedSourceLanguage = "unsupported_source_language"
  case unsupportedTargetLanguage = "unsupported_target_language"
  case unsupportedLanguagePairing = "unsupported_language_pairing"
  case unableToIdentifyLanguage = "unable_to_identify_language"
  case nothingToTranslate = "nothing_to_translate"
  case alreadyCancelled = "already_cancelled"
  case notInstalled = "not_installed"
  case internalError = "internal_error"
  case cancelled
  case translationError = "translation_error"
}

extension AppleTranslationPigeonError {
  convenience init(_ code: ErrorCode, _ message: String, details: String? = nil) {
    self.init(code: code.rawValue, message: message, details: details)
  }
}

enum Errors {
  static func invalidArgument(_ message: String) -> AppleTranslationPigeonError {
    AppleTranslationPigeonError(.invalidArgument, message)
  }

  static func unsupported(_ message: String) -> AppleTranslationPigeonError {
    AppleTranslationPigeonError(.unsupported, message)
  }

  static func invalidHandle(_ handle: Int64, expected: String) -> AppleTranslationPigeonError {
    AppleTranslationPigeonError(
      .invalidHandle,
      "Handle \(handle) is not a live \(expected). It may have been disposed.")
  }

  /// Converts any error into an `AppleTranslationPigeonError`.
  static func translate(_ error: any Error) -> AppleTranslationPigeonError {
    if let error = error as? AppleTranslationPigeonError { return error }
    if error is CancellationError {
      return AppleTranslationPigeonError(.cancelled, "The request was cancelled.")
    }
    #if canImport(Translation)
      if #available(iOS 18.0, macOS 15.0, *), let translated = translationError(error) {
        return translated
      }
    #endif
    let nsError = error as NSError
    return AppleTranslationPigeonError(
      .translationError, nsError.localizedDescription,
      details: "\(nsError.domain) \(nsError.code): \(error)")
  }

  #if canImport(Translation)
    /// Maps a `TranslationError` to its stable code. Returns nil for other
    /// errors.
    @available(iOS 18.0, macOS 15.0, *)
    private static func translationError(_ error: any Error) -> AppleTranslationPigeonError? {
      guard let translationError = error as? TranslationError else { return nil }
      let code: ErrorCode
      if TranslationError.unsupportedSourceLanguage ~= error {
        code = .unsupportedSourceLanguage
      } else if TranslationError.unsupportedTargetLanguage ~= error {
        code = .unsupportedTargetLanguage
      } else if TranslationError.unsupportedLanguagePairing ~= error {
        code = .unsupportedLanguagePairing
      } else if TranslationError.unableToIdentifyLanguage ~= error {
        code = .unableToIdentifyLanguage
      } else if TranslationError.nothingToTranslate ~= error {
        code = .nothingToTranslate
      } else if TranslationError.internalError ~= error {
        code = .internalError
      } else if #available(iOS 26.0, macOS 26.0, *),
        TranslationError.alreadyCancelled ~= error
      {
        code = .alreadyCancelled
      } else if #available(iOS 26.0, macOS 26.0, *), TranslationError.notInstalled ~= error {
        code = .notInstalled
      } else {
        code = .translationError
      }
      // `errorDescription` is usually the generic "Unable to Translate";
      // `failureReason` says what actually went wrong.
      let message =
        translationError.failureReason ?? translationError.errorDescription
        ?? "Translation failed."
      return AppleTranslationPigeonError(code, message, details: "\(error)")
    }
  #endif
}

/// Runs [body], translating any thrown error.
func translatingErrors<T>(_ body: () throws -> T) throws -> T {
  do { return try body() } catch { throw Errors.translate(error) }
}

/// Async variant of `translatingErrors`.
func translatingErrors<T>(_ body: () async throws -> T) async throws -> T {
  do { return try await body() } catch { throw Errors.translate(error) }
}
