import Foundation

#if canImport(CoreML)
  import CoreML
#endif

/// Error codes surfaced to Dart as `PlatformException.code`.
///
/// Keep in sync with `CoreMLErrorCode` in `lib/src/errors.dart`.
enum ErrorCode: String {
  case unsupported
  case invalidHandle = "invalid_handle"
  case invalidArgument = "invalid_argument"
  case notFound = "not_found"
  case busy
  case featureType = "feature_type"
  case ioError = "io_error"
  case modelDecryption = "model_decryption"
  case predictionCancelled = "prediction_cancelled"
  case customModel = "custom_model"
  case updateError = "update_error"
  case parameters
  case coreMLError = "core_ml_error"
  case pixelBufferError = "pixel_buffer_error"
}

extension CoreMLPigeonError {
  convenience init(_ code: ErrorCode, _ message: String, details: String? = nil) {
    self.init(code: code.rawValue, message: message, details: details)
  }
}

enum Errors {
  static func invalidArgument(_ message: String) -> CoreMLPigeonError {
    CoreMLPigeonError(.invalidArgument, message)
  }

  static func notFound(_ message: String) -> CoreMLPigeonError {
    CoreMLPigeonError(.notFound, message)
  }

  static func unsupported(_ message: String) -> CoreMLPigeonError {
    CoreMLPigeonError(.unsupported, message)
  }

  static func invalidHandle(_ handle: Int64, expected: String) -> CoreMLPigeonError {
    CoreMLPigeonError(
      .invalidHandle,
      "Handle \(handle) is not a live \(expected). It may have been disposed.")
  }

  static func busy(_ handle: Int64) -> CoreMLPigeonError {
    CoreMLPigeonError(
      .busy,
      "MLState \(handle) is already in use. Core ML requires predictions that share a "
        + "state to be serialized; await the previous prediction first.")
  }

  /// Converts any error thrown by Core ML (or by this plugin) into a
  /// `CoreMLPigeonError` with a stable code and a readable message.
  static func translate(_ error: any Error) -> CoreMLPigeonError {
    if let error = error as? CoreMLPigeonError {
      return error
    }
    let nsError = error as NSError
    #if canImport(CoreML)
      if nsError.domain == MLModelErrorDomain {
        return CoreMLPigeonError(
          code(for: nsError.code), nsError.localizedDescription,
          details: "MLModelError(\(nsError.code))")
      }
    #endif
    if nsError.domain == NSCocoaErrorDomain || nsError.domain == NSPOSIXErrorDomain {
      return CoreMLPigeonError(
        .ioError, nsError.localizedDescription,
        details: "\(nsError.domain)(\(nsError.code))")
    }
    return CoreMLPigeonError(
      .coreMLError, nsError.localizedDescription,
      details: "\(nsError.domain)(\(nsError.code))")
  }

  #if canImport(CoreML)
    private static func code(for modelErrorCode: Int) -> ErrorCode {
      switch MLModelError.Code(rawValue: modelErrorCode) {
      case .featureType: return .featureType
      case .io: return .ioError
      case .customLayer, .customModel: return .customModel
      case .update: return .updateError
      case .parameters: return .parameters
      case .modelDecryption, .modelDecryptionKeyFetch: return .modelDecryption
      case .predictionCancelled: return .predictionCancelled
      default: return .coreMLError
      }
    }
  #endif
}

/// Runs [body], translating any thrown error with `Errors.translate`.
func translatingErrors<T>(_ body: () throws -> T) throws -> T {
  do {
    return try body()
  } catch {
    throw Errors.translate(error)
  }
}

/// Async variant of `translatingErrors`.
func translatingErrors<T>(_ body: () async throws -> T) async throws -> T {
  do {
    return try await body()
  } catch {
    throw Errors.translate(error)
  }
}

/// The URL of an existing file or directory, or a `not_found` error.
func existingFileURL(_ path: String) throws -> URL {
  let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
  guard FileManager.default.fileExists(atPath: url.path) else {
    throw Errors.notFound("No file or directory at '\(url.path)'.")
  }
  return url
}
