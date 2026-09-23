import 'package:meta/meta.dart';

import 'messages.g.dart';

/// Converts seconds from the platform into a [Duration].
Duration secondsToDuration(double seconds) =>
    Duration(microseconds: (seconds * Duration.microsecondsPerSecond).round());

/// Whether the app may use speech recognition or the microphone.
///
/// Mirrors `SFSpeechRecognizerAuthorizationStatus` and
/// `AVAuthorizationStatus`.
enum AuthorizationStatus {
  /// The user has not been asked yet.
  notDetermined,

  /// The user denied access.
  denied,

  /// The device restricts access (for example, parental controls).
  restricted,

  /// The user granted access.
  authorized;

  /// Converts a platform message.
  static AuthorizationStatus fromMessage(AuthorizationStatusMessage message) =>
      switch (message) {
        AuthorizationStatusMessage.notDetermined => notDetermined,
        AuthorizationStatusMessage.denied => denied,
        AuthorizationStatusMessage.restricted => restricted,
        AuthorizationStatusMessage.authorized => authorized,
      };
}

/// A range of UTF-16 code units in a string, the way Dart indexes `String`.
@immutable
final class TextRange {
  /// Creates a range from [start] (inclusive) to [end] (exclusive).
  const TextRange(this.start, this.end);

  /// The first code unit.
  final int start;

  /// One past the last code unit.
  final int end;

  /// The number of code units.
  int get length => end - start;

  /// The part of [text] this range covers.
  String of(String text) => text.substring(start, end);

  @override
  bool operator ==(Object other) =>
      other is TextRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TextRange($start, $end)';
}

/// A word or phrase of a transcription, with its timing and confidence.
///
/// For `SFSpeechRecognizer` this mirrors `SFTranscriptionSegment`. For
/// `SpeechAnalyzer` transcribers it is one run of the result's
/// `AttributedString`: one per word when `ResultAttributeOption
/// .audioTimeRange` is requested, otherwise usually the whole text.
@immutable
final class TranscriptionSegment {
  /// Creates a segment.
  const TranscriptionSegment({
    required this.text,
    required this.range,
    this.startTime,
    this.endTime,
    this.confidence,
    this.alternatives = const [],
  });

  /// Converts a platform message.
  factory TranscriptionSegment.fromMessage(
    TranscriptionSegmentMessage message,
  ) => TranscriptionSegment(
    text: message.text,
    range: TextRange(message.start, message.start + message.length),
    startTime: switch (message.startTime) {
      final double seconds => secondsToDuration(seconds),
      null => null,
    },
    endTime: switch (message.endTime) {
      final double seconds => secondsToDuration(seconds),
      null => null,
    },
    confidence: message.confidence,
    alternatives: List.unmodifiable(message.alternatives),
  );

  /// The text of the segment, without surrounding whitespace.
  final String text;

  /// Where [text] is in the full transcription.
  final TextRange range;

  /// When the segment starts in the audio, if known.
  final Duration? startTime;

  /// When the segment ends in the audio, if known.
  final Duration? endTime;

  /// How long the segment is, if known.
  Duration? get duration => switch ((startTime, endTime)) {
    (final Duration start, final Duration end) => end - start,
    _ => null,
  };

  /// Confidence from 0 to 1, if known. `SFSpeechRecognizer` reports 0 for
  /// partial results.
  final double? confidence;

  /// Alternative texts for this segment (`SFSpeechRecognizer` only).
  final List<String> alternatives;

  @override
  String toString() =>
      'TranscriptionSegment("$text", $startTime-$endTime, '
      'confidence: $confidence)';
}

/// Where speech audio comes from.
@immutable
sealed class AudioSource {
  const AudioSource();

  /// An audio file (WAV, CAF, AIFF, M4A, MP3, ...) read with `AVAudioFile`.
  const factory AudioSource.file(String path) = FileAudioSource;

  /// Any media file, including video, read with `AVAsset`
  /// (`AssetInputSequenceProvider`). `SpeechAnalyzer` only, iOS/macOS 27.
  const factory AudioSource.asset(String path) = AssetAudioSource;

  /// The default microphone, captured with `AVAudioEngine`.
  ///
  /// Needs microphone authorization, `NSMicrophoneUsageDescription` and, on
  /// macOS, the `com.apple.security.device.audio-input` entitlement. On iOS
  /// the plugin activates a `.record` audio session unless
  /// [configureAudioSession] is false.
  const factory AudioSource.microphone({bool configureAudioSession}) =
      MicrophoneAudioSource;

  /// Plays [path] at real-time pace through the same buffer and conversion
  /// pipeline as the microphone. For tests; it needs no permissions.
  @visibleForTesting
  const factory AudioSource.simulatedMicrophone(String path) =
      SimulatedMicrophoneAudioSource;

  /// The message kind.
  AudioSourceKindMessage get kind;

  /// The file path, for file sources.
  String? get path => null;

  /// Whether the plugin configures the iOS audio session.
  bool get configureAudioSession => true;
}

/// See [AudioSource.file].
final class FileAudioSource extends AudioSource {
  /// Creates a file source.
  const FileAudioSource(this.path);

  @override
  final String path;

  @override
  AudioSourceKindMessage get kind => AudioSourceKindMessage.file;
}

/// See [AudioSource.asset].
final class AssetAudioSource extends AudioSource {
  /// Creates a media asset source.
  const AssetAudioSource(this.path);

  @override
  final String path;

  @override
  AudioSourceKindMessage get kind => AudioSourceKindMessage.asset;
}

/// See [AudioSource.microphone].
final class MicrophoneAudioSource extends AudioSource {
  /// Creates a microphone source.
  const MicrophoneAudioSource({this.configureAudioSession = true});

  @override
  final bool configureAudioSession;

  @override
  AudioSourceKindMessage get kind => AudioSourceKindMessage.microphone;
}

/// See [AudioSource.simulatedMicrophone].
@visibleForTesting
final class SimulatedMicrophoneAudioSource extends AudioSource {
  /// Creates a simulated microphone.
  const SimulatedMicrophoneAudioSource(this.path);

  @override
  final String path;

  @override
  AudioSourceKindMessage get kind => AudioSourceKindMessage.simulatedMicrophone;
}

/// An audio format (`AVAudioFormat`).
@immutable
final class AudioFormat {
  /// Creates a format.
  const AudioFormat({
    required this.sampleRate,
    required this.channelCount,
    required this.commonFormat,
    required this.isInterleaved,
  });

  /// Converts a platform message.
  factory AudioFormat.fromMessage(AudioFormatMessage message) => AudioFormat(
    sampleRate: message.sampleRate,
    channelCount: message.channelCount,
    commonFormat: message.commonFormat,
    isInterleaved: message.isInterleaved,
  );

  /// Samples per second.
  final double sampleRate;

  /// The number of channels.
  final int channelCount;

  /// `pcmFormatInt16`, `pcmFormatFloat32`, `pcmFormatFloat64`,
  /// `pcmFormatInt32` or `other`.
  final String commonFormat;

  /// Whether channels are interleaved.
  final bool isInterleaved;

  @override
  String toString() =>
      'AudioFormat(${sampleRate.round()} Hz, $channelCount ch, $commonFormat)';
}
