import 'dart:async';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';

/// A running recognition or analysis whose results arrive as a [Stream].
///
/// Results are buffered until [results] is listened to. Cancelling the
/// subscription cancels the request.
abstract base class SpeechRequest<T> extends RequestSink {
  /// Creates a request routed by [requestId].
  SpeechRequest(this.bindings, this.requestId) {
    _controller = StreamController<T>(onCancel: cancel);
    // Errors are also delivered through [results]; don't make them unhandled.
    _done.future.ignore();
  }

  /// The bindings this request talks to.
  final SpeechBindings bindings;

  /// Identifies this request on the platform channel.
  final int requestId;

  late final StreamController<T> _controller;
  final Completer<void> _done = Completer<void>();
  bool _ended = false;

  /// The results, in order. The stream closes when the request finishes and
  /// reports a [SpeechException] if it fails.
  Stream<T> get results => _controller.stream;

  /// Completes when the request finishes (or is cancelled), or completes
  /// with a [SpeechException] if it fails.
  Future<void> get done => _done.future;

  /// Whether the request is still running.
  bool get isActive => !_ended;

  /// Starts routing events, then runs [start]. On failure, the request is
  /// closed and the error rethrown.
  Future<void> begin(Future<void> Function() start) async {
    bindings.registerRequest(requestId, this);
    try {
      await guardPlatformCall(start);
    } on Object catch (error, stack) {
      _ended = true;
      bindings.unregisterRequest(requestId);
      unawaited(_controller.close());
      _done.completeError(error, stack);
      rethrow;
    }
  }

  /// Ends live input (stops the microphone) and waits for the final results.
  ///
  /// For files this stops early and finalizes what was read so far.
  Future<void> finish() async {
    if (!_ended) {
      await guardPlatformCall(() => bindings.host.finishRequest(requestId));
    }
    await done;
  }

  /// Stops the request without waiting for more results. The [results]
  /// stream closes without an error. Safe to call more than once.
  Future<void> cancel() async {
    if (_ended) return;
    _ended = true;
    bindings.unregisterRequest(requestId);
    if (!_done.isCompleted) _done.complete();
    unawaited(_controller.close());
    await guardPlatformCall(() => bindings.host.cancelRequest(requestId));
  }

  /// Adds a converted result.
  void addResult(T result) {
    if (_ended || _controller.isClosed) return;
    _controller.add(result);
  }

  /// Called when the request finished successfully, before [results]
  /// closes.
  void onFinished(double? lastSampleTime) {}

  @override
  void onDone(double? lastSampleTime) {
    if (_ended) return;
    _ended = true;
    bindings.unregisterRequest(requestId);
    onFinished(lastSampleTime);
    _done.complete();
    unawaited(_controller.close());
  }

  @override
  void onError(ErrorMessage error) {
    if (_ended) return;
    _ended = true;
    bindings.unregisterRequest(requestId);
    final exception = SpeechException.fromMessage(error);
    _done.completeError(exception);
    _controller.addError(exception);
    unawaited(_controller.close());
  }
}
