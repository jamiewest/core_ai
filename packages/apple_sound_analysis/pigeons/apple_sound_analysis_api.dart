// Pigeon schema for the apple_sound_analysis plugin.
//
// Regenerate with:
//   dart run pigeon --input pigeons/apple_sound_analysis_api.dart
//   dart format lib/src/messages.g.dart
//
// Analyses are identified by a request id chosen in Dart. Results, completion
// and errors arrive through `AppleSoundAnalysisCallbackApi` with that id.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'darwin/apple_sound_analysis/Sources/apple_sound_analysis/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'AppleSoundAnalysisPigeonError'),
    dartPackageName: 'apple_sound_analysis',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
/// Which classifier to run and how to window the audio.
class ClassifierConfigMessage {
  /// A Core ML sound classifier (`.mlmodel`, `.mlpackage` or `.mlmodelc`),
  /// or null for Apple's built-in classifier.
  String? modelPath;

  /// Window length in seconds, or null for the classifier's default.
  double? windowDurationSeconds;

  /// Overlap between windows, 0 (none) up to 1, or null for the default.
  double? overlapFactor;
}

/// Mirrors `SNClassifySoundRequest`'s read-only properties.
class ClassifierInfoMessage {
  ClassifierInfoMessage({
    required this.knownClassifications,
    required this.windowDurationSeconds,
    required this.overlapFactor,
    required this.allowedWindowDurationsSeconds,
  });

  List<String> knownClassifications;
  double windowDurationSeconds;
  double overlapFactor;

  /// The windows the classifier accepts: listed durations, or empty when
  /// any duration in [minimumWindowSeconds, maximumWindowSeconds] works.
  List<double> allowedWindowDurationsSeconds;
  double? minimumWindowSeconds;
  double? maximumWindowSeconds;
}

/// Mirrors `SNClassification`.
class ClassificationMessage {
  ClassificationMessage({required this.identifier, required this.confidence});

  String identifier;
  double confidence;
}

/// Mirrors `SNClassificationResult`.
class ClassificationResultMessage {
  ClassificationResultMessage({
    required this.requestId,
    required this.startSeconds,
    required this.durationSeconds,
    required this.classifications,
  });

  int requestId;
  double startSeconds;
  double durationSeconds;

  /// Most confident first.
  List<ClassificationMessage> classifications;
}

/// PCM audio pushed from Dart: interleaved 32-bit float samples.
class AudioFormatMessage {
  AudioFormatMessage({required this.sampleRate, required this.channelCount});

  double sampleRate;
  int channelCount;
}

/// Mirrors `AVAuthorizationStatus` for the microphone.
enum MicrophonePermissionMessage {
  notDetermined,
  restricted,
  denied,
  authorized,
}

/// Always available, so Dart can ask whether the framework exists.
@HostApi()
abstract class AppleSoundAnalysisPlatformApi {
  bool isSupported();
}

/// Registered only when SoundAnalysis is available.
@HostApi()
abstract class AppleSoundAnalysisHostApi {
  /// Labels, window defaults and window constraints of a classifier.
  @async
  ClassifierInfoMessage classifierInfo(ClassifierConfigMessage config);

  /// Starts classifying an audio file. Returns once the analysis has
  /// started; results follow through the callback API.
  @async
  void startFileAnalysis(
    int requestId,
    String path,
    ClassifierConfigMessage config,
    int? maximumClassifications,
  );

  /// Starts an analysis of PCM audio that Dart pushes with [analyzeSamples].
  @async
  void startStreamAnalysis(
    int requestId,
    AudioFormatMessage format,
    ClassifierConfigMessage config,
    int? maximumClassifications,
  );

  /// Feeds interleaved samples to a stream analysis, as the bytes of a
  /// little-endian `Float32List` (Pigeon has no float32 list type).
  @async
  void analyzeSamples(int requestId, Uint8List float32Samples);

  /// Flushes a stream analysis; its last results and completion follow.
  @async
  void completeStreamAnalysis(int requestId);

  /// Starts classifying the microphone until [cancel] is called.
  @async
  void startMicrophoneAnalysis(
    int requestId,
    ClassifierConfigMessage config,
    int? maximumClassifications,
  );

  /// Stops an analysis. No further callbacks arrive for [requestId].
  void cancel(int requestId);

  /// Stops every analysis. Returns how many were running.
  int cancelAll();

  MicrophonePermissionMessage microphonePermission();

  @async
  bool requestMicrophonePermission();
}

/// Native → Dart events, routed by request id.
@FlutterApi()
abstract class AppleSoundAnalysisCallbackApi {
  void onResult(ClassificationResultMessage result);

  void onComplete(int requestId);

  void onError(int requestId, String code, String message, String? details);
}
