import 'dart:typed_data';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'model.dart';
import 'types.dart';
import 'values.dart';

/// Device-level Core ML queries and plugin housekeeping.
abstract final class CoreML {
  /// Whether core_ml works on this device (iOS 18+ / macOS 15+).
  ///
  /// Every other API throws a [CoreMLException] with
  /// [CoreMLErrorCode.unsupported] when this is false.
  static Future<bool> isSupported() async {
    try {
      return await CoreMLBindings.instance.platform.isSupported();
    } on Object {
      // No plugin registered (for example on a non-Apple platform).
      return false;
    }
  }

  /// The OS name and version, for diagnostics.
  static Future<String> platformVersion() => guardPlatformCall(
    () => CoreMLBindings.instance.platform.platformVersion(),
  );

  /// The compute devices Core ML can use for predictions
  /// (`MLModel.availableComputeDevices`).
  static Future<List<MLComputeDevice>> availableComputeDevices() async {
    final devices = await guardPlatformCall(
      () => CoreMLBindings.instance.host.availableComputeDevices(),
    );
    return [for (final device in devices) MLComputeDevice.fromMessage(device)];
  }

  /// Every compute device on this machine, including ones reserved for
  /// other frameworks (`MLComputeDevice.allComputeDevices`).
  static Future<List<MLComputeDevice>> allComputeDevices() async {
    final devices = await guardPlatformCall(
      () => CoreMLBindings.instance.host.allComputeDevices(),
    );
    return [for (final device in devices) MLComputeDevice.fromMessage(device)];
  }

  /// The on-disk path of a bundled Flutter asset, such as a `.mlpackage`
  /// directory listed under `flutter: assets:`.
  static Future<String> assetPath(String assetKey, {String? package}) =>
      resolveAssetPath(assetKey, package: package);

  /// Encodes an image output as PNG or JPEG, for example to show with
  /// `Image.memory`. [quality] (0 to 1) applies to JPEG.
  static Future<Uint8List> encodeImage(
    PixelBuffer image, {
    MLImageEncoding encoding = MLImageEncoding.png,
    double quality = 0.9,
  }) => guardPlatformCall(
    () => CoreMLBindings.instance.host.encodeImage(
      image.toMessage(),
      ImageEncodingMessage.values[encoding.index],
      quality,
    ),
  );

  /// Releases every native model and state created by this engine.
  ///
  /// Dart objects referring to them become unusable. Useful after a hot
  /// restart, which discards Dart objects without disposing them. Returns how
  /// many objects were released.
  static Future<int> releaseAll() =>
      guardPlatformCall(() => CoreMLBindings.instance.host.releaseAll());

  /// How many native objects are currently alive, for leak checks.
  static Future<int> liveHandleCount() =>
      guardPlatformCall(() => CoreMLBindings.instance.host.liveHandleCount());
}
