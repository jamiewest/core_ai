/// Test support for code that uses foundation_models.
///
/// Replace [FoundationModelsBindings.instance] with bindings backed by fake
/// host APIs to exercise the Dart layer without a device.
library;

export 'src/bindings.dart';
export 'src/messages.g.dart';
