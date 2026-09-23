#if canImport(SoundAnalysis)
  import AVFoundation
  import Foundation
  import SoundAnalysis

  /// A running analysis that can be stopped.
  protocol Analysis: AnyObject {
    /// Stops producing results. Safe to call more than once.
    func stop()
  }

  /// The running analyses, keyed by the request id Dart chose.
  final class AnalysisRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var analyses: [Int64: Analysis] = [:]

    func insert(_ requestId: Int64, _ analysis: Analysis) throws {
      try lock.withLock {
        guard analyses[requestId] == nil else {
          throw Errors.invalidArgument("Request \(requestId) is already running.")
        }
        analyses[requestId] = analysis
      }
    }

    func get(_ requestId: Int64) -> Analysis? { lock.withLock { analyses[requestId] } }

    func contains(_ requestId: Int64) -> Bool { get(requestId) != nil }

    /// Removes and stops the analysis. Returns false if it was not running.
    @discardableResult
    func stop(_ requestId: Int64) -> Bool {
      guard let analysis = lock.withLock({ analyses.removeValue(forKey: requestId) }) else {
        return false
      }
      analysis.stop()
      return true
    }

    func stopAll() -> Int {
      let all = lock.withLock { () -> [Analysis] in
        let values = Array(analyses.values)
        analyses.removeAll()
        return values
      }
      all.forEach { $0.stop() }
      return all.count
    }

    var microphoneIsRunning: Bool {
      lock.withLock { analyses.values.contains { $0 is MicrophoneAnalysis } }
    }
  }

  /// Sends analysis events to Dart, dropping those of stopped analyses.
  final class EventSink: @unchecked Sendable {
    private let callback: AppleSoundAnalysisCallbackApi
    private let registry: AnalysisRegistry
    @MainActor private var tail: Task<Void, Never>?

    init(callback: AppleSoundAnalysisCallbackApi, registry: AnalysisRegistry) {
      self.callback = callback
      self.registry = registry
    }

    private func enqueue(_ body: @escaping @MainActor () async -> Void) {
      DispatchQueue.main.async { [self] in
        let previous = tail
        tail = Task { @MainActor in
          await previous?.value
          await body()
        }
      }
    }

    func result(_ message: ClassificationResultMessage) {
      enqueue { [self] in
        guard registry.contains(message.requestId) else { return }
        try? await callback.onResult(result: message)
      }
    }

    func complete(_ requestId: Int64) {
      enqueue { [self] in
        guard registry.stop(requestId) else { return }
        try? await callback.onComplete(requestId: requestId)
      }
    }

    func fail(_ requestId: Int64, _ error: any Error) {
      let error = Errors.translate(error)
      enqueue { [self] in
        guard registry.stop(requestId) else { return }
        try? await callback.onError(
          requestId: requestId, code: error.code, message: error.message ?? error.code,
          details: error.details as? String)
      }
    }
  }

  /// Receives SoundAnalysis results for one request and forwards them.
  final class ResultForwarder: NSObject, SNResultsObserving {
    private let requestId: Int64
    private let maximumClassifications: Int?
    private let sink: EventSink

    init(requestId: Int64, maximumClassifications: Int64?, sink: EventSink) {
      self.requestId = requestId
      self.maximumClassifications = maximumClassifications.map { Int($0) }
      self.sink = sink
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
      guard let result = result as? SNClassificationResult else { return }
      var classifications = result.classifications.sorted { $0.confidence > $1.confidence }
      if let maximum = maximumClassifications {
        classifications = Array(classifications.prefix(maximum))
      }
      sink.result(
        ClassificationResultMessage(
          requestId: requestId,
          startSeconds: result.timeRange.start.seconds,
          durationSeconds: result.timeRange.duration.seconds,
          classifications: classifications.map {
            ClassificationMessage(identifier: $0.identifier, confidence: $0.confidence)
          }))
    }

    func request(_ request: SNRequest, didFailWithError error: any Error) {
      sink.fail(requestId, error)
    }

    func requestDidComplete(_ request: SNRequest) {
      sink.complete(requestId)
    }
  }

  /// Classifies an audio file.
  final class FileAnalysis: Analysis {
    private let analyzer: SNAudioFileAnalyzer
    private let forwarder: ResultForwarder

    init(url: URL, request: SNClassifySoundRequest, forwarder: ResultForwarder) throws {
      analyzer = try SNAudioFileAnalyzer(url: url)
      self.forwarder = forwarder
      try analyzer.add(request, withObserver: forwarder)
    }

    func start() {
      // Keeps the analysis alive until SoundAnalysis finishes with it.
      analyzer.analyze { [self] _ in _ = self }
    }

    func stop() { analyzer.cancelAnalysis() }
  }

  /// Classifies PCM audio pushed from Dart.
  final class StreamAnalysis: Analysis {
    private let analyzer: SNAudioStreamAnalyzer
    private let forwarder: ResultForwarder
    private let format: AVAudioFormat
    /// SoundAnalysis requires one thread at a time per analyzer.
    private let queue = DispatchQueue(label: "apple_sound_analysis.stream")
    private var framePosition: AVAudioFramePosition = 0

    init(
      format message: AudioFormatMessage, request: SNClassifySoundRequest,
      forwarder: ResultForwarder
    )
      throws
    {
      guard message.sampleRate.isFinite, message.sampleRate > 0,
        message.sampleRate <= 384_000, (1...32).contains(message.channelCount),
        let format = AVAudioFormat(
          standardFormatWithSampleRate: message.sampleRate,
          channels: AVAudioChannelCount(message.channelCount))
      else {
        throw Errors.invalidArgument(
          "Unsupported format: \(message.sampleRate) Hz, \(message.channelCount) channels.")
      }
      self.format = format
      self.forwarder = forwarder
      analyzer = SNAudioStreamAnalyzer(format: format)
      try analyzer.add(request, withObserver: forwarder)
    }

    /// Deinterleaves little-endian float32 [bytes] and analyzes them.
    func analyze(_ bytes: Data) throws {
      let channels = Int(format.channelCount)
      let frameBytes = MemoryLayout<Float>.size * channels
      guard bytes.count % frameBytes == 0 else {
        throw Errors.invalidArgument(
          "Expected whole frames of \(channels) float32 samples, got \(bytes.count) bytes.")
      }
      let frames = bytes.count / frameBytes
      guard frames > 0 else { return }
      guard frames <= Int(UInt32.max) else {
        throw Errors.invalidArgument("Audio buffer is too large.")
      }
      guard
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
        let channelData = buffer.floatChannelData
      else {
        throw Errors.invalidArgument("Could not allocate a buffer of \(frames) frames.")
      }
      buffer.frameLength = AVAudioFrameCount(frames)
      try bytes.withUnsafeBytes { raw in
        for frame in 0..<frames {
          for channel in 0..<channels {
            let bits = raw.loadUnaligned(
              fromByteOffset: (frame * channels + channel) * 4, as: UInt32.self)
            let sample = Float(bitPattern: UInt32(littleEndian: bits))
            guard sample.isFinite else {
              throw Errors.invalidArgument("PCM samples must be finite.")
            }
            channelData[channel][frame] = sample
          }
        }
      }
      queue.sync {
        analyzer.analyze(buffer, atAudioFramePosition: framePosition)
        framePosition += AVAudioFramePosition(frames)
      }
    }

    func complete() {
      queue.async { [self] in analyzer.completeAnalysis() }
    }

    func stop() {
      queue.async { [self] in analyzer.removeAllRequests() }
    }
  }

  /// Classifies the default microphone.
  final class MicrophoneAnalysis: Analysis {
    private let engine = AVAudioEngine()
    private let analyzer: SNAudioStreamAnalyzer
    private let forwarder: ResultForwarder
    private let queue = DispatchQueue(label: "apple_sound_analysis.microphone")
    private let lock = NSLock()
    private var stopped = false
    private var framePosition: AVAudioFramePosition = 0
    #if os(iOS)
      private let previousCategory: AVAudioSession.Category
      private let previousMode: AVAudioSession.Mode
      private let previousOptions: AVAudioSession.CategoryOptions
    #endif

    init(request: SNClassifySoundRequest, forwarder: ResultForwarder) throws {
      self.forwarder = forwarder
      #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        previousCategory = session.category
        previousMode = session.mode
        previousOptions = session.categoryOptions
        let oldCategory = previousCategory
        let oldMode = previousMode
        let oldOptions = previousOptions
        var configured = false
        defer {
          if !configured {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(oldCategory, mode: oldMode, options: oldOptions)
          }
        }
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
      #endif
      let input = engine.inputNode
      let format = input.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else {
        throw AppleSoundAnalysisPigeonError(
          .noInputDevice, "No microphone input is available.")
      }
      analyzer = SNAudioStreamAnalyzer(format: format)
      try analyzer.add(request, withObserver: forwarder)
      input.installTap(onBus: 0, bufferSize: 8192, format: format) {
        [weak self] buffer, _ in
        // The engine owns/reuses its tap buffer. Copy before leaving the callback.
        guard let self,
          let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
        else { return }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in source.indices {
          if let from = source[index].mData, let to = destination[index].mData {
            memcpy(to, from, Int(source[index].mDataByteSize))
          }
        }
        self.queue.async { [self] in
          guard !self.lock.withLock({ self.stopped }) else { return }
          self.analyzer.analyze(copy, atAudioFramePosition: self.framePosition)
          self.framePosition += AVAudioFramePosition(copy.frameLength)
        }
      }
      #if os(iOS)
        configured = true
      #endif
    }

    func start() throws {
      engine.prepare()
      try engine.start()
    }

    func stop() {
      let alreadyStopped = lock.withLock { () -> Bool in
        defer { stopped = true }
        return stopped
      }
      guard !alreadyStopped else { return }
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      queue.async { [analyzer] in analyzer.removeAllRequests() }
      #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(previousCategory, mode: previousMode, options: previousOptions)
      #endif
    }
  }
#endif
