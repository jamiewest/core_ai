#if canImport(Translation)
  import Foundation
  import Translation

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Implements `AppleTranslationHostApi` on top of the Translation framework.
  @available(iOS 18.0, macOS 15.0, *)
  final class AppleTranslationHostApiImpl: AppleTranslationHostApi, @unchecked Sendable {
    let registry = HandleRegistry()
    let requests = RequestRegistry()
    private let callback: AppleTranslationCallbackApiProtocol

    init(callback: AppleTranslationCallbackApiProtocol) {
      self.callback = callback
    }

    func shutdown() {
      requests.cancelAll()
      _ = registry.removeAll()
    }

    // MARK: - Languages

    func language(identifier: String) throws -> LanguageMessage {
      try translatingErrors { Conversions.message(try Conversions.language(identifier)) }
    }

    // MARK: - LanguageAvailability

    private func availability(_ strategy: StrategyMessage?) throws -> LanguageAvailability {
      guard let strategy else { return LanguageAvailability() }
      guard #available(iOS 26.4, macOS 26.4, *) else {
        throw Errors.unsupported("Translation strategies need iOS 26.4 / macOS 26.4.")
      }
      return LanguageAvailability(preferredStrategy: Conversions.strategy(strategy))
    }

    func supportedLanguages(strategy: StrategyMessage?) async throws -> [LanguageMessage] {
      try await translatingErrors {
        let languages = try await availability(strategy).supportedLanguages
        return languages.map { Conversions.message($0) }
          .sorted { $0.minimalIdentifier < $1.minimalIdentifier }
      }
    }

    func status(source: String, target: String?, strategy: StrategyMessage?) async throws
      -> LanguageStatusMessage
    {
      try await translatingErrors {
        let from = try Conversions.language(source)
        let to = try Conversions.language(target)
        return Conversions.status(try await availability(strategy).status(from: from, to: to))
      }
    }

    func statusForText(text: String, target: String?, strategy: StrategyMessage?) async throws
      -> LanguageStatusMessage
    {
      try await translatingErrors {
        let to = try Conversions.language(target)
        return Conversions.status(try await availability(strategy).status(for: text, to: to))
      }
    }

    func defaultStrategy() throws -> StrategyMessage? {
      guard #available(iOS 26.4, macOS 26.4, *) else { return nil }
      return Conversions.message(LanguageAvailability().preferredStrategy)
    }

    // MARK: - TranslationSession

    func createSession(source: String, target: String?, strategy: StrategyMessage?) async throws
      -> SessionInfoMessage
    {
      try translatingErrors {
        guard #available(iOS 26.0, macOS 26.0, *) else {
          throw Errors.unsupported(
            "TranslationSession(installedSource:target:) needs iOS 26 / macOS 26.")
        }
        let from = try Conversions.language(source)
        let to = try Conversions.language(target)
        let session: TranslationSession
        if let strategy {
          guard #available(iOS 26.4, macOS 26.4, *) else {
            throw Errors.unsupported("Translation strategies need iOS 26.4 / macOS 26.4.")
          }
          session = TranslationSession(
            installedSource: from, target: to,
            preferredStrategy: Conversions.strategy(strategy))
        } else {
          session = TranslationSession(installedSource: from, target: to)
        }
        var preferred: StrategyMessage?
        if #available(iOS 26.4, macOS 26.4, *) {
          preferred = Conversions.message(session.preferredStrategy)
        }
        return SessionInfoMessage(
          handle: registry.insert(session),
          sourceLanguage: Conversions.message(session.sourceLanguage),
          targetLanguage: Conversions.message(session.targetLanguage),
          canRequestDownloads: session.canRequestDownloads,
          preferredStrategy: preferred)
      }
    }

    func isReady(handle: Int64) async throws -> Bool {
      try await translatingErrors {
        let session = try registry.session(handle)
        guard #available(iOS 26.0, macOS 26.0, *) else {
          throw Errors.unsupported("isReady needs iOS 26 / macOS 26.")
        }
        return await session.isReady
      }
    }

    func translate(handle: Int64, request: TranslationRequestMessage) async throws
      -> TranslationResponseMessage
    {
      try await translatingErrors {
        let session = try registry.session(handle)
        if let segments = request.segments {
          guard #available(iOS 26.4, macOS 26.4, *) else {
            throw Errors.unsupported("Attributed text needs iOS 26.4 / macOS 26.4.")
          }
          return Conversions.response(
            try await session.translate(Conversions.attributed(segments)))
        }
        return Conversions.response(try await session.translate(request.sourceText))
      }
    }

    func translations(handle: Int64, requests: [TranslationRequestMessage]) async throws
      -> [TranslationResponseMessage]
    {
      try await translatingErrors {
        let session = try registry.session(handle)
        let batch = try requests.map(Conversions.request)
        return try await session.translations(from: batch).map(Conversions.response)
      }
    }

    func startBatch(
      handle: Int64, requestId: Int64, requests batchRequests: [TranslationRequestMessage]
    ) async throws {
      let session = try translatingErrors { try registry.session(handle) }
      let batch = try translatingErrors { try batchRequests.map(Conversions.request) }
      let callback = self.callback
      let requests = self.requests
      requests.start(requestId) {
        Task {
          do {
            for try await response in session.translate(batch: batch) {
              try Task.checkCancellation()
              try await callback.onBatchResponse(
                requestId: requestId, response: Conversions.response(response))
            }
            try Task.checkCancellation()
            try await callback.onBatchDone(requestId: requestId)
          } catch {
            let translated = Errors.translate(error)
            try? await callback.onBatchError(
              requestId: requestId,
              error: ErrorMessage(
                code: translated.code, message: translated.message ?? translated.code,
                details: translated.details as? String))
          }
          requests.finish(requestId)
        }
      }
    }

    func cancelRequest(requestId: Int64) throws {
      requests.cancel(requestId)
    }

    func prepareTranslation(handle: Int64) async throws {
      try await translatingErrors {
        try await registry.session(handle).prepareTranslation()
      }
    }

    func cancelSession(handle: Int64) throws {
      try translatingErrors {
        let session = try registry.session(handle)
        guard #available(iOS 26.0, macOS 26.0, *) else {
          throw Errors.unsupported("cancel() needs iOS 26 / macOS 26.")
        }
        session.cancel()
      }
    }

    // MARK: - Handles

    func release(handle: Int64) async throws { registry.remove(handle) }

    func releaseAll() async throws -> Int64 { Int64(registry.removeAll()) }

    func liveHandleCount() throws -> Int64 { Int64(registry.count) }
  }
#endif
