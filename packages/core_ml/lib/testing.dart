/// Test support for code that uses core_ml.
///
/// Replace [CoreMLBindings.instance] with bindings backed by fake
/// [CoreMLHostApi] and [CoreMLPlatformApi] implementations to exercise the
/// Dart API without a device.
library;

export 'src/bindings.dart';
export 'src/messages.g.dart';
