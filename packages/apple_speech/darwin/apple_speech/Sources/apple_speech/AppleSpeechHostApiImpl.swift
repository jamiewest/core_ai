#if canImport(Speech)
  import AVFoundation
  import Foundation
  import Speech

  /// Implements `AppleSpeechHostApi`.
  ///
  /// The `SFSpeechRecognizer` methods work on every supported OS version.
  /// The `SpeechAnalyzer` methods throw `unsupported` before iOS/macOS 26.
  /// Async methods are nonisolated, so their bodies run off the platform
  /// thread even though Pigeon starts them from a main-actor task.
  final class AppleSpeechHostApiImpl: AppleSpeechHostApi, @unchecked Sendable {
    private let requests = RequestRegistry()
    private let callback: CallbackBox
    private let pump: EventPump

    init(callback: AppleSpeechCallbackApiProtocol) {
      self.callback = CallbackBox(callback)
      self.pump = EventPump(api: callback)
    }

    func shutdown() {
      _ = requests.cancelAll()
    }

    // MARK: - Authorization

    func speechAuthorizationStatus() throws -> AuthorizationStatusMessage {
      Authorization.speechStatus()
    }

    func requestSpeechAuthorization() async throws -> AuthorizationStatusMessage {
      try await Authorization.requestSpeech()
    }

    func microphoneAuthorizationStatus() throws -> AuthorizationStatusMessage {
      Authorization.microphoneStatus()
    }

    func requestMicrophoneAuthorization() async throws -> AuthorizationStatusMessage {
      try await Authorization.requestMicrophone()
    }

    // MARK: - SFSpeechRecognizer

    func recognizerSupportedLocales() async throws -> [String] {
      Array(Set(SFSpeechRecognizer.supportedLocales().map(RecognitionRun.identifier))).sorted()
    }

    func recognizerInfo(locale: String?) async throws -> RecognizerInfoMessage? {
      guard let recognizer = RecognitionRun.recognizer(for: locale) else { return nil }
      return RecognizerInfoMessage(
        locale: RecognitionRun.identifier(recognizer.locale),
        isAvailable: recognizer.isAvailable,
        supportsOnDeviceRecognition: recognizer.supportsOnDeviceRecognition,
        defaultTaskHint: RecognitionRun.taskHint(recognizer.defaultTaskHint))
    }

    func startRecognition(request: RecognitionRequestMessage) async throws {
      try await translatingErrors {
        let pending = PendingRequest()
        try requests.register(request.requestId, pending)
        let run: RecognitionRun
        do {
          run = try RecognitionRun.prepare(request, pump: pump)
          try pending.attach(run)
        } catch {
          requests.remove(request.requestId, ifSame: pending)
          throw error
        }
        let requests = self.requests
        let requestId = request.requestId
        // `SFSpeechRecognizer` delivers results on its queue (main by default).
        try await MainActor.run {
          do {
            try run.start { requests.remove(requestId, ifSame: pending) }
          } catch {
            run.cancel()
            requests.remove(requestId, ifSame: pending)
            throw error
          }
        }
      }
    }

    // MARK: - SpeechAnalyzer

    func speechTranscriberIsAvailable() throws -> Bool {
      guard #available(iOS 26.0, macOS 26.0, *) else { return false }
      return SpeechTranscriber.isAvailable
    }

    func supportedLocales(kind: ModuleKindMessage) async throws -> [String] {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("SpeechAnalyzer") }
      switch kind {
      case .speechTranscriber:
        return Modules.identifiers(await SpeechTranscriber.supportedLocales)
      case .dictationTranscriber:
        return Modules.identifiers(await DictationTranscriber.supportedLocales)
      case .speechDetector:
        throw Errors.invalidArgument("SpeechDetector does not depend on a locale.")
      }
    }

    func installedLocales(kind: ModuleKindMessage) async throws -> [String] {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("SpeechAnalyzer") }
      switch kind {
      case .speechTranscriber:
        return Modules.identifiers(await SpeechTranscriber.installedLocales)
      case .dictationTranscriber:
        return Modules.identifiers(await DictationTranscriber.installedLocales)
      case .speechDetector:
        throw Errors.invalidArgument("SpeechDetector does not depend on a locale.")
      }
    }

    func supportedLocaleEquivalent(kind: ModuleKindMessage, locale: String) async throws
      -> String?
    {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("SpeechAnalyzer") }
      let requested = Locale(identifier: locale)
      switch kind {
      case .speechTranscriber:
        return await SpeechTranscriber.supportedLocale(equivalentTo: requested).map(
          Modules.identifier)
      case .dictationTranscriber:
        return await DictationTranscriber.supportedLocale(equivalentTo: requested).map(
          Modules.identifier)
      case .speechDetector:
        throw Errors.invalidArgument("SpeechDetector does not depend on a locale.")
      }
    }

    func assetStatus(modules: [ModuleConfigMessage]) async throws -> AssetStatusMessage {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("AssetInventory") }
      return try await translatingErrors {
        let built = try await Modules.build(modules, validate: false)
        return Modules.assetStatus(await AssetInventory.status(forModules: built))
      }
    }

    func installAssets(requestId: Int64, modules: [ModuleConfigMessage]) async throws -> Bool {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("AssetInventory") }
      return try await translatingErrors {
        let run = AssetInstallRun()
        try requests.register(requestId, run)
        defer { requests.remove(requestId, ifSame: run) }
        let built = try await Modules.build(modules, validate: false)
        return try await run.install(requestId: requestId, modules: built, callback: callback)
      }
    }

    func reservedLocales() async throws -> [String] {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("AssetInventory") }
      return Modules.identifiers(await AssetInventory.reservedLocales)
    }

    func maximumReservedLocales() throws -> Int64 {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("AssetInventory") }
      return Int64(AssetInventory.maximumReservedLocales)
    }

    func reserveLocale(locale: String) async throws -> Bool {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("AssetInventory") }
      return try await translatingErrors {
        try await AssetInventory.reserve(locale: Locale(identifier: locale))
      }
    }

    func releaseLocale(locale: String) async throws -> Bool {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("AssetInventory") }
      return await AssetInventory.release(reservedLocale: Locale(identifier: locale))
    }

    func bestAvailableAudioFormat(modules: [ModuleConfigMessage]) async throws
      -> AudioFormatMessage?
    {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("SpeechAnalyzer") }
      return try await translatingErrors {
        let built = try await Modules.build(modules, validate: true)
        return await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: built)?.asMessage
      }
    }

    func startAnalysis(request: AnalysisRequestMessage) async throws {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("SpeechAnalyzer") }
      try await translatingErrors {
        let pending = PendingRequest()
        try requests.register(request.requestId, pending)
        do {
          let run = try await AnalysisRun.prepare(request)
          try pending.attach(run)
          let requests = self.requests
          let requestId = request.requestId
          run.start(callback: callback) { requests.remove(requestId, ifSame: pending) }
        } catch {
          requests.remove(request.requestId, ifSame: pending)
          throw error
        }
      }
    }

    func endModelRetention() async throws {
      guard #available(iOS 26.0, macOS 26.0, *) else { throw Errors.requires26("SpeechModels") }
      await SpeechModels.endRetention()
    }

    // MARK: - Requests

    func finishRequest(requestId: Int64) throws {
      requests.finishInput(requestId)
    }

    func cancelRequest(requestId: Int64) throws {
      requests.cancel(requestId)
    }

    func cancelAll() throws -> Int64 {
      Int64(requests.cancelAll())
    }

    func activeRequestCount() throws -> Int64 {
      Int64(requests.count)
    }
  }
#endif
