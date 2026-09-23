import Foundation

#if canImport(MediaIntelligence)
  import MediaIntelligence
#endif

/// Error codes surfaced to Dart as `PlatformException.code`.
///
/// Keep in sync with `MediaIntelligenceErrorCode` in `lib/src/errors.dart`.
enum ErrorCode: String {
  case unsupported
  case invalidArgument = "invalid_argument"
  case invalidHandle = "invalid_handle"
  case notFound = "not_found"
  case workingDirectory = "working_directory"
  case mediaProcessing = "media_processing"
  case faceGroupProcessing = "face_group_processing"
  case resultFetching = "result_fetching"
  case mediaIntelligenceError = "media_intelligence_error"
}

extension MediaIntelligencePigeonError {
  convenience init(_ code: ErrorCode, _ message: String, details: String? = nil) {
    self.init(code: code.rawValue, message: message, details: details)
  }
}

enum Errors {
  static func invalidArgument(_ message: String) -> MediaIntelligencePigeonError {
    MediaIntelligencePigeonError(.invalidArgument, message)
  }

  static func notFound(_ message: String) -> MediaIntelligencePigeonError {
    MediaIntelligencePigeonError(.notFound, message)
  }

  static func invalidHandle(_ handle: Int64) -> MediaIntelligencePigeonError {
    MediaIntelligencePigeonError(
      .invalidHandle, "Handle \(handle) is not a live FaceGroupAnalyzer. It may have been disposed.")
  }

  /// Converts any error into a `MediaIntelligencePigeonError`.
  static func translate(_ error: any Error) -> MediaIntelligencePigeonError {
    if let error = error as? MediaIntelligencePigeonError { return error }
    #if canImport(MediaIntelligence)
      if #available(iOS 27.0, macOS 27.0, *), let error = error as? MediaIntelligenceError {
        let code: ErrorCode =
          switch error {
          case .workingDirectory: .workingDirectory
          case .mediaProcessing: .mediaProcessing
          case .faceGroupProcessing: .faceGroupProcessing
          case .resultFetching: .resultFetching
          @unknown default: .mediaIntelligenceError
          }
        return MediaIntelligencePigeonError(
          code, error.errorDescription ?? "\(error)", details: "MediaIntelligenceError.\(error)")
      }
    #endif
    let nsError = error as NSError
    return MediaIntelligencePigeonError(
      .mediaIntelligenceError, nsError.localizedDescription,
      details: "\(nsError.domain) \(nsError.code)")
  }

  /// The error as a message for one failed request.
  static func requestError(_ error: any Error) -> RequestErrorMessage {
    let error = translate(error)
    return RequestErrorMessage(
      code: error.code, message: error.message ?? error.code, details: error.details as? String)
  }
}

/// Runs [body], translating any thrown error.
func translatingErrors<T>(_ body: () async throws -> T) async throws -> T {
  do { return try await body() } catch { throw Errors.translate(error) }
}
