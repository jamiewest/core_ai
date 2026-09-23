/// Test support for code that uses core_ai.
///
/// Replace [CoreAIBindings.instance] with bindings backed by fake
/// [CoreAIHostApi] and [CoreAIPlatformApi] implementations to exercise the
/// Dart API without a device.
library;

export 'src/bindings.dart';
export 'src/messages.g.dart';
