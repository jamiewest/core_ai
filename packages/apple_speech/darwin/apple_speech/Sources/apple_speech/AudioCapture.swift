import AVFoundation
import Foundation

/// A source of live PCM buffers: the microphone, or a file played back at
/// real-time pace through the same pipeline (for tests).
protocol LiveAudioSource: AnyObject {
  /// The format of the buffers passed to `start`'s handler.
  var format: AVAudioFormat { get }

  /// Starts delivering buffers. `onEnd` is called if the source runs out.
  func start(
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void, onEnd: @escaping () -> Void) throws

  /// Stops delivering buffers. Safe to call more than once.
  func stop()
}

/// Captures the default input device with `AVAudioEngine`.
final class MicrophoneCapture: LiveAudioSource, @unchecked Sendable {
  private let engine = AVAudioEngine()
  private let configureSession: Bool
  private let lifecycle = NSRecursiveLock()
  private var running = false
  private var stopped = false
  #if os(iOS)
    private var previousSession:
      (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
  #endif
  let format: AVAudioFormat

  /// Prepares the engine and reads the input format. Configures the iOS
  /// audio session when [configureSession] is true.
  init(configureSession: Bool) throws {
    self.configureSession = configureSession
    #if os(iOS)
      if configureSession {
        let session = AVAudioSession.sharedInstance()
        previousSession = (session.category, session.mode, session.categoryOptions)
        do {
          try session.setCategory(.record, mode: .measurement, options: .duckOthers)
          try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
          if let previousSession {
            try? session.setCategory(
              previousSession.0, mode: previousSession.1, options: previousSession.2)
          }
          throw AppleSpeechPigeonError(
            .microphoneUnavailable,
            "Could not activate the audio session: \(error.localizedDescription)")
        }
      }
    #endif
    let format = engine.inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0, format.channelCount > 0 else {
      #if os(iOS)
        if configureSession {
          let session = AVAudioSession.sharedInstance()
          try? session.setActive(false, options: .notifyOthersOnDeactivation)
          if let previousSession {
            try? session.setCategory(
              previousSession.0, mode: previousSession.1, options: previousSession.2)
          }
        }
      #endif
      throw AppleSpeechPigeonError(
        .microphoneUnavailable, "No audio input device is available.")
    }
    self.format = format
  }

  func start(
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void, onEnd: @escaping () -> Void
  ) throws {
    lifecycle.lock()
    defer { lifecycle.unlock() }
    guard !stopped else { throw CancellationError() }
    guard !running else { return }
    let input = engine.inputNode
    input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
      onBuffer(buffer)
    }
    engine.prepare()
    do {
      try engine.start()
    } catch {
      input.removeTap(onBus: 0)
      deactivateSession()
      throw AppleSpeechPigeonError(
        .microphoneUnavailable,
        "Could not start the microphone: \(error.localizedDescription)")
    }
    running = true
  }

  func stop() {
    lifecycle.lock()
    defer { lifecycle.unlock() }
    guard !stopped else { return }
    stopped = true
    if running {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
      running = false
    }
    deactivateSession()
  }

  private func deactivateSession() {
    #if os(iOS)
      if configureSession, let previous = previousSession {
        previousSession = nil
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        try? session.setCategory(previous.0, mode: previous.1, options: previous.2)
      }
    #endif
  }

  deinit { stop() }
}

/// Plays a file into the live pipeline at real-time pace, like a microphone.
final class SimulatedMicrophone: LiveAudioSource, @unchecked Sendable {
  private let file: AVAudioFile
  private let task = Mutex<Task<Void, Never>?>(nil)
  let format: AVAudioFormat

  init(file: AVAudioFile) {
    self.file = file
    self.format = file.processingFormat
  }

  func start(
    onBuffer: @escaping (AVAudioPCMBuffer) -> Void, onEnd: @escaping () -> Void
  ) throws {
    let file = self.file
    let format = self.format
    let chunk: AVAudioFrameCount = 4096
    let started = Task {
      let seconds = Double(chunk) / format.sampleRate
      while !Task.isCancelled && file.framePosition < file.length {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk)
        else { break }
        do {
          try file.read(into: buffer, frameCount: chunk)
        } catch {
          break
        }
        if buffer.frameLength == 0 { break }
        onBuffer(buffer)
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
      }
      if !Task.isCancelled { onEnd() }
    }
    task.withLock { $0 = started }
  }

  func stop() {
    task.withLock { $0 }?.cancel()
  }
}

/// Converts buffers to the format an analyzer or recognizer expects.
final class BufferConverter {
  let target: AVAudioFormat
  private var converter: AVAudioConverter?

  init(target: AVAudioFormat) { self.target = target }

  func convert(_ buffer: AVAudioPCMBuffer) throws -> AVAudioPCMBuffer {
    let source = buffer.format
    if source == target {
      // Engine tap buffers are reused after the callback returns. AnalyzerInput
      // keeps the buffer, so give it independent storage.
      guard let copy = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: buffer.frameLength) else {
        throw AppleSpeechPigeonError(.audioFormat, "Could not copy the audio buffer.")
      }
      copy.frameLength = buffer.frameLength
      let input = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
      let output = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
      for index in input.indices {
        if let from = input[index].mData, let to = output[index].mData {
          memcpy(to, from, Int(input[index].mDataByteSize))
        }
      }
      return copy
    }
    if converter == nil || converter?.inputFormat != source {
      guard let created = AVAudioConverter(from: source, to: target) else {
        throw AppleSpeechPigeonError(
          .audioFormat, "Cannot convert audio from \(source) to \(target).")
      }
      // Avoids timestamp drift from priming frames in a live stream.
      created.primeMethod = .none
      converter = created
    }
    guard let converter else { return buffer }
    let ratio = target.sampleRate / source.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 16
    guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
      throw AppleSpeechPigeonError(.audioFormat, "Could not allocate an audio buffer.")
    }
    var consumed = false
    var error: NSError?
    let status = converter.convert(to: output, error: &error) { _, inputStatus in
      if consumed {
        inputStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      inputStatus.pointee = .haveData
      return buffer
    }
    if status == .error {
      throw AppleSpeechPigeonError(
        .audioFormat, "Audio conversion failed: \(error?.localizedDescription ?? "unknown")")
    }
    return output
  }
}

extension AVAudioFormat {
  var asMessage: AudioFormatMessage {
    let common: String
    switch commonFormat {
    case .pcmFormatInt16: common = "pcmFormatInt16"
    case .pcmFormatInt32: common = "pcmFormatInt32"
    case .pcmFormatFloat32: common = "pcmFormatFloat32"
    case .pcmFormatFloat64: common = "pcmFormatFloat64"
    default: common = "other"
    }
    return AudioFormatMessage(
      sampleRate: sampleRate, channelCount: Int64(channelCount), commonFormat: common,
      isInterleaved: isInterleaved)
  }
}

/// Opens an audio file, checking that it exists first.
func openAudioFile(_ path: String?) throws -> AVAudioFile {
  guard let path, !path.isEmpty else {
    throw Errors.invalidArgument("A file path is required for this audio source.")
  }
  guard FileManager.default.fileExists(atPath: path) else { throw Errors.fileNotFound(path) }
  do {
    return try AVAudioFile(forReading: URL(fileURLWithPath: path))
  } catch {
    throw Errors.translate(error)
  }
}
