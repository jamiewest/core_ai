import 'dart:async';
import 'dart:typed_data';

import 'package:meta/meta.dart';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';

/// An immutable classifier configuration (`SNClassifySoundRequest`).
@immutable
final class SoundClassifier {
  /// Apple's built-in version-1 sound classifier.
  const SoundClassifier.builtIn({
    this.windowDurationSeconds,
    this.overlapFactor,
  }) : modelPath = null;

  /// A custom Core ML sound classifier at an absolute file path.
  const SoundClassifier.model(
    String path, {
    this.windowDurationSeconds,
    this.overlapFactor,
  }) : modelPath = path;

  /// `.mlmodel`, `.mlpackage` or `.mlmodelc`, or null for the built-in model.
  final String? modelPath;

  /// Window length in seconds; null uses the model default.
  final double? windowDurationSeconds;

  /// Window overlap in [0, 1); null uses the model default.
  final double? overlapFactor;

  ClassifierConfigMessage _message() => ClassifierConfigMessage(
    modelPath: modelPath,
    windowDurationSeconds: windowDurationSeconds,
    overlapFactor: overlapFactor,
  );

  /// Returns labels, effective settings, and valid window lengths.
  Future<ClassifierInfo> info() async => ClassifierInfo._(
    await guardPlatformCall(
      () => SoundAnalysisBindings.instance.host.classifierInfo(_message()),
    ),
  );
}

/// Classifier labels and window constraints.
@immutable
final class ClassifierInfo {
  ClassifierInfo._(ClassifierInfoMessage message)
    : knownClassifications = List.unmodifiable(message.knownClassifications),
      windowDurationSeconds = message.windowDurationSeconds,
      overlapFactor = message.overlapFactor,
      allowedWindowDurationsSeconds = List.unmodifiable(
        message.allowedWindowDurationsSeconds,
      ),
      minimumWindowSeconds = message.minimumWindowSeconds,
      maximumWindowSeconds = message.maximumWindowSeconds;

  /// All labels recognized by the model.
  final List<String> knownClassifications;

  /// Effective analysis window in seconds.
  final double windowDurationSeconds;

  /// Effective overlap between windows.
  final double overlapFactor;

  /// Exact allowed durations; empty for a continuous range.
  final List<double> allowedWindowDurationsSeconds;

  /// Minimum duration for a continuous range, otherwise null.
  final double? minimumWindowSeconds;

  /// Exclusive upper bound for a continuous range, otherwise null.
  final double? maximumWindowSeconds;
}

/// One model label and its confidence (`SNClassification`).
@immutable
final class Classification {
  /// Creates a classification.
  const Classification(this.identifier, this.confidence);

  /// Model label, such as `speech`.
  final String identifier;

  /// Confidence from zero to one.
  final double confidence;
}

/// A classified time window (`SNClassificationResult`).
@immutable
final class ClassificationResult {
  ClassificationResult._(ClassificationResultMessage message)
    : startSeconds = message.startSeconds,
      durationSeconds = message.durationSeconds,
      classifications = List.unmodifiable(
        message.classifications.map(
          (value) => Classification(value.identifier, value.confidence),
        ),
      );

  /// Beginning of the window relative to the audio's start.
  final double startSeconds;

  /// Length of the analyzed window.
  final double durationSeconds;

  /// Labels in descending confidence order.
  final List<Classification> classifications;

  /// Most confident label, or null for an empty result.
  Classification? get top =>
      classifications.isEmpty ? null : classifications.first;
}

/// Microphone authorization state.
enum MicrophonePermission {
  /// No permission decision has been made.
  notDetermined,

  /// Access is restricted by device policy.
  restricted,

  /// The user denied access.
  denied,

  /// The app has access.
  authorized;

  /// Reads authorization without prompting.
  static Future<MicrophonePermission> status() async =>
      values[(await guardPlatformCall(
        SoundAnalysisBindings.instance.host.microphonePermission,
      )).index];

  /// Requests authorization. The app must declare microphone usage strings.
  static Future<bool> request() => guardPlatformCall(
    SoundAnalysisBindings.instance.host.requestMicrophonePermission,
  );
}

/// File and microphone sound classification.
abstract final class SoundAnalyzer {
  /// Whether SoundAnalysis is available on this platform.
  static Future<bool> isSupported() async {
    try {
      return await SoundAnalysisBindings.instance.platform.isSupported();
    } on Object {
      return false;
    }
  }

  /// Classifies an audio file when listened to. Cancelling stops native work.
  static Stream<ClassificationResult> classifyFile(
    String path, {
    SoundClassifier classifier = const SoundClassifier.builtIn(),
    int? maximumClassifications,
  }) {
    final bindings = SoundAnalysisBindings.instance;
    return _Analysis(
      bindings,
      (id) => bindings.host.startFileAnalysis(
        id,
        path,
        classifier._message(),
        maximumClassifications,
      ),
    ).results;
  }

  /// Classifies the microphone until cancelled. Permission must be granted
  /// explicitly with [MicrophonePermission.request] before listening.
  static Stream<ClassificationResult> classifyMicrophone({
    SoundClassifier classifier = const SoundClassifier.builtIn(),
    int? maximumClassifications,
  }) {
    final bindings = SoundAnalysisBindings.instance;
    return _Analysis(
      bindings,
      (id) => bindings.host.startMicrophoneAnalysis(
        id,
        classifier._message(),
        maximumClassifications,
      ),
    ).results;
  }

  /// Cancels active analyses, closes their streams, and clears native leftovers.
  /// Returns the number of native analyses that were still running.
  static Future<int> cancelAll() async {
    final bindings = SoundAnalysisBindings.instance;
    if (bindings.cancellingAll) {
      throw StateError('cancelAll is already running.');
    }
    bindings.cancellingAll = true;
    final active = bindings.analyses.values.toList();
    try {
      for (final sink in active) {
        try {
          await sink.started;
        } on Object {
          /* Failed starts own no native resources. */
        }
      }
      final count = await guardPlatformCall(bindings.host.cancelAll);
      for (final sink in active) {
        sink.onComplete();
      }
      return count;
    } finally {
      bindings.cancellingAll = false;
    }
  }
}

/// Classifies interleaved little-endian float32 PCM supplied by Dart.
/// Listen to [results], await each [add], then [close] to flush the last windows.
/// Always [cancel] when abandoning an analysis.
final class SoundStreamClassifier {
  SoundStreamClassifier._(this._analysis, this.channelCount);
  final _Analysis _analysis;

  /// Number of interleaved channels in each sample frame.
  final int channelCount;
  Future<void> _tail = Future.value();
  Future<void>? _closing;
  bool _closed = false;

  /// Creates an analyzer for 1–32 channels at a finite rate up to 384 kHz.
  static Future<SoundStreamClassifier> create({
    required double sampleRate,
    int channelCount = 1,
    SoundClassifier classifier = const SoundClassifier.builtIn(),
    int? maximumClassifications,
  }) async {
    if (!sampleRate.isFinite || sampleRate <= 0 || sampleRate > 384000) {
      throw ArgumentError.value(sampleRate, 'sampleRate');
    }
    if (channelCount < 1 || channelCount > 32) {
      throw ArgumentError.value(channelCount, 'channelCount');
    }
    final bindings = SoundAnalysisBindings.instance;
    final analysis = _Analysis(
      bindings,
      (id) => bindings.host.startStreamAnalysis(
        id,
        AudioFormatMessage(sampleRate: sampleRate, channelCount: channelCount),
        classifier._message(),
        maximumClassifications,
      ),
    );
    await analysis.start();
    return SoundStreamClassifier._(analysis, channelCount);
  }

  /// Single-subscription stream of classified windows, buffered until listened to.
  Stream<ClassificationResult> get results => _analysis.results;

  Future<void> _enqueue(Future<void> Function() work) {
    final next = _tail.then((_) => work());
    _tail = next.catchError((Object _) {});
    return next;
  }

  /// Copies and enqueues complete frames. Samples must be finite.
  /// Calls are serialized even if their futures are not awaited by the caller.
  Future<void> add(Float32List samples) {
    if (_closed || _analysis.finished) throw StateError('The input is closed.');
    if (samples.length % channelCount != 0) {
      throw ArgumentError('Samples must contain whole interleaved frames.');
    }
    final data = ByteData(samples.length * 4);
    for (var i = 0; i < samples.length; i++) {
      if (!samples[i].isFinite) throw ArgumentError('Samples must be finite.');
      data.setFloat32(i * 4, samples[i], Endian.little);
    }
    return _enqueue(() async {
      if (_analysis.finished) throw StateError('The analysis has ended.');
      await guardPlatformCall(
        () => _analysis.bindings.host.analyzeSamples(
          _analysis.id,
          data.buffer.asUint8List(),
        ),
      );
    });
  }

  /// Finishes input after queued samples. Remaining results arrive on [results]
  /// before it closes. This method is idempotent and does not cancel results.
  Future<void> close() {
    _closed = true;
    return _closing ??= _enqueue(() async {
      if (_analysis.finished) return;
      await guardPlatformCall(
        () => _analysis.bindings.host.completeStreamAnalysis(_analysis.id),
      );
    });
  }

  /// Stops native analysis and closes [results]; safe to call repeatedly.
  Future<void> cancel() {
    _closed = true;
    return _analysis.cancel();
  }
}

class _Analysis implements AnalysisSink {
  _Analysis(this.bindings, this._startHost) : id = bindings.nextRequestId() {
    _controller = StreamController<ClassificationResult>(
      onListen: () {
        unawaited(start().catchError((Object e, StackTrace s) => _fail(e, s)));
      },
      onCancel: cancel,
    );
  }
  final SoundAnalysisBindings bindings;
  final int id;
  final Future<void> Function(int) _startHost;
  late final StreamController<ClassificationResult> _controller;
  Future<void>? _startup;
  Future<void>? _cancellation;
  bool finished = false;
  bool _didStart = false;
  Stream<ClassificationResult> get results => _controller.stream;
  @override
  Future<void> get started => _startup ?? Future.value();

  Future<void> start() => _startup ??= _start();
  Future<void> _start() async {
    if (finished) return;
    if (bindings.cancellingAll) throw StateError('cancelAll is running.');
    bindings.analyses[id] = this;
    try {
      await guardPlatformCall(() => _startHost(id));
      _didStart = true;
    } on Object {
      bindings.analyses.remove(id);
      rethrow;
    }
  }

  @override
  void onResult(ClassificationResultMessage result) {
    if (!finished) _controller.add(ClassificationResult._(result));
  }

  @override
  void onComplete() {
    if (finished) return;
    finished = true;
    bindings.analyses.remove(id);
    unawaited(_controller.close());
  }

  void _fail(Object error, StackTrace stack) {
    if (finished) return;
    _controller.addError(error, stack);
    onComplete();
  }

  @override
  void onError(String code, String message, String? details) => _fail(
    SoundAnalysisException(
      SoundAnalysisErrorCode.fromWire(code),
      message,
      details: details,
    ),
    StackTrace.current,
  );

  Future<void> cancel() => _cancellation ??= _cancel();
  Future<void> _cancel() async {
    if (finished) return;
    onComplete();
    try {
      await started;
    } on Object {
      return;
    }
    if (_didStart) await guardPlatformCall(() => bindings.host.cancel(id));
  }
}
