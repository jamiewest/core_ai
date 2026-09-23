import Foundation

#if canImport(CoreAI)
  import CoreAI
#endif

/// Error codes surfaced to Dart as `PlatformException.code`.
///
/// Keep in sync with `CoreAIErrorCode` in `lib/src/errors.dart`.
enum ErrorCode: String {
  case unsupported
  case invalidHandle = "invalid_handle"
  case invalidArgument = "invalid_argument"
  case notFound = "not_found"
  case busy
  case assetError = "asset_error"
  case coreAIError = "core_ai_error"
  case pixelBufferError = "pixel_buffer_error"
}

extension CoreAIPigeonError {
  convenience init(_ code: ErrorCode, _ message: String, details: String? = nil) {
    self.init(code: code.rawValue, message: message, details: details)
  }
}

enum Errors {
  static func invalidArgument(_ message: String) -> CoreAIPigeonError {
    CoreAIPigeonError(.invalidArgument, message)
  }

  static func notFound(_ message: String) -> CoreAIPigeonError {
    CoreAIPigeonError(.notFound, message)
  }

  static func invalidHandle(_ handle: Int64, expected: String) -> CoreAIPigeonError {
    CoreAIPigeonError(
      .invalidHandle,
      "Handle \(handle) is not a live \(expected). It may have been disposed.")
  }

  static func busy(_ handle: Int64) -> CoreAIPigeonError {
    CoreAIPigeonError(
      .busy,
      "Native value \(handle) is in use by another operation. Await that "
        + "operation before reusing the value.")
  }

  /// Converts any error thrown by Core AI (or by this plugin) into a
  /// `CoreAIPigeonError` with a stable code and a readable message.
  static func translate(_ error: any Error) -> CoreAIPigeonError {
    if let error = error as? CoreAIPigeonError {
      return error
    }
    #if canImport(CoreAI)
      if #available(iOS 27.0, macOS 27.0, *), let assetError = error as? AssetError {
        return CoreAIPigeonError(
          .assetError,
          assetError.errorDescription ?? "\(assetError.kind)",
          details: describeAssetErrorKind(assetError.kind))
      }
    #endif
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    return CoreAIPigeonError(
      .coreAIError, message, details: "\(String(reflecting: type(of: error))): \(error)")
  }

  #if canImport(CoreAI)
    @available(iOS 27.0, macOS 27.0, *)
    private static func describeAssetErrorKind(_ kind: AssetError.Kind) -> String {
      switch kind {
      case .unsupportedVersion(let version): return "unsupportedVersion(\(version))"
      case .invalidFeatureType(let type): return "invalidFeatureType(\(type))"
      case .corruptedMetadata: return "corruptedMetadata"
      case .invalidName: return "invalidName"
      case .duplicateName: return "duplicateName"
      @unknown default: return "\(kind)"
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
