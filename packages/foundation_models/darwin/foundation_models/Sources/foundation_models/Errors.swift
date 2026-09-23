import Foundation

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Error codes surfaced to Dart as `PlatformException.code`.
///
/// Keep in sync with `FoundationModelsErrorCode` in `lib/src/errors.dart`.
enum ErrorCode: String {
  case unsupported
  case invalidHandle = "invalid_handle"
  case invalidArgument = "invalid_argument"
  case notFound = "not_found"
  case modelUnavailable = "model_unavailable"
  case assetsUnavailable = "assets_unavailable"
  case contextWindowExceeded = "context_window_exceeded"
  case guardrailViolation = "guardrail_violation"
  case refusal
  case unsupportedGuide = "unsupported_guide"
  case unsupportedLanguage = "unsupported_language"
  case unsupportedCapability = "unsupported_capability"
  case unsupportedTranscriptContent = "unsupported_transcript_content"
  case decodingFailure = "decoding_failure"
  case rateLimited = "rate_limited"
  case quotaLimitReached = "quota_limit_reached"
  case networkFailure = "network_failure"
  case serviceUnavailable = "service_unavailable"
  case timeout
  case concurrentRequests = "concurrent_requests"
  case toolCallFailed = "tool_call_failed"
  case schemaError = "schema_error"
  case adapterError = "adapter_error"
  case cancelled
  case foundationModelsError = "foundation_models_error"
}

extension FoundationModelsPigeonError {
  convenience init(_ code: ErrorCode, _ message: String, details: [String: Any] = [:]) {
    var payload = details
    if payload.isEmpty {
      self.init(code: code.rawValue, message: message, details: nil)
      return
    }
    payload["code"] = code.rawValue
    let json = (try? JSONSerialization.data(withJSONObject: payload)).flatMap {
      String(data: $0, encoding: .utf8)
    }
    self.init(code: code.rawValue, message: message, details: json)
  }
}

enum Errors {
  static func invalidArgument(_ message: String) -> FoundationModelsPigeonError {
    FoundationModelsPigeonError(.invalidArgument, message)
  }

  static func notFound(_ message: String) -> FoundationModelsPigeonError {
    FoundationModelsPigeonError(.notFound, message)
  }

  static func invalidHandle(_ handle: Int64, expected: String) -> FoundationModelsPigeonError {
    FoundationModelsPigeonError(
      .invalidHandle,
      "Handle \(handle) is not a live \(expected). It may have been disposed.")
  }

  static func requires27(_ what: String) -> FoundationModelsPigeonError {
    FoundationModelsPigeonError(
      .unsupported, "\(what) requires iOS 27 or macOS 27 or later.")
  }

  /// Converts any error into a `FoundationModelsPigeonError` with a stable
  /// code, a readable message and structured details.
  static func translate(_ error: any Error) -> FoundationModelsPigeonError {
    if let error = error as? FoundationModelsPigeonError { return error }
    if error is CancellationError {
      return FoundationModelsPigeonError(.cancelled, "The request was cancelled.")
    }
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        if let error = error as? LanguageModelSession.GenerationError {
          return translateGenerationError(error)
        }
        if let error = error as? LanguageModelSession.ToolCallError {
          return FoundationModelsPigeonError(
            .toolCallFailed,
            "Tool '\(error.tool.name)' failed: "
              + "\(error.underlyingError.localizedDescription)",
            details: ["tool": error.tool.name])
        }
        if let error = error as? GenerationSchema.SchemaError {
          return FoundationModelsPigeonError(
            .schemaError, error.errorDescription ?? "\(error)")
        }
        if let error = error as? SystemLanguageModel.Adapter.AssetError {
          return FoundationModelsPigeonError(
            .adapterError, error.errorDescription ?? "\(error)")
        }
      }
      if #available(iOS 27.0, macOS 27.0, *) {
        if let error = error as? LanguageModelSession.Error {
          switch error {
          case .concurrentRequests:
            return FoundationModelsPigeonError(
              .concurrentRequests,
              "This session is already responding. Await the previous "
                + "response, or use another session.")
          default:
            return FoundationModelsPigeonError(
              .foundationModelsError, error.errorDescription ?? "\(error)")
          }
        }
        if let error = error as? LanguageModelError { return translateModelError(error) }
        if let error = error as? PrivateCloudComputeLanguageModel.Error {
          return translatePrivateCloudError(error)
        }
      }
    #endif
    let message = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    return FoundationModelsPigeonError(
      .foundationModelsError, message,
      details: ["type": "\(type(of: error))", "debug": "\(error)"])
  }

  #if canImport(FoundationModels)
    @available(iOS 26.0, macOS 26.0, *)
    private static func translateGenerationError(
      _ error: LanguageModelSession.GenerationError
    ) -> FoundationModelsPigeonError {
      let message = error.errorDescription ?? "\(error)"
      switch error {
      case .exceededContextWindowSize:
        return FoundationModelsPigeonError(.contextWindowExceeded, message)
      case .assetsUnavailable:
        return FoundationModelsPigeonError(.assetsUnavailable, message)
      case .guardrailViolation:
        return FoundationModelsPigeonError(.guardrailViolation, message)
      case .unsupportedGuide:
        return FoundationModelsPigeonError(.unsupportedGuide, message)
      case .unsupportedLanguageOrLocale:
        return FoundationModelsPigeonError(.unsupportedLanguage, message)
      case .decodingFailure:
        return FoundationModelsPigeonError(.decodingFailure, message)
      case .rateLimited:
        return FoundationModelsPigeonError(.rateLimited, message)
      case .concurrentRequests:
        return FoundationModelsPigeonError(.concurrentRequests, message)
      case .refusal:
        return FoundationModelsPigeonError(.refusal, message)
      @unknown default:
        return FoundationModelsPigeonError(.foundationModelsError, message)
      }
    }

    @available(iOS 27.0, macOS 27.0, *)
    private static func translateModelError(_ error: LanguageModelError)
      -> FoundationModelsPigeonError
    {
      let message = error.errorDescription ?? "\(error)"
      switch error {
      case .contextSizeExceeded(let context):
        return FoundationModelsPigeonError(
          .contextWindowExceeded, message,
          details: ["contextSize": context.contextSize, "tokenCount": context.tokenCount])
      case .rateLimited(let limited):
        return FoundationModelsPigeonError(
          .rateLimited, message,
          details: limited.resetDate.map {
            ["resetDateMillis": Int($0.timeIntervalSince1970 * 1000)]
          } ?? [:])
      case .guardrailViolation:
        return FoundationModelsPigeonError(.guardrailViolation, message)
      case .refusal(let refusal):
        return FoundationModelsPigeonError(
          .refusal, message, details: ["debug": refusal.debugDescription])
      case .unsupportedCapability(let unsupported):
        return FoundationModelsPigeonError(
          .unsupportedCapability, message,
          details: ["capability": "\(unsupported.capability)"])
      case .unsupportedTranscriptContent:
        return FoundationModelsPigeonError(.unsupportedTranscriptContent, message)
      case .unsupportedGenerationGuide:
        return FoundationModelsPigeonError(.unsupportedGuide, message)
      case .unsupportedLanguageOrLocale(let unsupported):
        return FoundationModelsPigeonError(
          .unsupportedLanguage, message,
          details: ["language": "\(unsupported.languageCode)"])
      case .timeout:
        return FoundationModelsPigeonError(.timeout, message)
      @unknown default:
        return FoundationModelsPigeonError(.foundationModelsError, message)
      }
    }

    @available(iOS 27.0, macOS 27.0, *)
    private static func translatePrivateCloudError(
      _ error: PrivateCloudComputeLanguageModel.Error
    ) -> FoundationModelsPigeonError {
      let message = error.errorDescription ?? "\(error)"
      switch error {
      case .networkFailure:
        return FoundationModelsPigeonError(.networkFailure, message)
      case .quotaLimitReached(let quota):
        var details: [String: Any] = [
          "hasLimitIncreaseSuggestion": quota.limitIncreaseSuggestion != nil
        ]
        if let reset = quota.resetDate {
          details["resetDateMillis"] = Int(reset.timeIntervalSince1970 * 1000)
        }
        return FoundationModelsPigeonError(.quotaLimitReached, message, details: details)
      case .serviceUnavailable:
        return FoundationModelsPigeonError(.serviceUnavailable, message)
      @unknown default:
        return FoundationModelsPigeonError(.foundationModelsError, message)
      }
    }
  #endif
}

/// Runs [body], translating any thrown error with `Errors.translate`.
func translatingErrors<T>(_ body: () throws -> T) throws -> T {
  do { return try body() } catch { throw Errors.translate(error) }
}

/// Async variant of `translatingErrors`.
func translatingErrors<T>(_ body: () async throws -> T) async throws -> T {
  do { return try await body() } catch { throw Errors.translate(error) }
}
