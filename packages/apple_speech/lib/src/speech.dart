import 'bindings.dart';
import 'common.dart';
import 'errors.dart';

/// Platform support, microphone authorization and request cleanup.
abstract final class Speech {
  /// Whether the Speech plugin is available on this platform.
  static Future<bool> isSupported() =>
      _supported(() => SpeechBindings.instance.platform.isSupported());

  /// Whether this OS supports SpeechAnalyzer (26 or later).
  static Future<bool> isAnalyzerSupported() =>
      _supported(() => SpeechBindings.instance.platform.isAnalyzerSupported());

  /// Whether media-asset input and version 27 analyzer options are available.
  static Future<bool> isVersion27Supported() =>
      _supported(() => SpeechBindings.instance.platform.isVersion27Supported());

  /// Queries microphone authorization without prompting.
  static Future<AuthorizationStatus> microphoneAuthorizationStatus() async =>
      AuthorizationStatus.fromMessage(
        await guardPlatformCall(
          () => SpeechBindings.instance.host.microphoneAuthorizationStatus(),
        ),
      );

  /// Requests microphone access. Call from an explicit user action after
  /// configuring the usage description and macOS audio-input entitlement.
  static Future<AuthorizationStatus> requestMicrophoneAuthorization() async =>
      AuthorizationStatus.fromMessage(
        await guardPlatformCall(
          () => SpeechBindings.instance.host.requestMicrophoneAuthorization(),
        ),
      );

  /// Number of requests currently registered on the native side.
  static Future<int> activeRequestCount() => guardPlatformCall(
    () => SpeechBindings.instance.host.activeRequestCount(),
  );

  /// Cancels current Dart requests (including those starting up), then native
  /// requests and downloads. Returns the number of Dart requests selected.
  /// Avoid starting new work concurrently with this global cleanup.
  static Future<int> cancelAll() async {
    final bindings = SpeechBindings.instance;
    final requests = bindings.activeRequests;
    await Future.wait(requests.map((request) => request.cancel()));
    await guardPlatformCall(() => bindings.host.cancelAll());
    return requests.length;
  }
}

Future<bool> _supported(Future<bool> Function() query) async {
  try {
    return await query();
  } on Object {
    return false;
  }
}
