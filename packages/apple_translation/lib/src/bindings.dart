import 'dart:async';

import 'messages.g.dart';

/// Receives the events of one streaming batch request.
abstract interface class BatchSink {
  /// One request in the batch finished.
  void onResponse(TranslationResponseMessage response);

  /// Every request in the batch finished.
  void onDone();

  /// The batch failed.
  void onError(ErrorMessage error);
}

/// The platform APIs the apple_translation library talks to.
///
/// Replace [instance] in tests to run the Dart layer against fakes.
class TranslationBindings {
  /// Creates bindings, defaulting to the real platform channels.
  ///
  /// Pass `registerCallbacks: false` in tests that drive [callbackHandler]
  /// directly.
  TranslationBindings({
    AppleTranslationHostApi? host,
    AppleTranslationPlatformApi? platform,
    bool registerCallbacks = true,
  }) : host = host ?? AppleTranslationHostApi(),
       platform = platform ?? AppleTranslationPlatformApi() {
    if (registerCallbacks) {
      AppleTranslationCallbackApi.setUp(callbackHandler);
    }
  }

  /// The bindings every object uses.
  static TranslationBindings instance = TranslationBindings();

  /// The Translation API (registered only when the framework exists).
  final AppleTranslationHostApi host;

  /// The always-available platform API.
  final AppleTranslationPlatformApi platform;

  /// Receives native callbacks for streaming batches.
  ///
  /// Tests can call this directly to simulate the platform.
  late final AppleTranslationCallbackApi callbackHandler = _CallbackRouter(
    this,
  );

  /// Releases native handles whose Dart owners were garbage collected.
  late final Finalizer<int> finalizer = Finalizer<int>(
    (handle) => unawaited(host.release(handle).catchError((Object _) {})),
  );

  final Map<int, BatchSink> _batches = {};
  int _nextRequestId = 1;

  /// Reserves an id for a streaming request.
  int nextRequestId() => _nextRequestId++;

  /// Routes batch events for [requestId] to [sink].
  void registerBatch(int requestId, BatchSink sink) =>
      _batches[requestId] = sink;

  /// Stops routing events for [requestId].
  void unregisterBatch(int requestId) => _batches.remove(requestId);

  /// How many streaming batches are routed, for leak checks in tests.
  int get activeBatchCount => _batches.length;
}

class _CallbackRouter implements AppleTranslationCallbackApi {
  _CallbackRouter(this._bindings);

  final TranslationBindings _bindings;

  @override
  void onBatchResponse(int requestId, TranslationResponseMessage response) =>
      _bindings._batches[requestId]?.onResponse(response);

  @override
  void onBatchDone(int requestId) => _bindings._batches[requestId]?.onDone();

  @override
  void onBatchError(int requestId, ErrorMessage error) =>
      _bindings._batches[requestId]?.onError(error);
}
