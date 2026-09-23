#if canImport(Speech)
  import AVFoundation
  import CoreMedia
  import Foundation
  import Speech

  /// One `SpeechAnalyzer` run over a file, a media asset or live audio.
  @available(iOS 26.0, macOS 26.0, *)
  final class AnalysisRun: ActiveRequest, @unchecked Sendable {
    typealias Drive = @Sendable (SpeechAnalyzer) async throws -> CMTime?

    let requestId: Int64
    private let analyzer: SpeechAnalyzer
    private let modules: [any SpeechModule]
    private let drive: Drive
    private let live: LiveAudioSource?
    private let liveInput: AsyncStream<AnalyzerInput>.Continuation?
    private let state = Mutex<(task: Task<Void, Never>?, cancelled: Bool)>((nil, false))

    private init(
      requestId: Int64, analyzer: SpeechAnalyzer, modules: [any SpeechModule],
      drive: @escaping Drive, live: LiveAudioSource?,
      liveInput: AsyncStream<AnalyzerInput>.Continuation?
    ) {
      self.requestId = requestId
      self.analyzer = analyzer
      self.modules = modules
      self.drive = drive
      self.live = live
      self.liveInput = liveInput
    }

    /// Builds the analyzer and opens the source. Throws on bad input before
    /// anything starts, so Dart sees the error from `startAnalysis`.
    static func prepare(_ request: AnalysisRequestMessage) async throws -> AnalysisRun {
      let modules = try await Modules.build(request.modules, validate: true)
      let analyzer = SpeechAnalyzer(modules: modules, options: Modules.options(request.options))
      let strings = request.contextualStrings.filter { !$0.value.isEmpty }
      if !strings.isEmpty {
        let context = AnalysisContext()
        for (tag, values) in strings {
          context.contextualStrings[AnalysisContext.ContextualStringsTag(tag)] = values
        }
        try await analyzer.setContext(context)
      }
      switch request.source {
      case .file:
        let file = try openAudioFile(request.path)
        let box = UncheckedBox(file)
        return AnalysisRun(
          requestId: request.requestId, analyzer: analyzer, modules: modules,
          drive: { try await $0.analyzeSequence(from: box.value) }, live: nil, liveInput: nil)
      case .asset:
        guard #available(iOS 27.0, macOS 27.0, *) else {
          throw Errors.requires27("Analyzing media assets")
        }
        guard let path = request.path, !path.isEmpty else {
          throw Errors.invalidArgument("A file path is required for this audio source.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
          throw Errors.fileNotFound(path)
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let provider = UncheckedBox(
          try await AssetInputSequenceProvider.provider(from: asset, compatibleWith: modules))
        return AnalysisRun(
          requestId: request.requestId, analyzer: analyzer, modules: modules,
          drive: { try await $0.analyzeSequence(provider.value.analyzerInputs) }, live: nil,
          liveInput: nil)
      case .microphone, .simulatedMicrophone:
        let source: LiveAudioSource
        if request.source == .microphone {
          try Authorization.requireMicrophoneAuthorized()
          source = try MicrophoneCapture(configureSession: request.configureAudioSession)
        } else {
          source = SimulatedMicrophone(file: try openAudioFile(request.path))
        }
        guard
          let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules, considering: source.format)
        else {
          source.stop()
          throw AppleSpeechPigeonError(
            .audioFormat, "The modules have no compatible audio format.")
        }
        do {
          try await analyzer.prepareToAnalyze(in: format)
        } catch {
          source.stop()
          throw error
        }
        var captured: AsyncStream<AnalyzerInput>.Continuation!
        let stream = AsyncStream<AnalyzerInput>(bufferingPolicy: .unbounded) { captured = $0 }
        let continuation = captured!
        let converter = BufferConverter(target: format)
        let run = AnalysisRun(
          requestId: request.requestId, analyzer: analyzer, modules: modules,
          drive: { try await $0.analyzeSequence(stream) }, live: source,
          liveInput: continuation)
        do {
          try source.start(
            onBuffer: { buffer in
              if let converted = try? converter.convert(buffer) {
                continuation.yield(AnalyzerInput(buffer: converted))
              }
            },
            onEnd: { continuation.finish() })
        } catch {
          continuation.finish()
          throw error
        }
        return run
      }
    }

    /// Runs the analysis in the background, reporting through [callback].
    func start(callback: CallbackBox, onFinished: @escaping @Sendable () -> Void) {
      let task = Task { [self] in
        await execute(callback: callback)
        onFinished()
      }
      let cancelledEarly = state.withLock { state -> Bool in
        state.task = task
        return state.cancelled
      }
      if cancelledEarly { task.cancel() }
    }

    private var isCancelled: Bool { state.withLock { $0.cancelled } }

    func finishInput() {
      live?.stop()
      liveInput?.finish()
    }

    func cancel() {
      let task = state.withLock { state -> Task<Void, Never>? in
        state.cancelled = true
        return state.task
      }
      finishInput()
      task?.cancel()
    }

    private func execute(callback: CallbackBox) async {
      let analyzer = self.analyzer
      let drive = self.drive
      let requestId = self.requestId
      let lastSample = Mutex<CMTime?>(nil)
      do {
        try await withThrowingTaskGroup(of: Void.self) { group in
          for (index, module) in modules.enumerated() {
            let box = UncheckedBox(module)
            group.addTask {
              try await Self.collect(
                box.value, index: index, requestId: requestId, callback: callback)
            }
          }
          group.addTask {
            try await withTaskCancellationHandler {
              let last = try await drive(analyzer)
              try Task.checkCancellation()
              if let last {
                try await analyzer.finalizeAndFinish(through: last)
              } else {
                await analyzer.cancelAndFinishNow()
              }
              lastSample.withLock { $0 = last }
            } onCancel: {
              Task { await analyzer.cancelAndFinishNow() }
            }
          }
          try await group.waitForAll()
        }
        live?.stop()
        guard !isCancelled else { return }
        let last = lastSample.current.flatMap(Modules.seconds)
        try? await callback.api.onRequestDone(requestId: requestId, lastSampleTime: last)
      } catch {
        live?.stop()
        guard !isCancelled else { return }
        try? await callback.api.onRequestError(
          requestId: requestId, error: Errors.translate(error).asMessage)
      }
    }

    private static func collect(
      _ module: any SpeechModule, index: Int, requestId: Int64, callback: CallbackBox
    ) async throws {
      if let transcriber = module as? SpeechTranscriber {
        for try await result in transcriber.results {
          try await send(
            Modules.transcriptionResult(
              requestId: requestId, moduleIndex: index, range: result.range,
              finalization: result.resultsFinalizationTime, isFinal: result.isFinal,
              text: result.text, alternatives: result.alternatives), callback)
        }
      } else if let transcriber = module as? DictationTranscriber {
        for try await result in transcriber.results {
          try await send(
            Modules.transcriptionResult(
              requestId: requestId, moduleIndex: index, range: result.range,
              finalization: result.resultsFinalizationTime, isFinal: result.isFinal,
              text: result.text, alternatives: result.alternatives), callback)
        }
      } else if let detector = module as? SpeechDetector {
        for try await result in detector.results {
          try await send(
            AnalyzerResultMessage(
              requestId: requestId, moduleIndex: Int64(index),
              rangeStart: Modules.seconds(result.range.start) ?? 0,
              rangeEnd: Modules.seconds(result.range.end) ?? 0,
              resultsFinalizationTime: Modules.seconds(result.resultsFinalizationTime) ?? 0,
              isFinal: result.isFinal, segments: [], alternatives: [],
              speechDetected: result.speechDetected), callback)
        }
      }
    }

    private static func send(_ result: AnalyzerResultMessage, _ callback: CallbackBox)
      async throws
    {
      try Task.checkCancellation()
      try? await callback.api.onAnalyzerResult(result: result)
    }
  }

  /// Carries a non-Sendable value into a task that is its only user.
  final class UncheckedBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
  }
#endif
