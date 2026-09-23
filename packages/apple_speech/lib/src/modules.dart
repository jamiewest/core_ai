import 'package:meta/meta.dart';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';

/// Mirrors `SpeechTranscriber.Preset`.
enum SpeechTranscriberPreset {
  /// Final results only, no timing.
  transcription,

  /// Final results with alternative transcriptions.
  transcriptionWithAlternatives,

  /// Final results with alternatives and word timing.
  timeIndexedTranscriptionWithAlternatives,

  /// Volatile (in-progress) and final results, tuned for live audio.
  progressiveTranscription,

  /// Volatile and final results with word timing.
  timeIndexedProgressiveTranscription,
}

/// Mirrors `DictationTranscriber.Preset`.
enum DictationTranscriberPreset {
  /// A short phrase, such as a search query.
  phrase,

  /// A short dictation.
  shortDictation,

  /// A short dictation with volatile results.
  progressiveShortDictation,

  /// A long dictation.
  longDictation,

  /// A long dictation with volatile results.
  progressiveLongDictation,

  /// A long dictation with word timing.
  timeIndexedLongDictation,
}

/// Mirrors `TranscriptionOption`.
///
/// `SpeechTranscriber` supports only [etiquetteReplacements];
/// `DictationTranscriber` supports all of them.
enum TranscriptionOption {
  /// Adds punctuation (`DictationTranscriber` only).
  punctuation,

  /// Turns spoken emoji names into emoji (`DictationTranscriber` only).
  emoji,

  /// Replaces profanity with a redacted form.
  etiquetteReplacements,
}

/// Mirrors `ReportingOption`.
enum ReportingOption {
  /// Report volatile (in-progress) results as well as final ones.
  volatileResults,

  /// Report alternative transcriptions.
  alternativeTranscriptions,

  /// Favor latency over accuracy (`SpeechTranscriber` only).
  fastResults,

  /// Finalize results more often (`DictationTranscriber` only).
  frequentFinalization,
}

/// Mirrors `ResultAttributeOption`: extra attributes on each word.
enum ResultAttributeOption {
  /// The audio time range of each word ([TranscriptionSegment.startTime]).
  audioTimeRange,

  /// The confidence of each word ([TranscriptionSegment.confidence]).
  transcriptionConfidence,
}

/// Mirrors `DictationTranscriber.ContentHint`.
enum DictationContentHint {
  /// Short utterances.
  shortForm,

  /// Speech far from the microphone.
  farField,

  /// Atypical speech patterns.
  atypicalSpeech,
}

/// Mirrors `SpeechDetector.SensitivityLevel`.
enum SpeechDetectorSensitivity {
  /// Only clear speech.
  low,

  /// The default.
  medium,

  /// Also quiet or distant speech.
  high,
}

/// A module that a `SpeechAnalyzer` runs over the audio.
///
/// Mirrors Swift's `SpeechModule` protocol. These are plain configuration
/// values; the native modules are created for each analysis.
@immutable
sealed class SpeechModule {
  const SpeechModule();

  /// Converts to a platform message.
  ModuleConfigMessage toMessage();
}

/// Speech-to-text for general audio: conversations, meetings, media.
///
/// Mirrors `SpeechTranscriber` (iOS 26 / macOS 26).
final class SpeechTranscriber extends SpeechModule {
  /// A transcriber for [locale] (such as `en-US`) using [preset].
  const SpeechTranscriber({
    required this.locale,
    SpeechTranscriberPreset this.preset = SpeechTranscriberPreset.transcription,
  }) : transcriptionOptions = const {},
       reportingOptions = const {},
       attributeOptions = const {};

  /// A transcriber with explicit options instead of a preset.
  const SpeechTranscriber.custom({
    required this.locale,
    this.transcriptionOptions = const {},
    this.reportingOptions = const {},
    this.attributeOptions = const {},
  }) : preset = null;

  /// The locale, as a BCP 47 identifier such as `en-US`. The plugin uses
  /// `supportedLocale(equivalentTo:)` to pick the matching model.
  final String locale;

  /// The preset, or null when the options are explicit.
  final SpeechTranscriberPreset? preset;

  /// Transcription options (only [TranscriptionOption.etiquetteReplacements]
  /// applies).
  final Set<TranscriptionOption> transcriptionOptions;

  /// Which results to report.
  final Set<ReportingOption> reportingOptions;

  /// Which attributes to attach to each word.
  final Set<ResultAttributeOption> attributeOptions;

  /// Whether `SpeechTranscriber` can run on this device.
  static Future<bool> isAvailable() async {
    try {
      return await SpeechBindings.instance.host.speechTranscriberIsAvailable();
    } on Object {
      return false;
    }
  }

  /// Locales the transcriber supports (some may need a download).
  static Future<List<String>> supportedLocales() =>
      _supportedLocales(ModuleKindMessage.speechTranscriber);

  /// Locales whose models are installed on this device.
  static Future<List<String>> installedLocales() =>
      _installedLocales(ModuleKindMessage.speechTranscriber);

  /// The supported locale that best matches [locale], or null.
  static Future<String?> supportedLocale({required String equivalentTo}) =>
      _equivalent(ModuleKindMessage.speechTranscriber, equivalentTo);

  @override
  ModuleConfigMessage toMessage() => ModuleConfigMessage(
    kind: ModuleKindMessage.speechTranscriber,
    locale: locale,
    speechPreset: switch (preset) {
      null => null,
      final value => SpeechTranscriberPresetMessage.values[value.index],
    },
    transcriptionOptions: _transcriptionOptions(transcriptionOptions),
    reportingOptions: _reportingOptions(reportingOptions),
    attributeOptions: _attributeOptions(attributeOptions),
    contentHints: const [],
  );

  @override
  String toString() =>
      'SpeechTranscriber($locale, ${preset?.name ?? 'custom'})';
}

/// Speech-to-text tuned for dictation, with punctuation and emoji options.
///
/// Mirrors `DictationTranscriber` (iOS 26 / macOS 26). It uses the same
/// models as keyboard dictation and supports more locales than
/// [SpeechTranscriber].
final class DictationTranscriber extends SpeechModule {
  /// A dictation transcriber for [locale] using [preset].
  const DictationTranscriber({
    required this.locale,
    DictationTranscriberPreset this.preset =
        DictationTranscriberPreset.longDictation,
  }) : contentHints = const {},
       transcriptionOptions = const {},
       reportingOptions = const {},
       attributeOptions = const {};

  /// A dictation transcriber with explicit options instead of a preset.
  const DictationTranscriber.custom({
    required this.locale,
    this.contentHints = const {},
    this.transcriptionOptions = const {},
    this.reportingOptions = const {},
    this.attributeOptions = const {},
  }) : preset = null;

  /// The locale, as a BCP 47 identifier such as `en-US`.
  final String locale;

  /// The preset, or null when the options are explicit.
  final DictationTranscriberPreset? preset;

  /// Hints about the audio.
  final Set<DictationContentHint> contentHints;

  /// Transcription options.
  final Set<TranscriptionOption> transcriptionOptions;

  /// Which results to report.
  final Set<ReportingOption> reportingOptions;

  /// Which attributes to attach to each word.
  final Set<ResultAttributeOption> attributeOptions;

  /// Locales dictation supports (some may need a download).
  static Future<List<String>> supportedLocales() =>
      _supportedLocales(ModuleKindMessage.dictationTranscriber);

  /// Locales whose dictation models are installed on this device.
  static Future<List<String>> installedLocales() =>
      _installedLocales(ModuleKindMessage.dictationTranscriber);

  /// The supported locale that best matches [locale], or null.
  static Future<String?> supportedLocale({required String equivalentTo}) =>
      _equivalent(ModuleKindMessage.dictationTranscriber, equivalentTo);

  @override
  ModuleConfigMessage toMessage() => ModuleConfigMessage(
    kind: ModuleKindMessage.dictationTranscriber,
    locale: locale,
    dictationPreset: switch (preset) {
      null => null,
      final value => DictationPresetMessage.values[value.index],
    },
    transcriptionOptions: _transcriptionOptions(transcriptionOptions),
    reportingOptions: _reportingOptions(reportingOptions),
    attributeOptions: _attributeOptions(attributeOptions),
    contentHints: [
      for (final hint in contentHints) ContentHintMessage.values[hint.index],
    ],
  );

  @override
  String toString() =>
      'DictationTranscriber($locale, ${preset?.name ?? 'custom'})';
}

/// Detects whether audio contains speech.
///
/// Mirrors `SpeechDetector` (iOS 26 / macOS 26). It must run alongside a
/// transcriber in the same analysis.
final class SpeechDetector extends SpeechModule {
  /// Creates a detector.
  const SpeechDetector({
    this.sensitivity = SpeechDetectorSensitivity.medium,
    this.reportResults = true,
  });

  /// How readily speech is detected.
  final SpeechDetectorSensitivity sensitivity;

  /// Whether to report detection results.
  final bool reportResults;

  @override
  ModuleConfigMessage toMessage() => ModuleConfigMessage(
    kind: ModuleKindMessage.speechDetector,
    sensitivityLevel: SensitivityLevelMessage.values[sensitivity.index],
    reportResults: reportResults,
    transcriptionOptions: const [],
    reportingOptions: const [],
    attributeOptions: const [],
    contentHints: const [],
  );

  @override
  String toString() => 'SpeechDetector(${sensitivity.name})';
}

List<TranscriptionOptionMessage> _transcriptionOptions(
  Set<TranscriptionOption> options,
) => [
  for (final option in options) TranscriptionOptionMessage.values[option.index],
];

List<ReportingOptionMessage> _reportingOptions(Set<ReportingOption> options) =>
    [for (final option in options) ReportingOptionMessage.values[option.index]];

List<ResultAttributeOptionMessage> _attributeOptions(
  Set<ResultAttributeOption> options,
) => [
  for (final option in options)
    ResultAttributeOptionMessage.values[option.index],
];

Future<List<String>> _supportedLocales(ModuleKindMessage kind) =>
    guardPlatformCall(
      () => SpeechBindings.instance.host.supportedLocales(kind),
    );

Future<List<String>> _installedLocales(ModuleKindMessage kind) =>
    guardPlatformCall(
      () => SpeechBindings.instance.host.installedLocales(kind),
    );

Future<String?> _equivalent(ModuleKindMessage kind, String locale) =>
    guardPlatformCall(
      () =>
          SpeechBindings.instance.host.supportedLocaleEquivalent(kind, locale),
    );
