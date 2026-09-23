import 'package:meta/meta.dart';

import 'bindings.dart';
import 'common.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'modules.dart';
import 'request.dart';

/// How long Speech retains models after an analysis.
enum ModelRetention {
  /// Release models when no analysis needs them.
  whileInUse,

  /// Keep models briefly for another analysis.
  lingering,

  /// Keep models until the process ends or retention is explicitly ended.
  processLifetime,
}

/// Scheduling priority for an analysis.
enum AnalysisPriority {
  /// Background work.
  background,

  /// Utility work.
  utility,

  /// Low priority.
  low,

  /// Medium priority.
  medium,

  /// High priority.
  high,

  /// Work requested directly by the user.
  userInitiated,
}

/// Mirrors `SpeechAnalyzer.Options`.
@immutable
final class AnalyzerOptions {
  /// Creates options. Null [ignoresResourceLimits] keeps Apple's default.
  const AnalyzerOptions({
    this.priority = AnalysisPriority.userInitiated,
    this.modelRetention = ModelRetention.whileInUse,
    this.ignoresResourceLimits,
  });

  /// Scheduling priority.
  final AnalysisPriority priority;

  /// How long models stay loaded.
  final ModelRetention modelRetention;

  /// Whether to ignore resource limits (iOS/macOS 27; ignored on 26).
  final bool? ignoresResourceLimits;

  /// Converts to the platform representation.
  AnalyzerOptionsMessage toMessage() => AnalyzerOptionsMessage(
    priority: TaskPriorityMessage.values[priority.index],
    modelRetention: ModelRetentionMessage.values[modelRetention.index],
    ignoresResourceLimits: ignoresResourceLimits,
  );
}

/// A result from one module. Volatile results may be replaced by later results
/// covering the same audio range; append only final text to a transcript.
@immutable
final class AnalysisResult {
  /// Converts a platform result.
  AnalysisResult.fromMessage(AnalyzerResultMessage message)
    : moduleIndex = message.moduleIndex,
      rangeStart = secondsToDuration(message.rangeStart),
      rangeEnd = secondsToDuration(message.rangeEnd),
      resultsFinalizationTime = secondsToDuration(
        message.resultsFinalizationTime,
      ),
      isFinal = message.isFinal,
      text = message.text,
      segments = List.unmodifiable(
        message.segments.map(TranscriptionSegment.fromMessage),
      ),
      alternatives = List.unmodifiable(message.alternatives),
      speechDetected = message.speechDetected;

  /// Index into the modules supplied to [SpeechAnalyzer.analyze].
  final int moduleIndex;

  /// Start of the result's audio range.
  final Duration rangeStart;

  /// End of the result's audio range.
  final Duration rangeEnd;

  /// Results before this time will no longer change.
  final Duration resultsFinalizationTime;

  /// Whether this result is final.
  final bool isFinal;

  /// Transcribed text, or null for a detector result.
  final String? text;

  /// Attributed text runs, optionally with word times and confidence.
  final List<TranscriptionSegment> segments;

  /// Alternative transcriptions.
  final List<String> alternatives;

  /// Whether speech was detected, or null for a transcriber result.
  final bool? speechDetected;
}

/// A running analysis. Cancel it when leaving a screen that owns live input.
final class SpeechAnalysis extends SpeechRequest<AnalysisResult> {
  SpeechAnalysis._(super.bindings, super.requestId);

  /// Time of the last analyzed sample, set on successful completion if known.
  Duration? get lastSampleTime => _lastSampleTime;
  Duration? _lastSampleTime;

  @override
  void onAnalyzerResult(AnalyzerResultMessage result) =>
      addResult(AnalysisResult.fromMessage(result));

  @override
  void onFinished(double? lastSampleTime) {
    _lastSampleTime = lastSampleTime == null
        ? null
        : secondsToDuration(lastSampleTime);
  }
}

/// On-device analysis with `SpeechAnalyzer` (iOS/macOS 26 or later).
abstract final class SpeechAnalyzer {
  /// Starts analyzing [source]. Models must already be installed. This does
  /// not request speech or microphone authorization or download models.
  static Future<SpeechAnalysis> analyze({
    required AudioSource source,
    required List<SpeechModule> modules,
    AnalyzerOptions? options,
    Map<String, List<String>> contextualStrings = const {},
  }) async {
    final bindings = SpeechBindings.instance;
    final request = SpeechAnalysis._(bindings, bindings.nextRequestId());
    final message = AnalysisRequestMessage(
      requestId: request.requestId,
      source: source.kind,
      path: source.path,
      modules: modules.map((module) => module.toMessage()).toList(),
      options: options?.toMessage(),
      contextualStrings: contextualStrings.map(
        (key, value) => MapEntry(key, List.of(value)),
      ),
      configureAudioSession: source.configureAudioSession,
    );
    await request.begin(() => bindings.host.startAnalysis(message));
    return request;
  }

  /// The best format for [modules], or null when none is available.
  static Future<AudioFormat?> bestAvailableAudioFormat(
    List<SpeechModule> modules,
  ) async {
    final result = await guardPlatformCall(
      () => SpeechBindings.instance.host.bestAvailableAudioFormat(
        modules.map((module) => module.toMessage()).toList(),
      ),
    );
    return result == null ? null : AudioFormat.fromMessage(result);
  }

  /// Releases retained models when no longer needed.
  static Future<void> endModelRetention() =>
      guardPlatformCall(() => SpeechBindings.instance.host.endModelRetention());
}
