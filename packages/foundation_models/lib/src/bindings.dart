import 'dart:async';

import 'content.dart';
import 'messages.g.dart';
import 'tools.dart';

/// Handles one in-flight streaming request.
abstract interface class StreamSink {
  /// A new cumulative snapshot arrived.
  void onSnapshot(StreamSnapshotMessage snapshot);

  /// The stream finished.
  void onDone(ResponseMessage response);

  /// The stream failed.
  void onError(ErrorMessage error);
}

/// Runs a tool call that the model requested.
abstract interface class ToolHost {
  /// Runs tool [name] with [arguments].
  Future<ToolOutput> runTool(String name, GeneratedContent arguments);
}

/// The platform APIs the foundation_models library talks to.
///
/// Replace [instance] in tests to run the Dart layer against fakes.
class FoundationModelsBindings {
  /// Creates bindings, defaulting to the real platform channels.
  FoundationModelsBindings({
    FoundationModelsHostApi? host,
    FoundationModelsPlatformApi? platform,
    bool registerCallbacks = true,
  }) : host = host ?? FoundationModelsHostApi(),
       platform = platform ?? FoundationModelsPlatformApi() {
    if (registerCallbacks) {
      FoundationModelsCallbackApi.setUp(callbackHandler);
    }
  }

  /// The bindings every object uses.
  static FoundationModelsBindings instance = FoundationModelsBindings();

  /// The Foundation Models API (registered only when the framework exists).
  final FoundationModelsHostApi host;

  /// The always-available platform API.
  final FoundationModelsPlatformApi platform;

  /// Receives native callbacks: tool calls and stream events.
  ///
  /// Tests can call this directly to simulate the platform.
  late final FoundationModelsCallbackApi callbackHandler = _CallbackRouter(
    this,
  );

  /// Releases native handles whose Dart owners were garbage collected.
  late final Finalizer<int> finalizer = Finalizer<int>(
    (handle) => unawaited(host.release(handle).catchError((Object _) {})),
  );

  final Map<int, StreamSink> _streams = {};
  final Map<int, ToolHost> _toolHosts = {};
  int _nextRequestId = 1;

  /// Reserves a request id for a streaming or cancellable request.
  int nextRequestId() => _nextRequestId++;

  /// Routes stream events for [requestId] to [sink].
  void registerStream(int requestId, StreamSink sink) =>
      _streams[requestId] = sink;

  /// Stops routing events for [requestId].
  void unregisterStream(int requestId) => _streams.remove(requestId);

  /// Routes tool calls for [sessionHandle] to [host].
  void registerToolHost(int sessionHandle, ToolHost host) =>
      _toolHosts[sessionHandle] = host;

  /// Stops routing tool calls for [sessionHandle].
  void unregisterToolHost(int sessionHandle) =>
      _toolHosts.remove(sessionHandle);
}

class _CallbackRouter implements FoundationModelsCallbackApi {
  _CallbackRouter(this._bindings);

  final FoundationModelsBindings _bindings;

  @override
  Future<ToolResultMessage> callTool(ToolCallRequestMessage request) async {
    final host = _bindings._toolHosts[request.sessionHandle];
    if (host == null) {
      throw StateError(
        'No session for handle ${request.sessionHandle}; it may have been '
        'disposed while the model was calling "${request.toolName}".',
      );
    }
    final output = await host.runTool(
      request.toolName,
      GeneratedContent(request.argumentsJson),
    );
    return output.toMessage();
  }

  @override
  void onStreamSnapshot(StreamSnapshotMessage snapshot) =>
      _bindings._streams[snapshot.requestId]?.onSnapshot(snapshot);

  @override
  void onStreamDone(int requestId, ResponseMessage response) =>
      _bindings._streams[requestId]?.onDone(response);

  @override
  void onStreamError(int requestId, ErrorMessage error) =>
      _bindings._streams[requestId]?.onError(error);
}
