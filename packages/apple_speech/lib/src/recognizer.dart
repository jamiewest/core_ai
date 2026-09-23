import 'package:meta/meta.dart';

import 'bindings.dart';
import 'common.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'request.dart';

/// The kind of utterance expected by `SFSpeechRecognizer`.
enum RecognitionTaskHint {
  /// No hint.
  unspecified,

  /// Dictated text.
  dictation,

  /// A search query.
  search,

  /// A short confirmation.
  confirmation,
}

/// Availability of a legacy speech recognizer for one locale.
@immutable
final class RecognizerInfo {
  /// Converts platform information.
  RecognizerInfo.fromMessage(RecognizerInfoMessage message)
    : locale = message.locale,
      isAvailable = message.isAvailable,
      supportsOnDeviceRecognition = message.supportsOnDeviceRecognition,
      defaultTaskHint =
          RecognitionTaskHint.values[message.defaultTaskHint.index];

  /// BCP 47 locale identifier.
  final String locale;

  /// Whether the recognizer is currently available.
  final bool isAvailable;

  /// Whether requests can require on-device processing.
  final bool supportsOnDeviceRecognition;

  /// Apple's default task hint.
  final RecognitionTaskHint defaultTaskHint;
}

/// A complete transcription hypothesis from `SFSpeechRecognizer`.
@immutable
final class Transcription {
  /// Converts a platform transcription.
  Transcription.fromMessage(TranscriptionMessage message)
    : formattedString = message.formattedString,
      segments = List.unmodifiable(
        message.segments.map(TranscriptionSegment.fromMessage),
      );

  /// The complete formatted text, replacing earlier partial hypotheses.
  final String formattedString;

  /// Words with timing, confidence and alternatives.
  final List<TranscriptionSegment> segments;
}

/// Timing and speaking-rate statistics from the legacy recognizer.
@immutable
final class RecognitionMetadata {
  /// Converts platform metadata.
  RecognitionMetadata.fromMessage(RecognitionMetadataMessage message)
    : speakingRate = message.speakingRate,
      averagePauseDuration = secondsToDuration(message.averagePauseDuration),
      speechStartTimestamp = secondsToDuration(message.speechStartTimestamp),
      speechDuration = secondsToDuration(message.speechDuration);

  /// Words per minute.
  final double speakingRate;

  /// Mean pause duration.
  final Duration averagePauseDuration;

  /// Start of speech in the source.
  final Duration speechStartTimestamp;

  /// Duration of speech.
  final Duration speechDuration;
}

/// One partial or final recognition result.
@immutable
final class RecognitionResult {
  /// Converts a platform result.
  RecognitionResult.fromMessage(RecognitionResultMessage message)
    : bestTranscription = Transcription.fromMessage(message.bestTranscription),
      transcriptions = List.unmodifiable(
        message.transcriptions.map(Transcription.fromMessage),
      ),
      isFinal = message.isFinal,
      metadata = message.metadata == null
          ? null
          : RecognitionMetadata.fromMessage(message.metadata!);

  /// Most likely complete hypothesis.
  final Transcription bestTranscription;

  /// All hypotheses, ordered by confidence.
  final List<Transcription> transcriptions;

  /// Whether recognition is complete.
  final bool isFinal;

  /// Statistics, usually available with final results.
  final RecognitionMetadata? metadata;
}

/// An active `SFSpeechRecognizer` request.
final class SpeechRecognition extends SpeechRequest<RecognitionResult> {
  SpeechRecognition._(super.bindings, super.requestId);

  @override
  void onRecognitionResult(RecognitionResultMessage result) =>
      addResult(RecognitionResult.fromMessage(result));
}

/// The legacy `SFSpeechRecognizer` API (iOS 15 / macOS 12 deployment targets).
/// Requires speech authorization even for file input. Unless
/// `requiresOnDeviceRecognition` is true, Apple may use its online service.
abstract final class SpeechRecognizer {
  /// Queries speech authorization without prompting.
  static Future<AuthorizationStatus> authorizationStatus() async =>
      AuthorizationStatus.fromMessage(
        await guardPlatformCall(
          () => SpeechBindings.instance.host.speechAuthorizationStatus(),
        ),
      );

  /// Requests speech authorization. Requires NSSpeechRecognitionUsageDescription.
  static Future<AuthorizationStatus> requestAuthorization() async =>
      AuthorizationStatus.fromMessage(
        await guardPlatformCall(
          () => SpeechBindings.instance.host.requestSpeechAuthorization(),
        ),
      );

  /// Supported BCP 47 locale identifiers.
  static Future<List<String>> supportedLocales() => guardPlatformCall(
    () => SpeechBindings.instance.host.recognizerSupportedLocales(),
  );

  /// Availability for [locale], or the user's current locale when omitted.
  static Future<RecognizerInfo?> info({String? locale}) async {
    final result = await guardPlatformCall(
      () => SpeechBindings.instance.host.recognizerInfo(locale),
    );
    return result == null ? null : RecognizerInfo.fromMessage(result);
  }

  /// Starts recognition without prompting for permissions. Media assets are
  /// unsupported; use a file or microphone source.
  static Future<SpeechRecognition> recognize({
    required AudioSource source,
    String? locale,
    RecognitionTaskHint taskHint = RecognitionTaskHint.unspecified,
    bool shouldReportPartialResults = true,
    List<String> contextualStrings = const [],
    bool requiresOnDeviceRecognition = false,
    bool? addsPunctuation,
  }) async {
    final bindings = SpeechBindings.instance;
    final request = SpeechRecognition._(bindings, bindings.nextRequestId());
    final message = RecognitionRequestMessage(
      requestId: request.requestId,
      locale: locale,
      source: source.kind,
      path: source.path,
      taskHint: TaskHintMessage.values[taskHint.index],
      shouldReportPartialResults: shouldReportPartialResults,
      contextualStrings: List.of(contextualStrings),
      requiresOnDeviceRecognition: requiresOnDeviceRecognition,
      addsPunctuation: addsPunctuation,
      configureAudioSession: source.configureAudioSession,
    );
    await request.begin(() => bindings.host.startRecognition(message));
    return request;
  }
}
