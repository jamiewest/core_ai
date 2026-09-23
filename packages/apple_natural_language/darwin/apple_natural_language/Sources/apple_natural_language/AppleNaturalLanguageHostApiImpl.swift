#if canImport(NaturalLanguage)
  import Foundation
  import NaturalLanguage

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Owns the native objects handed to Dart, keyed by opaque handles.
  final class HandleRegistry: @unchecked Sendable {
    enum Entry {
      case embedding(NLEmbedding)
      /// An `NLContextualEmbedding` (iOS 17+ / macOS 14+), held as `AnyObject`
      /// because an enum case cannot carry a newer type.
      case contextualEmbedding(AnyObject)
      case model(NLModel)
      case gazetteer(NLGazetteer)
    }

    private let lock = NSLock()
    private var nextHandle: Int64 = 1
    private var entries: [Int64: Entry] = [:]

    func insert(_ entry: Entry) -> Int64 {
      lock.withLock {
        let handle = nextHandle
        nextHandle += 1
        entries[handle] = entry
        return handle
      }
    }

    func embedding(_ handle: Int64) throws -> NLEmbedding {
      guard case .embedding(let value) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "NLEmbedding")
      }
      return value
    }

    @available(iOS 17.0, macOS 14.0, *)
    func contextualEmbedding(_ handle: Int64) throws -> NLContextualEmbedding {
      guard case .contextualEmbedding(let value) = lock.withLock({ entries[handle] }),
        let embedding = value as? NLContextualEmbedding
      else {
        throw Errors.invalidHandle(handle, expected: "NLContextualEmbedding")
      }
      return embedding
    }

    func model(_ handle: Int64) throws -> NLModel {
      guard case .model(let value) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "NLModel")
      }
      return value
    }

    func gazetteer(_ handle: Int64) throws -> NLGazetteer {
      guard case .gazetteer(let value) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "NLGazetteer")
      }
      return value
    }

    func remove(_ handle: Int64) { _ = lock.withLock { entries.removeValue(forKey: handle) } }

    func removeAll() -> Int {
      lock.withLock {
        let count = entries.count
        entries.removeAll()
        return count
      }
    }

    var count: Int { lock.withLock { entries.count } }
  }

  /// Implements `AppleNaturalLanguageHostApi` on top of NaturalLanguage.
  final class AppleNaturalLanguageHostApiImpl: AppleNaturalLanguageHostApi, @unchecked Sendable {
    let registry = HandleRegistry()

    func shutdown() { _ = registry.removeAll() }

    // MARK: - Language identification

    func dominantLanguage(text: String) throws -> String? {
      NLLanguageRecognizer.dominantLanguage(for: text)?.rawValue
    }

    func languageHypotheses(
      text: String, maximumCount: Int64, hints: [String: Double], constraints: [String]
    ) async throws -> [LanguageHypothesisMessage] {
      try translatingErrors {
        let recognizer = NLLanguageRecognizer()
        if !hints.isEmpty {
          var languageHints: [NLLanguage: Double] = [:]
          for (language, weight) in hints { languageHints[NLLanguage(language)] = weight }
          recognizer.languageHints = languageHints
        }
        if !constraints.isEmpty {
          recognizer.languageConstraints = constraints.map { NLLanguage(rawValue: $0) }
        }
        recognizer.processString(text)
        // With constraints, Apple pads the result with zero-confidence
        // languages outside them; drop those so the constraint holds.
        let allowed = Set(constraints)
        return recognizer.languageHypotheses(withMaximum: Int(maximumCount))
          .filter { allowed.isEmpty || allowed.contains($0.key.rawValue) }
          .map { LanguageHypothesisMessage(language: $0.key.rawValue, confidence: $0.value) }
          .sorted { $0.confidence > $1.confidence }
      }
    }

    // MARK: - Tokenization

    func tokenize(text: String, unit: TokenUnitMessage, language: String?) async throws
      -> [TokenMessage]
    {
      try translatingErrors {
        let tokenizer = NLTokenizer(unit: Conversions.unit(unit))
        tokenizer.string = text
        if let language { tokenizer.setLanguage(NLLanguage(language)) }
        var tokens: [TokenMessage] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, flags in
          let (start, length) = Conversions.range(range, in: text)
          tokens.append(
            TokenMessage(
              start: start, length: length,
              attributes: Conversions.attributes(flags)))
          return true
        }
        return tokens
      }
    }

    // MARK: - Tagging

    func tags(request: TagRequestMessage) async throws -> [TagMessage] {
      try translatingErrors {
        let scheme = Conversions.scheme(request.scheme)
        let tagger = NLTagger(tagSchemes: [scheme])
        tagger.string = request.text
        if let language = request.language {
          tagger.setLanguage(
            NLLanguage(language), range: request.text.startIndex..<request.text.endIndex)
        }
        if !request.modelHandles.isEmpty {
          tagger.setModels(try request.modelHandles.map(registry.model), forTagScheme: scheme)
        }
        if !request.gazetteerHandles.isEmpty {
          tagger.setGazetteers(try request.gazetteerHandles.map(registry.gazetteer), for: scheme)
        }
        var tags: [TagMessage] = []
        tagger.enumerateTags(
          in: request.text.startIndex..<request.text.endIndex,
          unit: Conversions.unit(request.unit), scheme: scheme,
          options: Conversions.options(request.options)
        ) { tag, range in
          let (start, length) = Conversions.range(range, in: request.text)
          tags.append(TagMessage(start: start, length: length, tag: tag?.rawValue))
          return true
        }
        return tags
      }
    }

    func tagHypotheses(
      text: String, characterIndex: Int64, scheme: TagSchemeMessage, unit: TokenUnitMessage,
      maximumCount: Int64
    ) async throws -> [TagHypothesisMessage] {
      try translatingErrors {
        let tagger = NLTagger(tagSchemes: [Conversions.scheme(scheme)])
        tagger.string = text
        let index = try Conversions.stringIndex(characterIndex, in: text)
        return tagger.tagHypotheses(
          at: index, unit: Conversions.unit(unit), scheme: Conversions.scheme(scheme),
          maximumCount: Int(maximumCount)
        ).0
        .map { TagHypothesisMessage(tag: $0.key, confidence: $0.value) }
        .sorted { $0.confidence > $1.confidence }
      }
    }

    func availableTagSchemes(unit: TokenUnitMessage, language: String) throws -> [String] {
      NLTagger.availableTagSchemes(for: Conversions.unit(unit), language: NLLanguage(language))
        .map { $0.rawValue }
    }

    func requestTaggerAssets(language: String, scheme: TagSchemeMessage) async throws
      -> AssetsResultMessage
    {
      try await withCheckedThrowingContinuation { continuation in
        NLTagger.requestAssets(
          for: NLLanguage(language), tagScheme: Conversions.scheme(scheme)
        ) { result, error in
          if let error {
            continuation.resume(throwing: Errors.translate(error))
          } else {
            continuation.resume(returning: Conversions.assetsResult(result))
          }
        }
      }
    }

    // MARK: - Embeddings

    func loadWordEmbedding(language: String, revision: Int64?) async throws
      -> EmbeddingInfoMessage
    {
      try embeddingInfo(
        revision.map {
          NLEmbedding.wordEmbedding(for: NLLanguage(language), revision: Int($0))
        } ?? NLEmbedding.wordEmbedding(for: NLLanguage(language)),
        what: "A word embedding for '\(language)'")
    }

    func loadSentenceEmbedding(language: String, revision: Int64?) async throws
      -> EmbeddingInfoMessage
    {
      try embeddingInfo(
        revision.map {
          NLEmbedding.sentenceEmbedding(for: NLLanguage(language), revision: Int($0))
        } ?? NLEmbedding.sentenceEmbedding(for: NLLanguage(language)),
        what: "A sentence embedding for '\(language)'")
    }

    func loadEmbeddingFromFile(path: String) async throws -> EmbeddingInfoMessage {
      try translatingErrors {
        let embedding = try NLEmbedding(contentsOf: try Conversions.fileURL(path))
        return try embeddingInfo(embedding, what: "The embedding at '\(path)'")
      }
    }

    private func embeddingInfo(_ embedding: NLEmbedding?, what: String) throws
      -> EmbeddingInfoMessage
    {
      guard let embedding else {
        throw AppleNaturalLanguagePigeonError(
          .assetsUnavailable,
          "\(what) is not available on this device. Embeddings ship per "
            + "language and may need to be downloaded by the system.")
      }
      return EmbeddingInfoMessage(
        handle: registry.insert(.embedding(embedding)),
        dimension: Int64(embedding.dimension),
        vocabularySize: Int64(embedding.vocabularySize),
        language: embedding.language?.rawValue,
        revision: Int64(embedding.revision))
    }

    func embeddingVector(handle: Int64, text: String) async throws -> FlutterStandardTypedData? {
      try translatingErrors {
        guard let vector = try registry.embedding(handle).vector(for: text) else { return nil }
        return FlutterStandardTypedData(float64: Data(bytes: vector, count: vector.count * 8))
      }
    }

    func embeddingDistance(
      handle: Int64, first: String, second: String, distanceType: DistanceTypeMessage
    ) async throws -> Double {
      try translatingErrors {
        try registry.embedding(handle).distance(
          between: first, and: second, distanceType: Conversions.distance(distanceType))
      }
    }

    func embeddingContains(handle: Int64, text: String) throws -> Bool {
      try registry.embedding(handle).contains(text)
    }

    func embeddingNeighbors(
      handle: Int64, text: String, maximumCount: Int64, maximumDistance: Double?,
      distanceType: DistanceTypeMessage
    ) async throws -> [NeighborMessage] {
      try translatingErrors {
        let embedding = try registry.embedding(handle)
        let type = Conversions.distance(distanceType)
        let neighbors = embedding.neighbors(
          for: text, maximumCount: Int(maximumCount), distanceType: type)
        return Self.neighborMessages(neighbors, maximumDistance: maximumDistance)
      }
    }

    func embeddingNeighborsForVector(
      handle: Int64, vector: FlutterStandardTypedData, maximumCount: Int64,
      maximumDistance: Double?, distanceType: DistanceTypeMessage
    ) async throws -> [NeighborMessage] {
      try translatingErrors {
        let embedding = try registry.embedding(handle)
        let type = Conversions.distance(distanceType)
        let values = vector.data.withUnsafeBytes { buffer in
          Array(buffer.bindMemory(to: Double.self))
        }
        let neighbors = embedding.neighbors(
          for: values, maximumCount: Int(maximumCount), distanceType: type)
        return Self.neighborMessages(neighbors, maximumDistance: maximumDistance)
      }
    }

    /// Swift has no `maximumDistance` overload, so filter the sorted results.
    private static func neighborMessages(
      _ neighbors: [(String, NLDistance)], maximumDistance: Double?
    ) -> [NeighborMessage] {
      neighbors
        .filter { maximumDistance == nil || $0.1 <= maximumDistance! }
        .map { NeighborMessage(text: $0.0, distance: $0.1) }
    }

    // MARK: - Contextual embeddings

    private func requireContextualEmbeddings() throws {
      guard #available(iOS 17.0, macOS 14.0, *) else {
        throw AppleNaturalLanguagePigeonError(
          .unsupported, "Contextual embeddings require iOS 17 or macOS 14 or later.")
      }
    }

    func loadContextualEmbedding(
      modelIdentifier: String?, language: String?, script: String?
    ) async throws -> ContextualEmbeddingInfoMessage {
      try translatingErrors {
        try requireContextualEmbeddings()
        guard #available(iOS 17.0, macOS 14.0, *) else { throw Errors.invalidArgument("") }
        let embedding: NLContextualEmbedding?
        if let modelIdentifier {
          embedding = NLContextualEmbedding(modelIdentifier: modelIdentifier)
        } else if let language {
          embedding = NLContextualEmbedding(language: NLLanguage(language))
        } else if let script {
          embedding = NLContextualEmbedding(script: NLScript(rawValue: script))
        } else {
          throw Errors.invalidArgument(
            "Pass a model identifier, a language or a script.")
        }
        guard let embedding else {
          throw AppleNaturalLanguagePigeonError(
            .assetsUnavailable, "No contextual embedding matches that request.")
        }
        return ContextualEmbeddingInfoMessage(
          handle: registry.insert(.contextualEmbedding(embedding)),
          modelIdentifier: embedding.modelIdentifier,
          languages: embedding.languages.map { $0.rawValue },
          scripts: embedding.scripts.map { $0.rawValue },
          revision: Int64(embedding.revision),
          dimension: Int64(embedding.dimension),
          maximumSequenceLength: Int64(embedding.maximumSequenceLength),
          hasAvailableAssets: embedding.hasAvailableAssets)
      }
    }

    func requestContextualEmbeddingAssets(handle: Int64) async throws -> AssetsResultMessage {
      try requireContextualEmbeddings()
      guard #available(iOS 17.0, macOS 14.0, *) else { throw Errors.invalidArgument("") }
      let embedding = try registry.contextualEmbedding(handle)
      return try await withCheckedThrowingContinuation { continuation in
        embedding.requestAssets { result, error in
          if let error {
            continuation.resume(throwing: Errors.translate(error))
          } else {
            continuation.resume(returning: Conversions.assetsResult(result))
          }
        }
      }
    }

    func contextualEmbeddingResult(handle: Int64, text: String, language: String?) async throws
      -> ContextualEmbeddingResultMessage
    {
      try translatingErrors {
        try requireContextualEmbeddings()
        guard #available(iOS 17.0, macOS 14.0, *) else { throw Errors.invalidArgument("") }
        let embedding = try registry.contextualEmbedding(handle)
        try embedding.load()
        let result = try embedding.embeddingResult(
          for: text, language: language.map { NLLanguage(rawValue: $0) })
        var tokens: [TokenVectorMessage] = []
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, range in
          let (start, length) = Conversions.range(range, in: text)
          tokens.append(
            TokenVectorMessage(
              start: start, length: length,
              vector: FlutterStandardTypedData(
                float64: Data(bytes: vector, count: vector.count * 8))))
          return true
        }
        return ContextualEmbeddingResultMessage(
          language: result.language.rawValue,
          sequenceLength: Int64(result.sequenceLength),
          tokens: tokens)
      }
    }

    // MARK: - Custom models and gazetteers

    func loadModel(path: String) async throws -> ModelInfoMessage {
      try translatingErrors {
        let model = try NLModel(contentsOf: try Conversions.fileURL(path))
        return ModelInfoMessage(
          handle: registry.insert(.model(model)),
          type: Conversions.modelType(model.configuration.type),
          language: model.configuration.language?.rawValue,
          revision: Int64(model.configuration.revision))
      }
    }

    func predictedLabel(handle: Int64, text: String) async throws -> String? {
      try translatingErrors { try registry.model(handle).predictedLabel(for: text) }
    }

    func predictedLabelHypotheses(handle: Int64, text: String, maximumCount: Int64) async throws
      -> [LabelHypothesisMessage]
    {
      try translatingErrors {
        try registry.model(handle)
          .predictedLabelHypotheses(for: text, maximumCount: Int(maximumCount))
          .map { LabelHypothesisMessage(label: $0.key, confidence: $0.value) }
          .sorted { $0.confidence > $1.confidence }
      }
    }

    func predictedLabelsForTokens(handle: Int64, tokens: [String]) async throws -> [String] {
      try translatingErrors { try registry.model(handle).predictedLabels(forTokens: tokens) }
    }

    func loadGazetteer(path: String) async throws -> Int64 {
      try translatingErrors {
        registry.insert(.gazetteer(try NLGazetteer(contentsOf: try Conversions.fileURL(path))))
      }
    }

    func createGazetteer(entries: [String: [String]], language: String?) async throws -> Int64 {
      try translatingErrors {
        let gazetteer = try NLGazetteer(
          dictionary: entries, language: language.map { NLLanguage(rawValue: $0) })
        return registry.insert(.gazetteer(gazetteer))
      }
    }

    func gazetteerLabel(handle: Int64, text: String) throws -> String? {
      try registry.gazetteer(handle).label(for: text)
    }

    // MARK: - Handles

    func release(handle: Int64) async throws { registry.remove(handle) }

    func releaseAll() async throws -> Int64 { Int64(registry.removeAll()) }

    func liveHandleCount() throws -> Int64 { Int64(registry.count) }
  }
#endif
