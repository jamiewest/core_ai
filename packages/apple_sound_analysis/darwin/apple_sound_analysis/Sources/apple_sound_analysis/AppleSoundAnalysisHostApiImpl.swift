#if canImport(SoundAnalysis)
  import AVFoundation
  import CoreML
  import Foundation
  import SoundAnalysis
  #if os(iOS)
    import Flutter
  #else
    import FlutterMacOS
  #endif

  final class AppleSoundAnalysisHostApiImpl: AppleSoundAnalysisHostApi, @unchecked Sendable {
    let registry = AnalysisRegistry()
    private let queue = DispatchQueue(label: "apple_sound_analysis.setup")
    private var models: [String: MLModel] = [:]
    private var compiledModels: [URL] = []
    private let callback: AppleSoundAnalysisCallbackApi
    private lazy var sink = EventSink(callback: callback, registry: registry)

    init(callback: AppleSoundAnalysisCallbackApi) { self.callback = callback }

    private func work<T>(_ body: @escaping () throws -> T) async throws -> T {
      try await withCheckedThrowingContinuation { continuation in
        queue.async {
          do { continuation.resume(returning: try body()) } catch {
            continuation.resume(throwing: Errors.translate(error))
          }
        }
      }
    }

    // Called only on the setup queue. Never pass unchecked values to ObjC setters.
    private func makeRequest(_ config: ClassifierConfigMessage) throws -> SNClassifySoundRequest {
      let request: SNClassifySoundRequest
      if let path = config.modelPath {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
          throw Errors.notFound("No sound model at \(path).")
        }
        let model: MLModel
        if let cached = models[url.path] {
          model = cached
        } else {
          let compiled: URL
          let temporary = ["mlmodel", "mlpackage"].contains(url.pathExtension.lowercased())
          compiled = temporary ? try MLModel.compileModel(at: url) : url
          do { model = try MLModel(contentsOf: compiled) } catch {
            if temporary { try? FileManager.default.removeItem(at: compiled) }
            throw error
          }
          if temporary { compiledModels.append(compiled) }
          models[url.path] = model
        }
        request = try SNClassifySoundRequest(mlModel: model)
      } else {
        request = try SNClassifySoundRequest(classifierIdentifier: .version1)
      }
      if let seconds = config.windowDurationSeconds {
        guard seconds.isFinite, seconds > 0 else {
          throw Errors.invalidArgument("Window duration must be finite and positive.")
        }
        let duration = CMTime(seconds: seconds, preferredTimescale: 1_000_000_000)
        let allowed: Bool
        switch request.windowDurationConstraint {
        case .enumeratedDurations(let durations):
          allowed = durations.contains { abs($0.seconds - seconds) < 0.000000001 }
          // Use the exact time from the constraint, avoiding rounding mismatches.
          if let exact = durations.first(where: { abs($0.seconds - seconds) < 0.000000001 }) {
            request.windowDuration = exact
          }
        case .durationRange(let range):
          allowed = duration.isNumeric && CMTimeRangeContainsTime(range, time: duration)
          if allowed { request.windowDuration = duration }
        @unknown default: allowed = false
        }
        guard allowed else {
          throw Errors.invalidArgument("Unsupported window duration: \(seconds).")
        }
      }
      if let overlap = config.overlapFactor {
        guard overlap.isFinite, overlap >= 0, overlap < 1 else {
          throw Errors.invalidArgument("Overlap factor must be in [0, 1).")
        }
        request.overlapFactor = overlap
      }
      return request
    }

    private func forwarder(_ id: Int64, _ maximum: Int64?) throws -> ResultForwarder {
      guard !registry.contains(id) else {
        throw Errors.invalidArgument("Request \(id) is already running.")
      }
      if let maximum, maximum <= 0 {
        throw Errors.invalidArgument("maximumClassifications must be positive.")
      }
      return ResultForwarder(requestId: id, maximumClassifications: maximum, sink: sink)
    }

    func classifierInfo(config: ClassifierConfigMessage) async throws -> ClassifierInfoMessage {
      try await work { [self] in
        let request = try makeRequest(config)
        var durations: [Double] = []
        var minimum: Double?
        var maximum: Double?
        switch request.windowDurationConstraint {
        case .enumeratedDurations(let values): durations = values.map { $0.seconds }
        case .durationRange(let range):
          minimum = range.start.seconds
          maximum = range.end.seconds
        @unknown default: break
        }
        return ClassifierInfoMessage(
          knownClassifications: request.knownClassifications,
          windowDurationSeconds: request.windowDuration.seconds,
          overlapFactor: request.overlapFactor,
          allowedWindowDurationsSeconds: durations,
          minimumWindowSeconds: minimum, maximumWindowSeconds: maximum)
      }
    }

    func startFileAnalysis(
      requestId: Int64, path: String, config: ClassifierConfigMessage,
      maximumClassifications: Int64?
    ) async throws {
      try await work { [self] in
        let observer = try forwarder(requestId, maximumClassifications)
        let analysis = try FileAnalysis(
          url: URL(fileURLWithPath: path),
          request: makeRequest(config), forwarder: observer)
        try registry.insert(requestId, analysis)
        analysis.start()
      }
    }

    func startStreamAnalysis(
      requestId: Int64, format: AudioFormatMessage,
      config: ClassifierConfigMessage, maximumClassifications: Int64?
    ) async throws {
      try await work { [self] in
        let observer = try forwarder(requestId, maximumClassifications)
        let analysis = try StreamAnalysis(
          format: format, request: makeRequest(config), forwarder: observer)
        try registry.insert(requestId, analysis)
      }
    }

    func analyzeSamples(requestId: Int64, float32Samples: FlutterStandardTypedData) async throws {
      try translatingErrors {
        guard let stream = registry.get(requestId) as? StreamAnalysis else {
          throw Errors.notRunning(requestId)
        }
        try stream.analyze(float32Samples.data)
      }
    }

    func completeStreamAnalysis(requestId: Int64) async throws {
      try translatingErrors {
        guard let stream = registry.get(requestId) as? StreamAnalysis else {
          throw Errors.notRunning(requestId)
        }
        stream.complete()
      }
    }

    func startMicrophoneAnalysis(
      requestId: Int64, config: ClassifierConfigMessage,
      maximumClassifications: Int64?
    ) async throws {
      try await work { [self] in
        guard !registry.microphoneIsRunning else {
          throw AppleSoundAnalysisPigeonError(.busy, "A microphone analysis is already running.")
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
          throw AppleSoundAnalysisPigeonError(
            .permissionDenied, "Microphone permission has not been granted.")
        }
        let observer = try forwarder(requestId, maximumClassifications)
        let analysis = try MicrophoneAnalysis(request: makeRequest(config), forwarder: observer)
        var registered = false
        do {
          try registry.insert(requestId, analysis)
          registered = true
          try analysis.start()
        } catch {
          if registered { registry.stop(requestId) }
          analysis.stop()
          throw error
        }
      }
    }

    func cancel(requestId: Int64) throws { registry.stop(requestId) }
    func cancelAll() throws -> Int64 { Int64(registry.stopAll()) }
    func shutdown() {
      queue.async { [self] in
        _ = registry.stopAll()
        models.removeAll()
        compiledModels.forEach { try? FileManager.default.removeItem(at: $0) }
        compiledModels.removeAll()
      }
    }

    func microphonePermission() throws -> MicrophonePermissionMessage {
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .notDetermined: return .notDetermined
      case .restricted: return .restricted
      case .denied: return .denied
      case .authorized: return .authorized
      @unknown default: return .denied
      }
    }

    func requestMicrophonePermission() async throws -> Bool {
      await AVCaptureDevice.requestAccess(for: .audio)
    }
  }
#endif
