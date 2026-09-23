#if canImport(FoundationModels)
  import FoundationModels
  import Foundation

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Implements `FoundationModelsHostApi` on top of Foundation Models.
  ///
  /// Async methods are nonisolated, so their bodies run off the platform
  /// thread even though Pigeon starts them from a main-actor task.
  @available(iOS 26.0, macOS 26.0, *)
  final class FoundationModelsHostApiImpl: FoundationModelsHostApi, @unchecked Sendable {
    let registry = HandleRegistry()
    private let requests = RequestRegistry()
    private let callback: CallbackBox

    init(callback: FoundationModelsCallbackApiProtocol) {
      self.callback = CallbackBox(callback)
    }

    func shutdown() {
      requests.cancelAll()
      _ = registry.removeAll()
    }

    // MARK: - Models

    func availability(model: ModelConfigMessage) async throws -> AvailabilityMessage {
      try translatingErrors {
        AvailabilityMessage(
          status: Conversions.availability(try Conversions.model(model, registry: registry)))
      }
    }

    func modelInfo(model: ModelConfigMessage) async throws -> ModelInfoMessage {
      try await translatingErrors {
        switch try Conversions.model(model, registry: registry) {
        case .system(let system):
          var capabilities: [CapabilityMessage] = []
          var variant: String?
          if #available(iOS 27.0, macOS 27.0, *) {
            capabilities = Conversions.capabilities(system.capabilities)
            variant = system.variant.displayName
          }
          return ModelInfoMessage(
            contextSize: Int64(system.contextSize), variantName: variant,
            capabilities: capabilities,
            supportedLanguages: Conversions.languages(system.supportedLanguages))
        case .privateCloudCompute:
          guard #available(iOS 27.0, macOS 27.0, *),
            let cloud = try Conversions.model(model, registry: registry).cloudModel
          else {
            throw Errors.requires27("The Private Cloud Compute model")
          }
          return ModelInfoMessage(
            contextSize: Int64(try await cloud.contextSize), variantName: nil,
            capabilities: Conversions.capabilities(cloud.capabilities),
            supportedLanguages: Conversions.languages(try await cloud.supportedLanguages))
        }
      }
    }

    func supportsLocale(model: ModelConfigMessage, localeIdentifier: String?) async throws
      -> Bool
    {
      try await translatingErrors {
        let locale = localeIdentifier.map(Locale.init(identifier:)) ?? Locale.current
        switch try Conversions.model(model, registry: registry) {
        case .system(let system):
          return system.supportsLocale(locale)
        case .privateCloudCompute:
          guard #available(iOS 27.0, macOS 27.0, *),
            let cloud = try Conversions.model(model, registry: registry).cloudModel
          else {
            throw Errors.requires27("The Private Cloud Compute model")
          }
          return try await cloud.supportsLocale(locale)
        }
      }
    }

    func tokenCount(model: ModelConfigMessage, request: TokenCountRequestMessage)
      async throws -> Int64
    {
      try await translatingErrors {
        guard #available(iOS 26.4, macOS 26.4, *) else {
          throw FoundationModelsPigeonError(
            .unsupported, "Token counting requires iOS 26.4 or macOS 26.4 or later.")
        }
        guard case .system(let system) = try Conversions.model(model, registry: registry)
        else {
          throw FoundationModelsPigeonError(
            .unsupported, "Token counting is only available for the on-device model.")
        }
        var total = 0
        if let prompt = request.prompt {
          total += try await system.tokenCount(for: try Conversions.prompt(prompt))
        }
        if let instructions = request.instructions {
          total += try await system.tokenCount(for: Instructions(instructions))
        }
        if !request.tools.isEmpty {
          let box = HandleBox()
          let tools = try Conversions.tools(
            request.tools, builtIn: [], callback: callback, sessionHandle: box)
          total += try await system.tokenCount(for: tools)
        }
        if let schemaJson = request.schemaJson {
          total += try await system.tokenCount(for: try Conversions.schema(schemaJson))
        }
        if let transcriptJson = request.transcriptJson {
          let transcript = try Conversions.transcript(json: transcriptJson)
          total += try await system.tokenCount(for: Array(transcript))
        }
        return Int64(total)
      }
    }

    func privateCloudComputeQuota() async throws -> QuotaUsageMessage {
      try translatingErrors {
        guard #available(iOS 27.0, macOS 27.0, *) else {
          throw Errors.requires27("Private Cloud Compute")
        }
        let usage = PrivateCloudComputeLanguageModel().quotaUsage
        var isApproaching = false
        if case .belowLimit(let below) = usage.status {
          isApproaching = below.isApproachingLimit
        }
        return QuotaUsageMessage(
          isLimitReached: usage.isLimitReached,
          isApproachingLimit: isApproaching,
          resetDateMillis: usage.resetDate.map { Int64($0.timeIntervalSince1970 * 1000) },
          hasLimitIncreaseSuggestion: usage.limitIncreaseSuggestion != nil)
      }
    }

    func showQuotaLimitIncreaseSuggestion() throws {
      guard #available(iOS 27.0, macOS 27.0, *) else {
        throw Errors.requires27("Private Cloud Compute")
      }
      PrivateCloudComputeLanguageModel().quotaUsage.limitIncreaseSuggestion?.show()
    }

    // MARK: - Adapters

    func loadAdapter(path: String?, name: String?) async throws -> AdapterInfoMessage {
      try translatingErrors {
        let adapter: SystemLanguageModel.Adapter
        if let path {
          let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
          guard FileManager.default.fileExists(atPath: url.path) else {
            throw Errors.notFound("No adapter at '\(url.path)'.")
          }
          adapter = try SystemLanguageModel.Adapter(fileURL: url)
        } else if let name {
          adapter = try SystemLanguageModel.Adapter(name: name)
        } else {
          throw Errors.invalidArgument("An adapter needs a path or a name.")
        }
        let metadata = adapter.creatorDefinedMetadata.compactMapValues { "\($0)" }
        let json = (try? JSONSerialization.data(withJSONObject: metadata)).map {
          String(decoding: $0, as: UTF8.self)
        }
        return AdapterInfoMessage(
          handle: registry.insert(.adapter(adapter)),
          creatorDefinedMetadataJson: json ?? "{}")
      }
    }

    func compileAdapter(adapterHandle: Int64) async throws {
      try await translatingErrors { try await registry.adapter(adapterHandle).compile() }
    }

    func compatibleAdapterIdentifiers(name: String) throws -> [String] {
      SystemLanguageModel.Adapter.compatibleAdapterIdentifiers(name: name)
    }

    func removeObsoleteAdapters() async throws {
      try translatingErrors { try SystemLanguageModel.Adapter.removeObsoleteAdapters() }
    }

    // MARK: - Schemas and transcripts

    func validateSchema(schemaJson: String) async throws -> String {
      try translatingErrors { try Conversions.schemaJson(try Conversions.schema(schemaJson)) }
    }

    func decodeTranscript(json: String) async throws -> TranscriptMessage {
      try translatingErrors { try Conversions.transcript(try Conversions.transcript(json: json)) }
    }

    // MARK: - Sessions

    func createSession(config: SessionConfigMessage) async throws -> Int64 {
      try translatingErrors {
        let box = HandleBox()
        let tools = try Conversions.tools(
          config.tools, builtIn: config.builtInTools, callback: callback, sessionHandle: box)
        let model = try Conversions.model(config.model, registry: registry)
        let session: LanguageModelSession
        if let transcriptJson = config.transcriptJson {
          let transcript = try Conversions.transcript(json: transcriptJson)
          switch model {
          case .system(let system):
            session = LanguageModelSession(model: system, tools: tools, transcript: transcript)
          case .privateCloudCompute:
            guard #available(iOS 27.0, macOS 27.0, *), let cloud = model.cloudModel else {
              throw Errors.requires27("The Private Cloud Compute model")
            }
            session = LanguageModelSession(model: cloud, tools: tools, transcript: transcript)
          }
        } else {
          let instructions = config.instructions.map(Instructions.init)
          switch model {
          case .system(let system):
            session = LanguageModelSession(
              model: system, tools: tools, instructions: instructions)
          case .privateCloudCompute:
            guard #available(iOS 27.0, macOS 27.0, *), let cloud = model.cloudModel else {
              throw Errors.requires27("The Private Cloud Compute model")
            }
            session = LanguageModelSession(
              model: cloud, tools: tools, instructions: instructions)
          }
        }
        if #available(iOS 27.0, macOS 27.0, *), let policy = config.transcriptPolicy {
          session.transcriptErrorHandlingPolicy =
            policy == .preserveTranscript ? .preserveTranscript : .revertTranscript
        }
        let handle = registry.insert(
          .session(
            SessionBox(
              session: session, dartToolNames: Set(config.tools.map { $0.name }))))
        box.value = handle
        return handle
      }
    }

    func respond(request: RespondRequestMessage) async throws -> ResponseMessage {
      try await translatingErrors {
        let box = try registry.session(request.sessionHandle)
        // A second request while one is in flight traps inside Foundation
        // Models on device instead of throwing, so reject it here.
        guard !box.session.isResponding else { throw concurrentRequestsError() }
        let prompt = try Conversions.prompt(request.prompt)
        let options = Conversions.options(request.options)
        let task = Task { () -> ResponseMessage in
          if let schemaJson = request.schemaJson {
            let schema = try Conversions.schema(schemaJson)
            let response: LanguageModelSession.Response<GeneratedContent>
            if #available(iOS 27.0, macOS 27.0, *),
              Conversions.hasContextOptions(request.contextOptions)
            {
              response = try await box.session.respond(
                to: prompt, schema: schema, options: options,
                contextOptions: Conversions.contextOptions(request.contextOptions))
            } else {
              response = try await box.session.respond(
                to: prompt, schema: schema,
                includeSchemaInPrompt: request.contextOptions.includeSchemaInPrompt ?? true,
                options: options)
            }
            return ResponseMessage(
              contentJson: response.content.jsonString,
              isComplete: response.content.isComplete,
              entries: try Conversions.entries(response.transcriptEntries),
              usage: usage(of: response))
          }
          let response: LanguageModelSession.Response<String>
          if #available(iOS 27.0, macOS 27.0, *),
            Conversions.hasContextOptions(request.contextOptions)
          {
            response = try await box.session.respond(
              to: prompt, options: options,
              contextOptions: Conversions.contextOptions(request.contextOptions))
          } else {
            response = try await box.session.respond(to: prompt, options: options)
          }
          return ResponseMessage(
            text: response.content, isComplete: true,
            entries: try Conversions.entries(response.transcriptEntries),
            usage: usage(of: response))
        }
        let wrapper = Task { _ = await task.result }
        requests.register(request.requestId, task: wrapper)
        defer { requests.finish(request.requestId) }
        return try await task.value
      }
    }

    private func usage<Content>(of response: LanguageModelSession.Response<Content>)
      -> UsageMessage
    {
      if #available(iOS 27.0, macOS 27.0, *) { return Conversions.usage(response.usage) }
      return Conversions.emptyUsage()
    }

    func startStream(request: RespondRequestMessage) async throws {
      let box = try registry.session(request.sessionHandle)
      guard !box.session.isResponding else { throw concurrentRequestsError() }
      let prompt = try translatingErrors { try Conversions.prompt(request.prompt) }
      let options = Conversions.options(request.options)
      let callback = self.callback.api
      let requests = self.requests
      let task = Task { [weak self] in
        guard let self else { return }
        do {
          if let schemaJson = request.schemaJson {
            let schema = try Conversions.schema(schemaJson)
            let stream = box.session.streamResponse(
              to: prompt, schema: schema,
              includeSchemaInPrompt: request.contextOptions.includeSchemaInPrompt ?? true,
              options: options)
            var last: LanguageModelSession.ResponseStream<GeneratedContent>.Snapshot?
            for try await snapshot in stream {
              try Task.checkCancellation()
              last = snapshot
              try await callback.onStreamSnapshot(
                snapshot: StreamSnapshotMessage(
                  requestId: request.requestId,
                  contentJson: snapshot.rawContent.jsonString,
                  isComplete: snapshot.rawContent.isComplete,
                  usage: self.usage(of: snapshot)))
            }
            try await callback.onStreamDone(
              requestId: request.requestId,
              response: ResponseMessage(
                contentJson: last?.rawContent.jsonString,
                isComplete: last?.rawContent.isComplete ?? false,
                entries: try self.entries(of: last),
                usage: last.map { self.usage(of: $0) } ?? Conversions.emptyUsage()))
          } else {
            let stream = box.session.streamResponse(to: prompt, options: options)
            var last: LanguageModelSession.ResponseStream<String>.Snapshot?
            for try await snapshot in stream {
              try Task.checkCancellation()
              last = snapshot
              try await callback.onStreamSnapshot(
                snapshot: StreamSnapshotMessage(
                  requestId: request.requestId, text: snapshot.content,
                  isComplete: snapshot.rawContent.isComplete,
                  usage: self.usage(of: snapshot)))
            }
            try await callback.onStreamDone(
              requestId: request.requestId,
              response: ResponseMessage(
                text: last?.content, isComplete: true,
                entries: try self.entries(of: last),
                usage: last.map { self.usage(of: $0) } ?? Conversions.emptyUsage()))
          }
        } catch {
          let translated = Errors.translate(error)
          try? await callback.onStreamError(
            requestId: request.requestId,
            error: ErrorMessage(
              code: translated.code, message: translated.message ?? "",
              details: translated.details as? String))
        }
        requests.finish(request.requestId)
      }
      requests.register(request.requestId, task: task)
    }

    /// The transcript entries of a stream snapshot (iOS/macOS 27+).
    private func entries<Content>(
      of snapshot: LanguageModelSession.ResponseStream<Content>.Snapshot?
    ) throws -> [TranscriptEntryMessage] {
      guard #available(iOS 27.0, macOS 27.0, *), let snapshot else { return [] }
      return try Conversions.entries(snapshot.transcriptEntries)
    }

    private func usage<Content>(
      of snapshot: LanguageModelSession.ResponseStream<Content>.Snapshot
    ) -> UsageMessage {
      if #available(iOS 27.0, macOS 27.0, *) { return Conversions.usage(snapshot.usage) }
      return Conversions.emptyUsage()
    }

    func cancelRequest(requestId: Int64) throws {
      requests.cancel(requestId)
    }

    func prewarm(sessionHandle: Int64, promptPrefix: PromptMessage?) throws {
      try translatingErrors {
        let box = try registry.session(sessionHandle)
        box.session.prewarm(promptPrefix: try promptPrefix.map(Conversions.prompt))
      }
    }

    func transcript(sessionHandle: Int64) async throws -> TranscriptMessage {
      try translatingErrors {
        try Conversions.transcript(try registry.session(sessionHandle).session.transcript)
      }
    }

    func isResponding(sessionHandle: Int64) throws -> Bool {
      try registry.session(sessionHandle).session.isResponding
    }

    func sessionUsage(sessionHandle: Int64) throws -> UsageMessage {
      guard #available(iOS 27.0, macOS 27.0, *) else { return Conversions.emptyUsage() }
      return Conversions.usage(try registry.session(sessionHandle).session.usage)
    }

    func setTranscriptPolicy(sessionHandle: Int64, policy: TranscriptPolicyMessage?) throws {
      guard #available(iOS 27.0, macOS 27.0, *) else {
        throw Errors.requires27("Transcript error handling policies")
      }
      let box = try registry.session(sessionHandle)
      switch policy {
      case .preserveTranscript: box.session.transcriptErrorHandlingPolicy = .preserveTranscript
      case .revertTranscript: box.session.transcriptErrorHandlingPolicy = .revertTranscript
      case .none: box.session.transcriptErrorHandlingPolicy = nil
      }
    }

    func logFeedbackAttachment(
      sessionHandle: Int64, sentiment: FeedbackSentimentMessage?,
      issues: [FeedbackIssueMessage], desiredResponseText: String?
    ) async throws -> FlutterStandardTypedData {
      try translatingErrors {
        guard #available(iOS 27.0, macOS 27.0, *) else {
          throw Errors.requires27("Feedback attachments")
        }
        let box = try registry.session(sessionHandle)
        let mapped: LanguageModelFeedback.Sentiment? = switch sentiment {
        case .positive: .positive
        case .negative: .negative
        case .neutral: .neutral
        case .none: nil
        }
        let mappedIssues = issues.map(Conversions.feedbackIssue)
        let data = box.session.logFeedbackAttachment(
          sentiment: mapped, issues: mappedIssues, desiredResponseText: desiredResponseText)
        return FlutterStandardTypedData(bytes: data)
      }
    }

    private func concurrentRequestsError() -> FoundationModelsPigeonError {
      FoundationModelsPigeonError(
        .concurrentRequests,
        "This session is already responding. Await the previous response, "
          + "cancel its stream, or use another session.")
    }

    // MARK: - Handles

    func release(handle: Int64) async throws {
      registry.remove(handle)
    }

    func releaseAll() async throws -> Int64 {
      requests.cancelAll()
      return Int64(registry.removeAll())
    }

    func liveHandleCount() throws -> Int64 {
      Int64(registry.count)
    }
  }
#endif
