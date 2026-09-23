/// Flutter bindings for Apple's Vision framework (iOS 27+ / macOS 27+).
///
/// Run one or more of Vision's still-image requests on an image with
/// [AppleVision.perform] or [AppleVision.analyze]:
///
/// ```dart
/// if (!await AppleVision.isSupported()) return;
/// const text = RecognizeTextRequest();
/// const barcodes = DetectBarcodesRequest();
/// final analysis = await AppleVision.analyze(
///   ImageInput.file('/tmp/label.jpg'),
///   requests: [text, barcodes],
/// );
/// for (final line in analysis.resultOf(text)) {
///   print(line.text);
/// }
/// for (final code in analysis.resultOf(barcodes)) {
///   print('${code.symbology.name}: ${code.payload}');
/// }
/// ```
///
/// Observations use Vision's normalized geometry: the origin is the
/// **lower-left** corner of the image and y grows upwards. Convert it to
/// Flutter's pixel space with [NormalizedRect.toImageCoordinates],
/// [NormalizedPoint.toImageCoordinates] and
/// [NormalizedQuad.toImageCoordinates], which default to an upper-left
/// origin.
library;

export 'src/errors.dart' show AppleVisionErrorCode, AppleVisionException;
export 'src/vision.dart';
