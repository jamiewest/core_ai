import Foundation

#if canImport(Vision)
  import Vision
#endif

/// Error codes surfaced to Dart as `PlatformException.code`.
///
/// Keep in sync with `AppleVisionErrorCode` in `lib/src/errors.dart`.
enum ErrorCode: String {
  case unsupported
  case invalidArgument = "invalid_argument"
  case notFound = "not_found"
  case imageError = "image_error"
  case maskError = "mask_error"
  case visionError = "vision_error"
}

extension AppleVisionPigeonError {
  convenience init(_ code: ErrorCode, _ message: String, details: String? = nil) {
    self.init(code: code.rawValue, message: message, details: details)
  }
}

enum Errors {
  static func invalidArgument(_ message: String) -> AppleVisionPigeonError {
    AppleVisionPigeonError(.invalidArgument, message)
  }

  static func notFound(_ message: String) -> AppleVisionPigeonError {
    AppleVisionPigeonError(.notFound, message)
  }

  static func image(_ message: String) -> AppleVisionPigeonError {
    AppleVisionPigeonError(.imageError, message)
  }

  static func mask(_ message: String) -> AppleVisionPigeonError {
    AppleVisionPigeonError(.maskError, message)
  }

  /// Converts any error thrown by Vision (or by this plugin) into an
  /// `AppleVisionPigeonError` with a stable code and a readable message.
  static func translate(_ error: any Error) -> AppleVisionPigeonError {
    if let error = error as? AppleVisionPigeonError {
      return error
    }
    #if canImport(Vision)
      if #available(iOS 27.0, macOS 27.0, *), let error = error as? VisionError {
        return AppleVisionPigeonError(
          code: code(for: error).rawValue,
          message: error.errorDescription ?? "\(error)",
          details: "VisionError.\(kind(of: error))")
      }
    #endif
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    return AppleVisionPigeonError(
      .visionError, message, details: "\(String(reflecting: type(of: error))): \(error)")
  }

  /// The wire form of an error, for a per-request failure.
  static func message(_ error: AppleVisionPigeonError) -> ErrorMessage {
    ErrorMessage(
      code: error.code, message: error.message ?? error.code,
      details: error.details.map { String(describing: $0) })
  }

  #if canImport(Vision)
    @available(iOS 27.0, macOS 27.0, *)
    private static func code(for error: VisionError) -> ErrorCode {
      switch error {
      case .invalidArgument, .outOfBoundsError, .unsupportedRevision, .unsupportedComputeDevice,
        .unsupportedComputeStage, .unsupportedRequest:
        return .invalidArgument
      case .invalidImage, .invalidFormat:
        return .imageError
      case .pixelBufferCreationFailed:
        return .maskError
      default:
        return .visionError
      }
    }

    @available(iOS 27.0, macOS 27.0, *)
    private static func kind(of error: VisionError) -> String {
      switch error {
      case .dataUnavailable: return "dataUnavailable"
      case .internalError: return "internalError"
      case .invalidArgument: return "invalidArgument"
      case .invalidFormat: return "invalidFormat"
      case .invalidImage: return "invalidImage"
      case .invalidModel: return "invalidModel"
      case .invalidOperation: return "invalidOperation"
      case .ioError: return "ioError"
      case .operationFailed: return "operationFailed"
      case .outOfBoundsError: return "outOfBoundsError"
      case .outOfMemory: return "outOfMemory"
      case .pixelBufferCreationFailed: return "pixelBufferCreationFailed"
      case .requestCancelled: return "requestCancelled"
      case .timeout: return "timeout"
      case .timeStampNotFound: return "timeStampNotFound"
      case .unsupportedComputeDevice: return "unsupportedComputeDevice"
      case .unsupportedComputeStage: return "unsupportedComputeStage"
      case .unsupportedRequest: return "unsupportedRequest"
      case .unsupportedRevision: return "unsupportedRevision"
      @unknown default: return "unknown"
      }
    }
  #endif
}

/// Runs [body], translating any thrown error with `Errors.translate`.
func translatingErrors<T>(_ body: () async throws -> T) async throws -> T {
  do {
    return try await body()
  } catch {
    throw Errors.translate(error)
  }
}

/// Synchronous variant of `translatingErrors`.
func translatingErrors<T>(_ body: () throws -> T) throws -> T {
  do {
    return try body()
  } catch {
    throw Errors.translate(error)
  }
}
