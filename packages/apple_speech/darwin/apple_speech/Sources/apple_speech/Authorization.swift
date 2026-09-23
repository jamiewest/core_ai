#if canImport(Speech)
  import AVFoundation
  import Foundation
  import Speech

  /// Speech recognition and microphone permissions.
  enum Authorization {
    static let speechUsageKey = "NSSpeechRecognitionUsageDescription"
    static let microphoneUsageKey = "NSMicrophoneUsageDescription"

    static func speechStatus() -> AuthorizationStatusMessage {
      switch SFSpeechRecognizer.authorizationStatus() {
      case .authorized: return .authorized
      case .denied: return .denied
      case .restricted: return .restricted
      case .notDetermined: return .notDetermined
      @unknown default: return .notDetermined
      }
    }

    static func requestSpeech() async throws -> AuthorizationStatusMessage {
      // Apple terminates the app when the usage description is missing.
      try requireUsageDescription(speechUsageKey)
      if SFSpeechRecognizer.authorizationStatus() != .notDetermined { return speechStatus() }
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
      }
      return speechStatus()
    }

    static func microphoneStatus() -> AuthorizationStatusMessage {
      switch AVCaptureDevice.authorizationStatus(for: .audio) {
      case .authorized: return .authorized
      case .denied: return .denied
      case .restricted: return .restricted
      case .notDetermined: return .notDetermined
      @unknown default: return .notDetermined
      }
    }

    static func requestMicrophone() async throws -> AuthorizationStatusMessage {
      try requireUsageDescription(microphoneUsageKey)
      if AVCaptureDevice.authorizationStatus(for: .audio) != .notDetermined {
        return microphoneStatus()
      }
      _ = await AVCaptureDevice.requestAccess(for: .audio)
      return microphoneStatus()
    }

    /// Throws unless speech recognition is authorized. Never prompts.
    static func requireSpeechAuthorized() throws {
      let status = speechStatus()
      guard status == .authorized else {
        throw AppleSpeechPigeonError(
          .notAuthorized,
          "Speech recognition is not authorized (status: \(status)). Call "
            + "SpeechRecognizer.requestAuthorization() first.",
          details: ["status": "\(status)"])
      }
    }

    /// Throws unless the microphone is authorized. Never prompts.
    static func requireMicrophoneAuthorized() throws {
      try requireUsageDescription(microphoneUsageKey)
      let status = microphoneStatus()
      guard status == .authorized else {
        throw AppleSpeechPigeonError(
          .microphoneNotAuthorized,
          "Microphone access is not authorized (status: \(status)). Call "
            + "Speech.requestMicrophoneAuthorization() first.",
          details: ["status": "\(status)"])
      }
    }

    static func requireUsageDescription(_ key: String) throws {
      let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
      guard let value, !value.isEmpty else {
        throw AppleSpeechPigeonError(
          .missingUsageDescription,
          "The app's Info.plist has no \(key). Add it before requesting access.",
          details: ["key": key])
      }
    }
  }
#endif
