import 'bindings.dart';
import 'errors.dart';
import 'model.dart';
import 'specialization.dart';

/// Device-level Core AI queries and plugin housekeeping.
abstract final class CoreAI {
  /// Whether Core AI is available on this device (iOS 27+ / macOS 27+).
  ///
  /// Every other API throws a [CoreAIException] with
  /// [CoreAIErrorCode.unsupported] when this is false.
  static Future<bool> isSupported() async {
    try {
      return await CoreAIBindings.instance.platform.isSupported();
    } on Object {
      // No plugin registered (for example on a non-Apple platform).
      return false;
    }
  }

  /// The OS name and version, for diagnostics.
  static Future<String> platformVersion() => guardPlatformCall(
    () => CoreAIBindings.instance.platform.platformVersion(),
  );

  /// The Core AI architecture name of this device, which identifies the
  /// matching ahead-of-time compiled model assets.
  static Future<String> deviceArchitectureName() => guardPlatformCall(
    () => CoreAIBindings.instance.host.deviceArchitectureName(),
  );

  /// The compute units available on this device.
  static Future<Set<ComputeUnitKind>> availableComputeUnitKinds() async {
    final kinds = await guardPlatformCall(
      () => CoreAIBindings.instance.host.availableComputeUnitKinds(),
    );
    return {for (final kind in kinds) ComputeUnitKind.fromMessage(kind)};
  }

  /// The on-disk path of a bundled Flutter asset, such as an `.aimodel`
  /// directory listed under `flutter: assets:`.
  static Future<String> assetPath(String assetKey, {String? package}) =>
      resolveAssetPath(assetKey, package: package);

  /// Releases every native object created by this engine: models,
  /// functions, native values and streams.
  ///
  /// Dart objects referring to them become unusable. Useful after a hot
  /// restart, which discards Dart objects without disposing them. Returns how
  /// many objects were released.
  static Future<int> releaseAll() =>
      guardPlatformCall(() => CoreAIBindings.instance.host.releaseAll());

  /// How many native objects are currently alive, for leak checks.
  static Future<int> liveHandleCount() =>
      guardPlatformCall(() => CoreAIBindings.instance.host.liveHandleCount());
}
