import 'messages.g.dart';

/// The platform APIs the apple_vision_native library talks to.
///
/// Replace [instance] in tests to run the Dart layer against fakes:
///
/// ```dart
/// AppleVisionBindings.instance = AppleVisionBindings(host: FakeHost());
/// ```
class AppleVisionBindings {
  /// Creates bindings, defaulting to the real platform channels.
  AppleVisionBindings({
    AppleVisionHostApi? host,
    AppleVisionPlatformApi? platform,
  }) : host = host ?? AppleVisionHostApi(),
       platform = platform ?? AppleVisionPlatformApi();

  /// The bindings used by every apple_vision_native call.
  static AppleVisionBindings instance = AppleVisionBindings();

  /// The Vision API (registered only when Vision is available).
  final AppleVisionHostApi host;

  /// The always-available platform API.
  final AppleVisionPlatformApi platform;
}
