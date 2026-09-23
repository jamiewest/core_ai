/// Test support for code that uses apple_vision.
///
/// Replace [AppleVisionBindings.instance] with bindings backed by fake
/// [AppleVisionHostApi] and [AppleVisionPlatformApi] implementations to
/// exercise the Dart API without a device.
library;

export 'src/bindings.dart';
export 'src/messages.g.dart';
