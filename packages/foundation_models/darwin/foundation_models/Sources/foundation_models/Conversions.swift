#if canImport(FoundationModels)
  import CoreGraphics
  import FoundationModels
  import Foundation
  import ImageIO

  #if canImport(Vision)
    import Vision
  #endif

  // MARK: - Models

  /// A resolved Foundation Models language model.
  @available(iOS 26.0, macOS 26.0, *)
  enum ResolvedModel {
    case system(SystemLanguageModel)
    /// A `PrivateCloudComputeLanguageModel` (iOS/macOS 27+). Held as
    /// `AnyObject` because an enum case cannot carry a newer type.
    case privateCloudCompute(AnyObject)
  }

  @available(iOS 27.0, macOS 27.0, *)
  extension ResolvedModel {
    /// The Private Cloud Compute model, for a `.privateCloudCompute` case.
    var cloudModel: PrivateCloudComputeLanguageModel? {
      guard case .privateCloudCompute(let model) = self else { return nil }
      return model as? PrivateCloudComputeLanguageModel
    }
  }

  @available(iOS 26.0, macOS 26.0, *)
  enum Conversions {
    static func model(_ message: ModelConfigMessage, registry: HandleRegistry) throws
      -> ResolvedModel
    {
      switch message.kind {
      case .system:
        let guardrails: SystemLanguageModel.Guardrails =
          message.guardrails == .permissiveContentTransformations
          ? .permissiveContentTransformations : .default
        if let adapterHandle = message.adapterHandle {
          let adapter = try registry.adapter(adapterHandle)
          return .system(SystemLanguageModel(adapter: adapter, guardrails: guardrails))
        }
        let useCase: SystemLanguageModel.UseCase =
          message.useCase == .contentTagging ? .contentTagging : .general
        return .system(SystemLanguageModel(useCase: useCase, guardrails: guardrails))
      case .privateCloudCompute:
        guard #available(iOS 27.0, macOS 27.0, *) else {
          throw Errors.requires27("The Private Cloud Compute model")
        }
        return .privateCloudCompute(PrivateCloudComputeLanguageModel())
      }
    }

    static func availability(_ model: ResolvedModel) -> AvailabilityStatusMessage {
      switch model {
      case .system(let system):
        switch system.availability {
        case .available: return .available
        case .unavailable(let reason):
          switch reason {
          case .deviceNotEligible: return .deviceNotEligible
          case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
          case .modelNotReady: return .modelNotReady
          @unknown default: return .unknown
          }
        @unknown default: return .unknown
        }
      case .privateCloudCompute:
        guard #available(iOS 27.0, macOS 27.0, *), let cloud = model.cloudModel else {
          return .unknown
        }
        switch cloud.availability {
        case .available: return .available
        case .unavailable(let reason):
          switch reason {
          case .deviceNotEligible: return .deviceNotEligible
          case .systemNotReady: return .systemNotReady
          @unknown default: return .unknown
          }
        @unknown default: return .unknown
        }
      }
    }

    @available(iOS 27.0, macOS 27.0, *)
    static func capabilities(_ capabilities: LanguageModelCapabilities)
      -> [CapabilityMessage]
    {
      var result: [CapabilityMessage] = []
      if capabilities.contains(.vision) { result.append(.vision) }
      if capabilities.contains(.guidedGeneration) { result.append(.guidedGeneration) }
      if capabilities.contains(.reasoning) { result.append(.reasoning) }
      if capabilities.contains(.toolCalling) { result.append(.toolCalling) }
      return result
    }

    // MARK: - Options

    static func options(_ message: GenerationOptionsMessage) -> GenerationOptions {
      var sampling: GenerationOptions.SamplingMode?
      switch message.samplingKind {
      case .greedy:
        sampling = .greedy
      case .topK:
        sampling = .random(
          top: Int(message.topK ?? 50), seed: message.seed.map(UInt64.init))
      case .probabilityThreshold:
        sampling = .random(
          probabilityThreshold: message.probabilityThreshold ?? 0.9,
          seed: message.seed.map(UInt64.init))
      case .none:
        sampling = nil
      }
      var options = GenerationOptions(
        samplingMode: sampling,
        temperature: message.temperature,
        maximumResponseTokens: message.maximumResponseTokens.map(Int.init))
      if #available(iOS 27.0, macOS 27.0, *), let mode = message.toolCallingMode {
        options.toolCallingMode = switch mode {
        case .allowed: .allowed
        case .required: .required
        case .disallowed: .disallowed
        }
      }
      return options
    }

    @available(iOS 27.0, macOS 27.0, *)
    static func contextOptions(_ message: ContextOptionsMessage) -> ContextOptions {
      var level: ContextOptions.ReasoningLevel?
      switch message.reasoningLevel {
      case .light: level = .light
      case .moderate: level = .moderate
      case .deep: level = .deep
      case .custom: level = .custom(message.customReasoningLevel ?? "")
      case .none: level = nil
      }
      return ContextOptions(
        includeSchemaInPrompt: message.includeSchemaInPrompt, reasoningLevel: level)
    }

    static func hasContextOptions(_ message: ContextOptionsMessage) -> Bool {
      message.reasoningLevel != nil || message.includeSchemaInPrompt != nil
    }

    // MARK: - Prompts

    static func prompt(_ message: PromptMessage) throws -> Prompt {
      guard !message.images.isEmpty else { return Prompt(message.text) }
      guard #available(iOS 27.0, macOS 27.0, *) else {
        throw Errors.requires27("Image attachments in prompts")
      }
      var parts: [Prompt] = []
      if !message.text.isEmpty { parts.append(Prompt(message.text)) }
      for attachment in message.images {
        let image = try cgImage(attachment.image)
        var value = Attachment(image)
        if let label = attachment.label { value = value.label(label) }
        parts.append(Prompt(value))
      }
      return Prompt(parts)
    }

    static func cgImage(_ message: ImageInputMessage) throws -> CGImage {
      switch message.kind {
      case .file:
        guard let path = message.path else {
          throw Errors.invalidArgument("A file image needs a path.")
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: url.path) else {
          throw Errors.notFound("No image file at '\(url.path)'.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
          throw Errors.invalidArgument("Could not decode the image at '\(url.path)'.")
        }
        return image
      case .encoded:
        guard let data = message.bytes?.data else {
          throw Errors.invalidArgument("An encoded image needs bytes.")
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
          throw Errors.invalidArgument("Could not decode the image data.")
        }
        return image
      case .pixels:
        guard let data = message.bytes?.data, let width = message.width,
          let height = message.height
        else {
          throw Errors.invalidArgument("Pixel images need bytes, width and height.")
        }
        let bytesPerRow = Int(message.bytesPerRow ?? Int64(width * 4))
        guard data.count >= bytesPerRow * Int(height) else {
          throw Errors.invalidArgument("Pixel data is smaller than width x height.")
        }
        guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
            width: Int(width), height: Int(height), bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(
              rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false,
            intent: .defaultIntent)
        else {
          throw Errors.invalidArgument("Could not build an image from the pixels.")
        }
        return image
      }
    }

    // MARK: - Schemas and tools

    static func schema(_ json: String) throws -> GenerationSchema {
      do {
        return try JSONDecoder().decode(GenerationSchema.self, from: Data(json.utf8))
      } catch {
        throw FoundationModelsPigeonError(
          .schemaError,
          "The schema is not a valid GenerationSchema JSON schema: "
            + "\(error.localizedDescription)",
          details: ["debug": "\(error)"])
      }
    }

    static func schemaJson(_ schema: GenerationSchema) throws -> String {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return String(decoding: try encoder.encode(schema), as: UTF8.self)
    }

    static func tools(
      _ definitions: [ToolDefinitionMessage], builtIn: [BuiltInToolMessage],
      callback: CallbackBox, sessionHandle: HandleBox
    ) throws -> [any Tool] {
      var tools: [any Tool] = try definitions.map { definition in
        DartTool(
          name: definition.name,
          description: definition.toolDescription,
          parameters: try schema(definition.parametersJson),
          includesSchemaInInstructions: definition.includesSchemaInInstructions,
          callback: callback,
          sessionHandle: sessionHandle)
      }
      for tool in builtIn {
        #if canImport(Vision)
          guard #available(iOS 27.0, macOS 27.0, *) else {
            throw Errors.requires27("Built-in Vision tools")
          }
          switch tool {
          case .ocr: tools.append(OCRTool())
          case .barcodeReader: tools.append(BarcodeReaderTool())
          }
        #else
          throw FoundationModelsPigeonError(
            .unsupported, "Vision is not available on this platform.")
        #endif
      }
      return tools
    }

    // MARK: - Transcripts

    static func transcript(_ transcript: Transcript) throws -> TranscriptMessage {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys]
      return TranscriptMessage(
        entries: try transcript.map(entry),
        json: String(decoding: try encoder.encode(transcript), as: UTF8.self))
    }

    static func transcript(json: String) throws -> Transcript {
      do {
        return try JSONDecoder().decode(Transcript.self, from: Data(json.utf8))
      } catch {
        throw FoundationModelsPigeonError(
          .invalidArgument,
          "The transcript JSON could not be decoded: \(error.localizedDescription)",
          details: ["debug": "\(error)"])
      }
    }

    static func entry(_ entry: Transcript.Entry) throws -> TranscriptEntryMessage {
      switch entry {
      case .instructions(let instructions):
        return TranscriptEntryMessage(
          id: instructions.id, kind: .instructions,
          segments: try instructions.segments.map(segment), toolCalls: [],
          toolDefinitions: try instructions.toolDefinitions.map(toolDefinition))
      case .prompt(let prompt):
        return TranscriptEntryMessage(
          id: prompt.id, kind: .prompt, segments: try prompt.segments.map(segment),
          toolCalls: [], toolDefinitions: [],
          responseFormatName: prompt.responseFormat?.name)
      case .toolCalls(let calls):
        return TranscriptEntryMessage(
          id: calls.id, kind: .toolCalls, segments: [],
          toolCalls: calls.map {
            ToolCallMessage(
              id: $0.id, toolName: $0.toolName, argumentsJson: $0.arguments.jsonString)
          },
          toolDefinitions: [])
      case .toolOutput(let output):
        return TranscriptEntryMessage(
          id: output.id, kind: .toolOutput, segments: try output.segments.map(segment),
          toolCalls: [], toolDefinitions: [], toolName: output.toolName)
      case .response(let response):
        return TranscriptEntryMessage(
          id: response.id, kind: .response, segments: try response.segments.map(segment),
          toolCalls: [], toolDefinitions: [])
      case .reasoning(let reasoning):
        return TranscriptEntryMessage(
          id: reasoning.id, kind: .reasoning, segments: try reasoning.segments.map(segment),
          toolCalls: [], toolDefinitions: [])
      @unknown default:
        return TranscriptEntryMessage(
          id: entry.id, kind: .response, segments: [], toolCalls: [], toolDefinitions: [])
      }
    }

    static func segment(_ segment: Transcript.Segment) throws -> SegmentMessage {
      switch segment {
      case .text(let text):
        return SegmentMessage(id: text.id, kind: .text, text: text.content)
      case .structure(let structure):
        return SegmentMessage(
          id: structure.id, kind: .structure, contentJson: structure.content.jsonString,
          schemaName: structure.source)
      case .attachment(let attachment):
        return SegmentMessage(
          id: attachment.id, kind: .attachment, attachmentLabel: attachment.label)
      @unknown default:
        return SegmentMessage(id: segment.id, kind: .text, text: "\(segment)")
      }
    }

    static func toolDefinition(_ definition: Transcript.ToolDefinition) throws
      -> ToolDefinitionMessage
    {
      var parametersJson = "{}"
      if #available(iOS 27.0, macOS 27.0, *) {
        parametersJson = try schemaJson(definition.parameters)
      }
      return ToolDefinitionMessage(
        name: definition.name, toolDescription: definition.description,
        parametersJson: parametersJson, includesSchemaInInstructions: true)
    }

    static func entries(_ entries: ArraySlice<Transcript.Entry>) throws
      -> [TranscriptEntryMessage]
    {
      try entries.map(entry)
    }

    @available(iOS 27.0, macOS 27.0, *)
    static func feedbackIssue(_ message: FeedbackIssueMessage)
      -> LanguageModelFeedback.Issue
    {
      let category: LanguageModelFeedback.Issue.Category
      switch message.category {
      case .unhelpful: category = .unhelpful
      case .tooVerbose: category = .tooVerbose
      case .didNotFollowInstructions: category = .didNotFollowInstructions
      case .incorrect: category = .incorrect
      case .stereotypeOrBias: category = .stereotypeOrBias
      case .suggestiveOrSexual: category = .suggestiveOrSexual
      case .vulgarOrOffensive: category = .vulgarOrOffensive
      case .triggeredGuardrailUnexpectedly: category = .triggeredGuardrailUnexpectedly
      }
      return LanguageModelFeedback.Issue(
        category: category, explanation: message.explanation)
    }

    // MARK: - Usage

    static func emptyUsage() -> UsageMessage {
      UsageMessage(inputTokens: 0, cachedInputTokens: 0, outputTokens: 0, reasoningTokens: 0)
    }

    @available(iOS 27.0, macOS 27.0, *)
    static func usage(_ usage: LanguageModelSession.Usage) -> UsageMessage {
      UsageMessage(
        inputTokens: Int64(usage.input.totalTokenCount),
        cachedInputTokens: Int64(usage.input.cachedTokenCount),
        outputTokens: Int64(usage.output.totalTokenCount),
        reasoningTokens: Int64(usage.output.reasoningTokenCount))
    }

    // MARK: - Languages

    static func languages(_ languages: Set<Locale.Language>) -> [String] {
      languages.map { $0.maximalIdentifier }.sorted()
    }
  }
#endif
