import Foundation

#if canImport(SoundAnalysis)
  import SoundAnalysis
#endif

/// Error codes surfaced to Dart as `PlatformException.code`.
///
/// Keep in sync with `SoundAnalysisErrorCode` in `lib/src/errors.dart`.
enum ErrorCode: String {
  case unsupported
  case invalidArgument = "invalid_argument"
  case notFound = "not_found"
  case notRunning = "not_running"
  case busy
  case permissionDenied = "permission_denied"
  case noInputDevice = "no_input_device"
  case invalidFile = "invalid_file"
  case invalidFormat = "invalid_format"
  case invalidModel = "invalid_model"
  case operationFailed = "operation_failed"
  case soundAnalysisError = "sound_analysis_error"
}

extension AppleSoundAnalysisPigeonError {
  convenience init(_ code: ErrorCode, _ message: String, details: String? = nil) {
    self.init(code: code.rawValue, message: message, details: details)
  }
}

enum Errors {
  static func invalidArgument(_ message: String) -> AppleSoundAnalysisPigeonError {
    AppleSoundAnalysisPigeonError(.invalidArgument, message)
  }

  static func notFound(_ message: String) -> AppleSoundAnalysisPigeonError {
    AppleSoundAnalysisPigeonError(.notFound, message)
  }

  static func notRunning(_ requestId: Int64) -> AppleSoundAnalysisPigeonError {
    AppleSoundAnalysisPigeonError(
      .notRunning,
      "No stream analysis \(requestId) is running. It may have finished or been cancelled.")
  }

  /// Converts any error into a `AppleSoundAnalysisPigeonError`.
  static func translate(_ error: any Error) -> AppleSoundAnalysisPigeonError {
    if let error = error as? AppleSoundAnalysisPigeonError { return error }
    let nsError = error as NSError
    let details = "\(nsError.domain) \(nsError.code)"
    #if canImport(SoundAnalysis)
      if nsError.domain == SNErrorDomain {
        let code: ErrorCode =
          switch SNError.Code(rawValue: nsError.code) {
          case .operationFailed: .operationFailed
          case .invalidFormat: .invalidFormat
          case .invalidModel: .invalidModel
          case .invalidFile: .invalidFile
          default: .soundAnalysisError
          }
        return AppleSoundAnalysisPigeonError(code, nsError.localizedDescription, details: details)
      }
    #endif
    if nsError.domain == "com.apple.CoreML" {
      return AppleSoundAnalysisPigeonError(
        .invalidModel, nsError.localizedDescription, details: details)
    }
    return AppleSoundAnalysisPigeonError(
      .soundAnalysisError, nsError.localizedDescription, details: details)
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
