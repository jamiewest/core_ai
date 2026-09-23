#if canImport(Speech)
  import AVFoundation
  import Foundation
  import Speech

  /// One `SFSpeechRecognizer` task over a file or the microphone.
  final class RecognitionRun: ActiveRequest, @unchecked Sendable {
    let requestId: Int64
    private let recognizer: SFSpeechRecognizer
    private let request: SFSpeechRecognitionRequest
    private let live: LiveAudioSource?
    private let pump: EventPump
    private let state = Mutex<(task: SFSpeechRecognitionTask?, cancelled: Bool, ended: Bool)>(
      (nil, false, false))

    private init(
      requestId: Int64, recognizer: SFSpeechRecognizer, request: SFSpeechRecognitionRequest,
      live: LiveAudioSource?, pump: EventPump
    ) {
      self.requestId = requestId
      self.recognizer = recognizer
      self.request = request
      self.live = live
      self.pump = pump
    }

    static func recognizer(for locale: String?) -> SFSpeechRecognizer? {
      if let locale { return SFSpeechRecognizer(locale: Locale(identifier: locale)) }
      return SFSpeechRecognizer()
    }

    /// A BCP 47-style identifier that works before iOS 16 / macOS 13.
    static func identifier(_ locale: Locale) -> String {
      locale.identifier.replacingOccurrences(of: "_", with: "-")
    }

    static func taskHint(_ hint: SFSpeechRecognitionTaskHint) -> TaskHintMessage {
      switch hint {
      case .dictation: return .dictation
      case .search: return .search
      case .confirmation: return .confirmation
      default: return .unspecified
      }
    }

    /// Validates the request and opens the source without starting.
    static func prepare(_ message: RecognitionRequestMessage, pump: EventPump) throws
      -> RecognitionRun
    {
      try Authorization.requireSpeechAuthorized()
      guard let recognizer = recognizer(for: message.locale) else {
        throw Errors.unsupportedLocale(message.locale ?? "(current)", "SFSpeechRecognizer")
      }
      guard recognizer.isAvailable else {
        throw AppleSpeechPigeonError(
          .recognizerUnavailable,
          "The speech recognizer for \(identifier(recognizer.locale)) is not available "
            + "right now.")
      }
      if message.requiresOnDeviceRecognition && !recognizer.supportsOnDeviceRecognition {
        throw Errors.unsupported(
          "On-device recognition is not supported for \(identifier(recognizer.locale)).")
      }
      let request: SFSpeechRecognitionRequest
      var live: LiveAudioSource?
      switch message.source {
      case .file:
        guard let path = message.path, !path.isEmpty else {
          throw Errors.invalidArgument("A file path is required for this audio source.")
        }
        guard FileManager.default.fileExists(atPath: path) else {
          throw Errors.fileNotFound(path)
        }
        request = SFSpeechURLRecognitionRequest(url: URL(fileURLWithPath: path))
      case .microphone:
        try Authorization.requireMicrophoneAuthorized()
        request = SFSpeechAudioBufferRecognitionRequest()
        live = try MicrophoneCapture(configureSession: message.configureAudioSession)
      case .simulatedMicrophone:
        request = SFSpeechAudioBufferRecognitionRequest()
        live = SimulatedMicrophone(file: try openAudioFile(message.path))
      case .asset:
        throw Errors.invalidArgument(
          "SFSpeechRecognizer takes audio files and the microphone, not media assets.")
      }
      request.taskHint = taskHint(message.taskHint)
      request.shouldReportPartialResults = message.shouldReportPartialResults
      request.contextualStrings = message.contextualStrings
      request.requiresOnDeviceRecognition = message.requiresOnDeviceRecognition
      if let punctuation = message.addsPunctuation {
        if #available(iOS 16.0, macOS 13.0, *) {
          request.addsPunctuation = punctuation
        }
      }
      return RecognitionRun(
        requestId: message.requestId, recognizer: recognizer, request: request, live: live,
        pump: pump)
    }

    private static func taskHint(_ hint: TaskHintMessage) -> SFSpeechRecognitionTaskHint {
      switch hint {
      case .unspecified: return .unspecified
      case .dictation: return .dictation
      case .search: return .search
      case .confirmation: return .confirmation
      }
    }

    /// Starts recognizing; [onFinished] runs once the request has ended.
    func start(onFinished: @escaping @Sendable () -> Void) throws {
      let requestId = self.requestId
      let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
        guard let self else { return }
        if self.state.withLock({ $0.cancelled || $0.ended }) { return }
        if let result {
          let message = Self.message(requestId: requestId, result: result)
          self.pump.send { api in try? await api.onRecognitionResult(result: message) }
          if result.isFinal {
            self.end(onFinished) { api in
              try? await api.onRequestDone(requestId: requestId, lastSampleTime: nil)
            }
            return
          }
        }
        if let error {
          let translated = Errors.translate(error).asMessage
          self.end(onFinished) { api in
            try? await api.onRequestError(requestId: requestId, error: translated)
          }
        }
      }
      state.withLock { $0.task = task }
      if let live, let bufferRequest = request as? SFSpeechAudioBufferRecognitionRequest {
        do {
          try live.start(
            onBuffer: { bufferRequest.append($0) }, onEnd: { bufferRequest.endAudio() })
        } catch {
          task.cancel()
          throw error
        }
      }
    }

    private func end(
      _ onFinished: @escaping @Sendable () -> Void, _ job: @escaping EventPump.Job
    ) {
      let first = state.withLock { state -> Bool in
        defer { state.ended = true }
        return !state.ended
      }
      guard first else { return }
      live?.stop()
      pump.send(job)
      onFinished()
    }

    func finishInput() {
      live?.stop()
      (request as? SFSpeechAudioBufferRecognitionRequest)?.endAudio()
      state.withLock { $0.task }?.finish()
    }

    func cancel() {
      let task = state.withLock { state -> SFSpeechRecognitionTask? in
        state.cancelled = true
        return state.task
      }
      live?.stop()
      task?.cancel()
    }

    // MARK: - Conversions

    static func message(requestId: Int64, result: SFSpeechRecognitionResult)
      -> RecognitionResultMessage
    {
      var metadata: RecognitionMetadataMessage?
      if let value = result.speechRecognitionMetadata {
        metadata = RecognitionMetadataMessage(
          speakingRate: value.speakingRate, averagePauseDuration: value.averagePauseDuration,
          speechStartTimestamp: value.speechStartTimestamp, speechDuration: value.speechDuration)
      }
      return RecognitionResultMessage(
        requestId: requestId, bestTranscription: transcription(result.bestTranscription),
        transcriptions: result.transcriptions.map(transcription), isFinal: result.isFinal,
        metadata: metadata)
    }

    static func transcription(_ value: SFTranscription) -> TranscriptionMessage {
      TranscriptionMessage(
        formattedString: value.formattedString,
        segments: value.segments.map { segment in
          TranscriptionSegmentMessage(
            text: segment.substring, start: Int64(segment.substringRange.location),
            length: Int64(segment.substringRange.length), startTime: segment.timestamp,
            endTime: segment.timestamp + segment.duration,
            confidence: Double(segment.confidence),
            alternatives: segment.alternativeSubstrings)
        })
    }
  }
#endif
