import 'dart:async';

import 'messages.g.dart';

/// Receives the events of one streaming face request.
abstract interface class FaceRequestSink {
  /// Faces found in one asset.
  void onAssetFaces(FaceGroupMessage assetFaces);

  /// The request finished.
  void onComplete();

  /// The request failed.
  void onError(RequestErrorMessage error);
}

/// The platform APIs the media_intelligence library talks to.
///
/// Replace [instance] in tests to run the Dart layer against fakes.
class MediaIntelligenceBindings {
  /// Creates bindings, defaulting to the real platform channels.
  ///
  /// Pass `registerCallbacks: false` with fakes, and drive
  /// [callbackHandler] directly.
  MediaIntelligenceBindings({
    MediaIntelligenceHostApi? host,
    MediaIntelligencePlatformApi? platform,
    bool registerCallbacks = true,
  }) : host = host ?? MediaIntelligenceHostApi(),
       platform = platform ?? MediaIntelligencePlatformApi() {
    if (registerCallbacks) MediaIntelligenceCallbackApi.setUp(callbackHandler);
  }

  /// The bindings every object uses.
  static MediaIntelligenceBindings instance = MediaIntelligenceBindings();

  /// The MediaIntelligence API (registered only on iOS 27 / macOS 27).
  final MediaIntelligenceHostApi host;

  /// The always-available platform API.
  final MediaIntelligencePlatformApi platform;

  /// Receives native callbacks. Tests can call it to simulate the platform.
  late final MediaIntelligenceCallbackApi callbackHandler = _CallbackRouter(
    this,
  );

  /// Releases native handles whose Dart owners were garbage collected.
  late final Finalizer<int> finalizer = Finalizer<int>(
    (handle) => unawaited(host.release(handle).catchError((Object _) {})),
  );

  final Map<int, FaceRequestSink> _requests = {};
  int _nextRequestId = 1;

  /// Reserves an id for a streaming request.
  int nextRequestId() => _nextRequestId++;

  /// Routes events for [requestId] to [sink].
  void registerRequest(int requestId, FaceRequestSink sink) =>
      _requests[requestId] = sink;

  /// Stops routing events for [requestId].
  void unregisterRequest(int requestId) => _requests.remove(requestId);

  /// How many streaming requests are routed, for leak checks.
  int get activeRequestCount => _requests.length;
}

class _CallbackRouter implements MediaIntelligenceCallbackApi {
  _CallbackRouter(this._bindings);

  final MediaIntelligenceBindings _bindings;

  @override
  void onAssetFaces(int requestId, FaceGroupMessage assetFaces) =>
      _bindings._requests[requestId]?.onAssetFaces(assetFaces);

  @override
  void onComplete(int requestId) =>
      _bindings._requests[requestId]?.onComplete();

  @override
  void onError(int requestId, RequestErrorMessage error) =>
      _bindings._requests[requestId]?.onError(error);
}
