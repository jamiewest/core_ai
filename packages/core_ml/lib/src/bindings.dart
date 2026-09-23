import 'dart:async';

import 'messages.g.dart';

/// The platform APIs the core_ml library talks to.
///
/// Replace [instance] in tests to run the Dart layer against fakes:
///
/// ```dart
/// CoreMLBindings.instance = CoreMLBindings(host: FakeHost());
/// ```
class CoreMLBindings {
  /// Creates bindings, defaulting to the real platform channels.
  CoreMLBindings({CoreMLHostApi? host, CoreMLPlatformApi? platform})
    : host = host ?? CoreMLHostApi(),
      platform = platform ?? CoreMLPlatformApi();

  /// The bindings used by every core_ml object.
  static CoreMLBindings instance = CoreMLBindings();

  /// The Core ML API (registered only on iOS 18+ / macOS 15+).
  final CoreMLHostApi host;

  /// The always-available platform API.
  final CoreMLPlatformApi platform;

  /// Releases native handles whose Dart owners were garbage collected without
  /// being disposed.
  late final Finalizer<int> finalizer = Finalizer<int>(
    (handle) => unawaited(host.release(handle).catchError((Object _) {})),
  );
}
