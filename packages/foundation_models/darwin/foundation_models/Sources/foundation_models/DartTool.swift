#if canImport(FoundationModels)
  import FoundationModels
  import Foundation

  /// A `Tool` whose implementation lives in Dart.
  ///
  /// `call(arguments:)` runs while `respond` is still in flight: it sends the
  /// arguments to Dart through the callback API and waits for the result, so
  /// the Dart handler must not start another request on the same session.
  @available(iOS 26.0, macOS 26.0, *)
  struct DartTool: Tool {
    typealias Arguments = GeneratedContent
    typealias Output = GeneratedContent

    let name: String
    let description: String
    let parameters: GenerationSchema
    let includesSchemaInInstructions: Bool
    let callback: CallbackBox
    /// Set once the session has a handle, so Dart can route the call.
    let sessionHandle: HandleBox

    func call(arguments: GeneratedContent) async throws -> GeneratedContent {
      let request = ToolCallRequestMessage(
        sessionHandle: sessionHandle.value,
        toolName: name,
        argumentsJson: arguments.jsonString)
      let result = try await callback.api.callTool(request: request)
      if let json = result.contentJson {
        return try GeneratedContent(json: json)
      }
      return GeneratedContent(result.text ?? "")
    }
  }

  /// Holds the callback API, which Pigeon does not declare `Sendable`.
  final class CallbackBox: @unchecked Sendable {
    let api: FoundationModelsCallbackApiProtocol

    init(_ api: FoundationModelsCallbackApiProtocol) { self.api = api }
  }

  /// A mutable handle shared with the tools of a session.
  final class HandleBox: @unchecked Sendable {
    private let lock = NSLock()
    private var handle: Int64 = 0

    var value: Int64 {
      get { lock.withLock { handle } }
      set { lock.withLock { handle = newValue } }
    }
  }
#endif
