import 'messages.g.dart';

/// Receives the native events of one request.
///
/// Every method does nothing by default; implementations override what
/// their request produces.
abstract class RequestSink {
  /// Cancels this request when supported.
  Future<void> cancel() async {}

  /// A `SpeechAnalyzer` module produced a result.
  void onAnalyzerResult(AnalyzerResultMessage result) {}

  /// `SFSpeechRecognizer` produced a result.
  void onRecognitionResult(RecognitionResultMessage result) {}

  /// An asset download progressed.
  void onInstallProgress(double fractionCompleted) {}

  /// The request finished.
  void onDone(double? lastSampleTime) {}

  /// The request failed.
  void onError(ErrorMessage error) {}
}

/// The platform APIs the apple_speech library talks to.
///
/// Replace [instance] in tests to run the Dart layer against fakes.
class SpeechBindings {
  /// Creates bindings, defaulting to the real platform channels.
  SpeechBindings({
    AppleSpeechHostApi? host,
    AppleSpeechPlatformApi? platform,
    bool registerCallbacks = true,
  }) : host = host ?? AppleSpeechHostApi(),
       platform = platform ?? AppleSpeechPlatformApi() {
    if (registerCallbacks) AppleSpeechCallbackApi.setUp(callbackHandler);
  }

  /// The bindings every API uses.
  static SpeechBindings instance = SpeechBindings();

  /// The Speech API.
  final AppleSpeechHostApi host;

  /// The always-available platform API.
  final AppleSpeechPlatformApi platform;

  /// Receives native events and routes them by request id.
  ///
  /// Tests can call this directly to simulate the platform.
  late final AppleSpeechCallbackApi callbackHandler = _CallbackRouter(this);

  final Map<int, RequestSink> _requests = {};
  int _nextRequestId = 1;

  /// Reserves an id for a new request.
  int nextRequestId() => _nextRequestId++;

  /// Routes events for [requestId] to [sink].
  void registerRequest(int requestId, RequestSink sink) =>
      _requests[requestId] = sink;

  /// Stops routing events for [requestId].
  void unregisterRequest(int requestId) => _requests.remove(requestId);

  /// Snapshot of currently routed requests.
  List<RequestSink> get activeRequests => List.of(_requests.values);

  /// How many requests are routed on the Dart side.
  int get routedRequestCount => _requests.length;
}

class _CallbackRouter implements AppleSpeechCallbackApi {
  _CallbackRouter(this._bindings);

  final SpeechBindings _bindings;

  RequestSink? _sink(int requestId) => _bindings._requests[requestId];

  @override
  void onAnalyzerResult(AnalyzerResultMessage result) =>
      _sink(result.requestId)?.onAnalyzerResult(result);

  @override
  void onRecognitionResult(RecognitionResultMessage result) =>
      _sink(result.requestId)?.onRecognitionResult(result);

  @override
  void onInstallProgress(int requestId, double fractionCompleted) =>
      _sink(requestId)?.onInstallProgress(fractionCompleted);

  @override
  void onRequestDone(int requestId, double? lastSampleTime) =>
      _sink(requestId)?.onDone(lastSampleTime);

  @override
  void onRequestError(int requestId, ErrorMessage error) =>
      _sink(requestId)?.onError(error);
}
