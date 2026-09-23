import Foundation

/// Error codes surfaced to Dart as `PlatformException.code`.
///
/// Keep in sync with `SpeechErrorCode` in `lib/src/errors.dart`.
enum ErrorCode: String {
  case unsupported
  case invalidArgument = "invalid_argument"
  case notFound = "not_found"
  case notAuthorized = "not_authorized"
  case microphoneNotAuthorized = "microphone_not_authorized"
  case missingUsageDescription = "missing_usage_description"
  case unsupportedLocale = "unsupported_locale"
  case recognizerUnavailable = "recognizer_unavailable"
  case assetsNotInstalled = "assets_not_installed"
  case tooManyReservedLocales = "too_many_reserved_locales"
  case audioFormat = "audio_format"
  case audioReadFailed = "audio_read_failed"
  case microphoneUnavailable = "microphone_unavailable"
  case noSpeechDetected = "no_speech_detected"
  case insufficientResources = "insufficient_resources"
  case serviceUnavailable = "service_unavailable"
  case dictationDisabled = "dictation_disabled"
  case busy
  case timeout
  case cancelled
  case speechError = "speech_error"
}

extension AppleSpeechPigeonError {
  convenience init(_ code: ErrorCode, _ message: String, details: [String: Any] = [:]) {
    if details.isEmpty {
      self.init(code: code.rawValue, message: message, details: nil)
      return
    }
    let json = (try? JSONSerialization.data(withJSONObject: details)).flatMap {
      String(data: $0, encoding: .utf8)
    }
    self.init(code: code.rawValue, message: message, details: json)
  }

  /// The error as a callback message.
  var asMessage: ErrorMessage {
    ErrorMessage(code: code, message: message ?? code, details: details as? String)
  }
}

enum Errors {
  static func invalidArgument(_ message: String) -> AppleSpeechPigeonError {
    AppleSpeechPigeonError(.invalidArgument, message)
  }

  static func unsupported(_ message: String) -> AppleSpeechPigeonError {
    AppleSpeechPigeonError(.unsupported, message)
  }

  static func requires26(_ what: String) -> AppleSpeechPigeonError {
    unsupported("\(what) requires iOS 26 or macOS 26 or later.")
  }

  static func requires27(_ what: String) -> AppleSpeechPigeonError {
    unsupported("\(what) requires iOS 27 or macOS 27 or later.")
  }

  static func fileNotFound(_ path: String) -> AppleSpeechPigeonError {
    AppleSpeechPigeonError(.notFound, "No file at \(path).", details: ["path": path])
  }

  static func unsupportedLocale(_ locale: String, _ what: String) -> AppleSpeechPigeonError {
    AppleSpeechPigeonError(
      .unsupportedLocale, "\(what) does not support the locale \(locale).",
      details: ["locale": locale])
  }

  /// Converts any error into an `AppleSpeechPigeonError` with a stable code,
  /// a readable message, and the underlying domain and code in `details`.
  static func translate(_ error: any Error) -> AppleSpeechPigeonError {
    if let error = error as? AppleSpeechPigeonError { return error }
    if error is CancellationError {
      return AppleSpeechPigeonError(.cancelled, "The request was cancelled.")
    }
    let nsError = error as NSError
    let details: [String: Any] = ["domain": nsError.domain, "nativeCode": nsError.code]
    let described = nsError.localizedDescription
    func make(_ code: ErrorCode, _ message: String? = nil) -> AppleSpeechPigeonError {
      AppleSpeechPigeonError(code, message ?? described, details: details)
    }
    switch nsError.domain {
    case "SFSpeechErrorDomain":
      // Raw values from SFErrors.h and the Swift overlay (iOS/macOS 26+).
      switch nsError.code {
      case 2: return make(.audioReadFailed)
      case 3:
        return make(
          .audioFormat,
          "\(described). Speech also reports this when the locale's assets "
            + "are not installed; check AssetInventory.")
      case 4: return make(.assetsNotInstalled, "\(described). No model is installed.")
      case 5, 17: return make(.audioFormat)
      case 10:
        return make(
          .assetsNotInstalled,
          "\(described). The locale is not reserved; call AssetInventory.reserve.")
      case 11: return make(.tooManyReservedLocales)
      case 12: return make(.timeout)
      case 13: return make(.invalidArgument)
      case 15: return make(.unsupportedLocale)
      case 16: return make(.insufficientResources)
      case 18: return make(.microphoneUnavailable)
      default: return make(.speechError)
      }
    case "kAFAssistantErrorDomain":
      switch nsError.code {
      case 1100: return make(.busy)
      case 1101, 1107: return make(.serviceUnavailable)
      case 1110: return make(.noSpeechDetected)
      case 1700: return make(.notAuthorized)
      default: return make(.speechError)
      }
    case "kLSRErrorDomain":
      switch nsError.code {
      case 102: return make(.assetsNotInstalled)
      case 201: return make(.dictationDisabled)
      case 301: return make(.cancelled)
      default: return make(.speechError)
      }
    case "com.apple.coreaudio.avfaudio", NSOSStatusErrorDomain:
      return make(
        .audioReadFailed,
        "Could not read the audio (OSStatus \(fourCharCode(nsError.code))).")
    default:
      return make(.speechError)
    }
  }

  /// Renders an OSStatus as its four-character code when it has one.
  private static func fourCharCode(_ code: Int) -> String {
    let value = UInt32(truncatingIfNeeded: code)
    let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    if bytes.allSatisfy({ $0 >= 32 && $0 < 127 }) {
      return "'\(String(decoding: bytes, as: UTF8.self))'"
    }
    return String(code)
  }
}

/// Runs [body], translating thrown errors.
func translatingErrors<T>(_ body: () async throws -> T) async throws -> T {
  do {
    return try await body()
  } catch {
    throw Errors.translate(error)
  }
}

/// Runs [body], translating thrown errors.
func translatingErrors<T>(_ body: () throws -> T) throws -> T {
  do {
    return try body()
  } catch {
    throw Errors.translate(error)
  }
}
