import 'dart:typed_data';
import 'dart:ui';

import 'package:meta/meta.dart';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';

part 'geometry.dart';
part 'image_input.dart';
part 'mask.dart';
part 'observations.dart';
part 'requests.dart';

/// Apple's Vision framework: still-image analysis on device.
///
/// ```dart
/// if (!await AppleVision.isSupported()) return;
/// const request = RecognizeTextRequest();
/// final lines = await AppleVision.perform(
///   ImageInput.file('/tmp/receipt.jpg'),
///   request,
/// );
/// for (final line in lines) {
///   print('${line.text} (${line.confidence})');
/// }
/// ```
///
/// All geometry comes back normalized to the unit square with Vision's own
/// convention: the origin is the **lower-left** corner and y grows upwards.
/// Convert it with [NormalizedRect.toImageCoordinates] and friends, which
/// default to Flutter's upper-left origin.
abstract final class AppleVision {
  /// Whether this device can run Vision's still-image requests.
  ///
  /// False below iOS 27 / macOS 27, where the plugin registers only
  /// [platformVersion] and [isSupported].
  static Future<bool> isSupported() => guardPlatformCall(
    () => AppleVisionBindings.instance.platform.isSupported(),
  );

  /// A readable operating-system version, for diagnostics.
  static Future<String> platformVersion() => guardPlatformCall(
    () => AppleVisionBindings.instance.platform.platformVersion(),
  );

  /// The BCP-47 identifiers of the languages text recognition supports.
  static Future<List<String>> supportedRecognitionLanguages({
    RecognitionLevel level = RecognitionLevel.accurate,
  }) => guardPlatformCall(
    () => AppleVisionBindings.instance.host.supportedRecognitionLanguages(
      level._message,
    ),
  );

  /// The barcode symbologies this device can detect.
  static Future<List<BarcodeSymbology>> supportedBarcodeSymbologies() async {
    final values = await guardPlatformCall(
      () => AppleVisionBindings.instance.host.supportedBarcodeSymbologies(),
    );
    return values.map(BarcodeSymbology._from).toList(growable: false);
  }

  /// Every label [ClassifyImageRequest] can return.
  static Future<List<String>> supportedClassificationIdentifiers() =>
      guardPlatformCall(
        () => AppleVisionBindings.instance.host
            .supportedClassificationIdentifiers(),
      );

  /// The pixel size of [image] once [orientation] has been applied.
  static Future<Size> imageSize(
    ImageInput image, {
    ImageOrientation? orientation,
  }) async {
    final size = await guardPlatformCall(
      () => AppleVisionBindings.instance.host.imageSize(
        image._toMessage(),
        orientation?._message,
      ),
    );
    return Size(size.width.toDouble(), size.height.toDouble());
  }

  /// Runs one [request] on [image] and returns its observations.
  ///
  /// Throws an [AppleVisionException] when the request fails.
  static Future<R> perform<R>(
    ImageInput image,
    VisionRequest<R> request, {
    ImageOrientation? orientation,
  }) async {
    final analysis = await analyze(
      image,
      requests: [request],
      orientation: orientation,
    );
    return analysis.resultOf(request);
  }

  /// Decodes [image] once and runs every request in [requests] on it.
  ///
  /// Requests that fail on their own do not fail the whole call; read them
  /// back with [VisionAnalysis.errorFor].
  static Future<VisionAnalysis> analyze(
    ImageInput image, {
    required List<VisionRequest<Object?>> requests,
    ImageOrientation? orientation,
  }) async {
    if (requests.isEmpty) {
      throw ArgumentError.value(requests, 'requests', 'must not be empty');
    }
    final analysis = await guardPlatformCall(
      () => AppleVisionBindings.instance.host.perform(
        image._toMessage(),
        orientation?._message,
        requests.map((request) => request._toMessage()).toList(),
      ),
    );
    return VisionAnalysis._(requests, analysis);
  }
}

/// What one [AppleVision.analyze] call produced.
final class VisionAnalysis {
  VisionAnalysis._(
    List<VisionRequest<Object?>> requests,
    AnalysisMessage message,
  ) : imageSize = Size(
        message.imageSize.width.toDouble(),
        message.imageSize.height.toDouble(),
      ),
      requests = List.unmodifiable(requests) {
    for (var i = 0; i < requests.length; i++) {
      final request = requests[i];
      if (i >= message.results.length) {
        _errors[request] = const AppleVisionException(
          AppleVisionErrorCode.unknown,
          'The platform returned fewer results than requests.',
        );
        continue;
      }
      final result = message.results[i];
      final error = result.error;
      if (error != null) {
        _errors[request] = AppleVisionException(
          AppleVisionErrorCode.fromWire(error.code),
          error.message,
          details: error.details,
        );
      } else {
        _values[request] = request._decode(result);
      }
    }
  }

  /// The size of the analyzed image, in pixels, after its orientation was
  /// applied. Pass it to [NormalizedRect.toImageCoordinates].
  final Size imageSize;

  /// The requests that were run, in order.
  final List<VisionRequest<Object?>> requests;

  final Map<VisionRequest<Object?>, Object?> _values = Map.identity();
  final Map<VisionRequest<Object?>, AppleVisionException> _errors =
      Map.identity();

  /// The observations [request] produced.
  ///
  /// Throws the request's [AppleVisionException] when it failed, and a
  /// [StateError] when [request] was not part of this analysis.
  R resultOf<R>(VisionRequest<R> request) {
    final error = _errors[request];
    if (error != null) throw error;
    if (!_values.containsKey(request)) {
      throw StateError('$request was not part of this analysis.');
    }
    return _values[request] as R;
  }

  /// Why [request] failed, or null when it succeeded.
  AppleVisionException? errorFor(VisionRequest<Object?> request) =>
      _errors[request];

  /// Whether [request] produced observations.
  bool succeeded(VisionRequest<Object?> request) =>
      _values.containsKey(request);

  @override
  String toString() =>
      'VisionAnalysis($imageSize, ${requests.length} requests, '
      '${_errors.length} failed)';
}
