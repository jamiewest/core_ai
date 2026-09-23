import 'messages.g.dart';

/// Receives callbacks for one analysis; exposed for fake hosts in tests.
abstract interface class AnalysisSink {
  /// Completes when native startup has been acknowledged.
  Future<void> get started;

  /// Delivers a classification window.
  void onResult(ClassificationResultMessage result);

  /// Closes the result stream.
  void onComplete();

  /// Delivers a terminal native failure.
  void onError(String code, String message, String? details);
}

/// Injectable platform bindings and callback routing.
class SoundAnalysisBindings {
  /// Creates bindings; disable callback registration when driving fakes.
  SoundAnalysisBindings({
    AppleSoundAnalysisHostApi? host,
    AppleSoundAnalysisPlatformApi? platform,
    bool registerCallbacks = true,
  }) : host = host ?? AppleSoundAnalysisHostApi(),
       platform = platform ?? AppleSoundAnalysisPlatformApi() {
    if (registerCallbacks) AppleSoundAnalysisCallbackApi.setUp(callbackHandler);
  }

  /// Bindings used for new analyses.
  static SoundAnalysisBindings instance = SoundAnalysisBindings();

  /// Native operations.
  final AppleSoundAnalysisHostApi host;

  /// Platform support query.
  final AppleSoundAnalysisPlatformApi platform;

  /// Callback receiver; tests may invoke it directly.
  late final AppleSoundAnalysisCallbackApi callbackHandler = _Router(this);

  /// Active routes, for cancellation and leak checks.
  final Map<int, AnalysisSink> analyses = {};

  /// Blocks starts during a cancel-all operation.
  bool cancellingAll = false;
  int _nextId = 1;

  /// Allocates an identifier for this engine's next analysis.
  int nextRequestId() => _nextId++;
}

class _Router implements AppleSoundAnalysisCallbackApi {
  _Router(this.bindings);
  final SoundAnalysisBindings bindings;
  @override
  void onResult(ClassificationResultMessage result) =>
      bindings.analyses[result.requestId]?.onResult(result);
  @override
  void onComplete(int requestId) => bindings.analyses[requestId]?.onComplete();
  @override
  void onError(int requestId, String code, String message, String? details) =>
      bindings.analyses[requestId]?.onError(code, message, details);
}
