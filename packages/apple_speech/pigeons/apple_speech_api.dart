// Pigeon schema for the apple_speech plugin.
//
// Regenerate with:
//   dart run pigeon --input pigeons/apple_speech_api.dart
//   dart format lib/src/messages.g.dart
//
// Conventions:
// * Locales travel as BCP 47 identifiers with hyphens ("en-US").
// * Times travel as seconds (double); Dart converts them to `Duration`.
// * Text ranges are UTF-16 code-unit offsets, matching Dart `String` indexes.
// * Recognition and analysis are requests identified by a Dart-chosen
//   `requestId`. Results, completion, errors and download progress arrive
//   through `AppleSpeechCallbackApi`. Dart cancels with `cancelRequest`, and
//   ends live input (the microphone) with `finishRequest`.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'darwin/apple_speech/Sources/apple_speech/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'AppleSpeechPigeonError'),
    dartPackageName: 'apple_speech',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------
/// Mirrors `SFSpeechRecognizerAuthorizationStatus` and
/// `AVAuthorizationStatus`.
enum AuthorizationStatusMessage {
  notDetermined,
  denied,
  restricted,
  authorized,
}

/// Mirrors `SFSpeechRecognitionTaskHint`.
enum TaskHintMessage { unspecified, dictation, search, confirmation }

/// Where audio comes from.
enum AudioSourceKindMessage {
  /// An audio file read with `AVAudioFile`.
  file,

  /// Any media file (audio or video) read with `AVAsset` (iOS/macOS 27).
  asset,

  /// The default input device, captured with `AVAudioEngine`.
  microphone,

  /// A file fed buffer by buffer through the microphone pipeline (tests).
  simulatedMicrophone,
}

/// The kind of a `SpeechModule`.
enum ModuleKindMessage {
  speechTranscriber,
  dictationTranscriber,
  speechDetector,
}

/// Mirrors `SpeechTranscriber.Preset`.
enum SpeechTranscriberPresetMessage {
  transcription,
  transcriptionWithAlternatives,
  timeIndexedTranscriptionWithAlternatives,
  progressiveTranscription,
  timeIndexedProgressiveTranscription,
}

/// Mirrors `DictationTranscriber.Preset`.
enum DictationPresetMessage {
  phrase,
  shortDictation,
  progressiveShortDictation,
  longDictation,
  progressiveLongDictation,
  timeIndexedLongDictation,
}

/// Mirrors `SpeechTranscriber.TranscriptionOption` and
/// `DictationTranscriber.TranscriptionOption`.
enum TranscriptionOptionMessage { punctuation, emoji, etiquetteReplacements }

/// Mirrors `SpeechTranscriber.ReportingOption` and
/// `DictationTranscriber.ReportingOption`.
enum ReportingOptionMessage {
  volatileResults,
  alternativeTranscriptions,
  fastResults,
  frequentFinalization,
}

/// Mirrors `ResultAttributeOption`.
enum ResultAttributeOptionMessage { audioTimeRange, transcriptionConfidence }

/// Mirrors `DictationTranscriber.ContentHint` (except custom language
/// models).
enum ContentHintMessage { shortForm, farField, atypicalSpeech }

/// Mirrors `SpeechDetector.SensitivityLevel`.
enum SensitivityLevelMessage { low, medium, high }

/// Mirrors `SpeechAnalyzer.Options.ModelRetention`.
enum ModelRetentionMessage { whileInUse, lingering, processLifetime }

/// Mirrors `TaskPriority`.
enum TaskPriorityMessage {
  background,
  utility,
  low,
  medium,
  high,
  userInitiated,
}

/// Mirrors `AssetInventory.Status`.
enum AssetStatusMessage { unsupported, supported, downloading, installed }

// ---------------------------------------------------------------------------
// Shared
// ---------------------------------------------------------------------------
/// One word or phrase of a transcription.
class TranscriptionSegmentMessage {
  TranscriptionSegmentMessage({
    required this.text,
    required this.start,
    required this.length,
    this.startTime,
    this.endTime,
    this.confidence,
    required this.alternatives,
  });

  String text;

  /// UTF-16 offset of the segment in the full text.
  int start;

  /// UTF-16 length of the segment in the full text.
  int length;

  /// Seconds from the start of the audio.
  double? startTime;
  double? endTime;

  /// 0...1.
  double? confidence;
  List<String> alternatives;
}

class ErrorMessage {
  ErrorMessage({required this.code, required this.message, this.details});

  String code;
  String message;
  String? details;
}

class AudioFormatMessage {
  AudioFormatMessage({
    required this.sampleRate,
    required this.channelCount,
    required this.commonFormat,
    required this.isInterleaved,
  });

  double sampleRate;
  int channelCount;

  /// `pcmFormatInt16`, `pcmFormatFloat32`, ... or `other`.
  String commonFormat;
  bool isInterleaved;
}

// ---------------------------------------------------------------------------
// SFSpeechRecognizer (iOS 10+ / macOS 10.15+)
// ---------------------------------------------------------------------------
class RecognizerInfoMessage {
  RecognizerInfoMessage({
    required this.locale,
    required this.isAvailable,
    required this.supportsOnDeviceRecognition,
    required this.defaultTaskHint,
  });

  String locale;
  bool isAvailable;
  bool supportsOnDeviceRecognition;
  TaskHintMessage defaultTaskHint;
}

class RecognitionRequestMessage {
  RecognitionRequestMessage({
    required this.requestId,
    this.locale,
    required this.source,
    this.path,
    required this.taskHint,
    required this.shouldReportPartialResults,
    required this.contextualStrings,
    required this.requiresOnDeviceRecognition,
    this.addsPunctuation,
    required this.configureAudioSession,
  });

  int requestId;

  /// Null for the user's current locale.
  String? locale;

  /// `file` or `microphone`.
  AudioSourceKindMessage source;
  String? path;
  TaskHintMessage taskHint;
  bool shouldReportPartialResults;
  List<String> contextualStrings;
  bool requiresOnDeviceRecognition;

  /// iOS 16 / macOS 13; null keeps Apple's default.
  bool? addsPunctuation;

  /// iOS only: activate a recording `AVAudioSession` for the microphone.
  bool configureAudioSession;
}

class TranscriptionMessage {
  TranscriptionMessage({required this.formattedString, required this.segments});

  String formattedString;
  List<TranscriptionSegmentMessage> segments;
}

class RecognitionMetadataMessage {
  RecognitionMetadataMessage({
    required this.speakingRate,
    required this.averagePauseDuration,
    required this.speechStartTimestamp,
    required this.speechDuration,
  });

  double speakingRate;
  double averagePauseDuration;
  double speechStartTimestamp;
  double speechDuration;
}

class RecognitionResultMessage {
  RecognitionResultMessage({
    required this.requestId,
    required this.bestTranscription,
    required this.transcriptions,
    required this.isFinal,
    this.metadata,
  });

  int requestId;
  TranscriptionMessage bestTranscription;
  List<TranscriptionMessage> transcriptions;
  bool isFinal;
  RecognitionMetadataMessage? metadata;
}

// ---------------------------------------------------------------------------
// SpeechAnalyzer (iOS 26+ / macOS 26+)
// ---------------------------------------------------------------------------
/// A `SpeechTranscriber`, `DictationTranscriber` or `SpeechDetector`.
class ModuleConfigMessage {
  ModuleConfigMessage({
    required this.kind,
    this.locale,
    this.speechPreset,
    this.dictationPreset,
    required this.transcriptionOptions,
    required this.reportingOptions,
    required this.attributeOptions,
    required this.contentHints,
    this.sensitivityLevel,
    this.reportResults,
  });

  ModuleKindMessage kind;

  /// Transcribers only.
  String? locale;

  /// When set, used instead of the option lists.
  SpeechTranscriberPresetMessage? speechPreset;
  DictationPresetMessage? dictationPreset;
  List<TranscriptionOptionMessage> transcriptionOptions;
  List<ReportingOptionMessage> reportingOptions;
  List<ResultAttributeOptionMessage> attributeOptions;
  List<ContentHintMessage> contentHints;

  /// Detector only.
  SensitivityLevelMessage? sensitivityLevel;
  bool? reportResults;
}

class AnalyzerOptionsMessage {
  AnalyzerOptionsMessage({
    required this.priority,
    required this.modelRetention,
    this.ignoresResourceLimits,
  });

  TaskPriorityMessage priority;
  ModelRetentionMessage modelRetention;

  /// iOS/macOS 27.
  bool? ignoresResourceLimits;
}

class AnalysisRequestMessage {
  AnalysisRequestMessage({
    required this.requestId,
    required this.source,
    this.path,
    required this.modules,
    this.options,
    required this.contextualStrings,
    required this.configureAudioSession,
  });

  int requestId;
  AudioSourceKindMessage source;
  String? path;
  List<ModuleConfigMessage> modules;
  AnalyzerOptionsMessage? options;

  /// `AnalysisContext.contextualStrings`, keyed by tag (e.g. "general").
  Map<String, List<String>> contextualStrings;

  /// iOS only: activate a recording `AVAudioSession` for the microphone.
  bool configureAudioSession;
}

/// A result from one module of an analysis.
class AnalyzerResultMessage {
  AnalyzerResultMessage({
    required this.requestId,
    required this.moduleIndex,
    required this.rangeStart,
    required this.rangeEnd,
    required this.resultsFinalizationTime,
    required this.isFinal,
    this.text,
    required this.segments,
    required this.alternatives,
    this.speechDetected,
  });

  int requestId;

  /// Index into `AnalysisRequestMessage.modules`.
  int moduleIndex;
  double rangeStart;
  double rangeEnd;
  double resultsFinalizationTime;
  bool isFinal;

  /// Transcribers: the transcribed text.
  String? text;

  /// Transcribers: the runs of `text` with their attributes.
  List<TranscriptionSegmentMessage> segments;

  /// Transcribers: alternative transcriptions, best first.
  List<String> alternatives;

  /// Detector: whether speech was detected in the range.
  bool? speechDetected;
}

// ---------------------------------------------------------------------------
// APIs
// ---------------------------------------------------------------------------
/// Always available.
@HostApi()
abstract class AppleSpeechPlatformApi {
  /// Whether the Speech framework is available (`SFSpeechRecognizer`).
  bool isSupported();

  /// Whether `SpeechAnalyzer` is available (iOS/macOS 26+).
  bool isAnalyzerSupported();

  /// Whether iOS/macOS 27 additions are available.
  bool isVersion27Supported();
}

/// Registered when the Speech framework can be imported.
@HostApi()
abstract class AppleSpeechHostApi {
  // -- Authorization ----------------------------------------------------------
  AuthorizationStatusMessage speechAuthorizationStatus();

  @async
  AuthorizationStatusMessage requestSpeechAuthorization();

  AuthorizationStatusMessage microphoneAuthorizationStatus();

  @async
  AuthorizationStatusMessage requestMicrophoneAuthorization();

  // -- SFSpeechRecognizer -----------------------------------------------------
  @async
  List<String> recognizerSupportedLocales();

  /// Null when no recognizer exists for [locale].
  @async
  RecognizerInfoMessage? recognizerInfo(String? locale);

  /// Starts recognition; results arrive through the callback API.
  @async
  void startRecognition(RecognitionRequestMessage request);

  // -- SpeechAnalyzer ---------------------------------------------------------
  bool speechTranscriberIsAvailable();

  @async
  List<String> supportedLocales(ModuleKindMessage kind);

  @async
  List<String> installedLocales(ModuleKindMessage kind);

  @async
  String? supportedLocaleEquivalent(ModuleKindMessage kind, String locale);

  @async
  AssetStatusMessage assetStatus(List<ModuleConfigMessage> modules);

  /// Downloads and installs assets; returns false when nothing was needed.
  /// Progress arrives through `onInstallProgress`.
  @async
  bool installAssets(int requestId, List<ModuleConfigMessage> modules);

  @async
  List<String> reservedLocales();

  int maximumReservedLocales();

  @async
  bool reserveLocale(String locale);

  @async
  bool releaseLocale(String locale);

  @async
  AudioFormatMessage? bestAvailableAudioFormat(
    List<ModuleConfigMessage> modules,
  );

  /// Starts an analysis; results arrive through the callback API.
  @async
  void startAnalysis(AnalysisRequestMessage request);

  @async
  void endModelRetention();

  // -- Requests ---------------------------------------------------------------
  /// Ends live input (stops the microphone) and finalizes the results.
  void finishRequest(int requestId);

  /// Cancels a request. No further events are sent for it.
  void cancelRequest(int requestId);

  /// Cancels every request; returns how many were active.
  int cancelAll();

  int activeRequestCount();
}

/// Native -> Dart.
@FlutterApi()
abstract class AppleSpeechCallbackApi {
  void onAnalyzerResult(AnalyzerResultMessage result);

  void onRecognitionResult(RecognitionResultMessage result);

  void onInstallProgress(int requestId, double fractionCompleted);

  /// The request finished. For analyses, [lastSampleTime] is the end of the
  /// analyzed audio in seconds.
  void onRequestDone(int requestId, double? lastSampleTime);

  void onRequestError(int requestId, ErrorMessage error);
}
