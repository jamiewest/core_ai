import 'dart:async';

import 'messages.g.dart';

/// The platform APIs the core_ai library talks to.
///
/// Replace [instance] in tests to run the Dart layer against fakes:
///
/// ```dart
/// CoreAIBindings.instance = CoreAIBindings(host: FakeHost());
/// ```
class CoreAIBindings {
  /// Creates bindings, defaulting to the real platform channels.
  CoreAIBindings({CoreAIHostApi? host, CoreAIPlatformApi? platform})
    : host = host ?? CoreAIHostApi(),
      platform = platform ?? CoreAIPlatformApi();

  /// The bindings used by every core_ai object.
  static CoreAIBindings instance = CoreAIBindings();

  /// The Core AI API (registered only when Core AI is available).
  final CoreAIHostApi host;

  /// The always-available platform API.
  final CoreAIPlatformApi platform;

  /// Releases native handles whose Dart owners were garbage collected without
  /// being disposed.
  late final Finalizer<int> finalizer = Finalizer<int>(
    (handle) => unawaited(host.release(handle).catchError((Object _) {})),
  );
}
