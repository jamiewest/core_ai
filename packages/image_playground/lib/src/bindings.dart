import 'messages.g.dart';

/// Injectable platform APIs for unit and widget tests.
class ImagePlaygroundBindings {
  /// Creates bindings, using the real platform channels by default.
  ImagePlaygroundBindings({
    ImagePlaygroundPlatformApi? platform,
    ImagePlaygroundHostApi? host,
  }) : platform = platform ?? ImagePlaygroundPlatformApi(),
       host = host ?? ImagePlaygroundHostApi();

  /// Bindings used when new sessions are created.
  static ImagePlaygroundBindings instance = ImagePlaygroundBindings();

  /// Always-registered support queries.
  final ImagePlaygroundPlatformApi platform;

  /// Framework API, registered on supported OS versions.
  final ImagePlaygroundHostApi host;

  /// Best-effort backstop for sessions not explicitly disposed.
  late final Finalizer<int> finalizer = Finalizer((handle) {
    host.release(handle).ignore();
  });
}
