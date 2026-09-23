part of 'values.dart';

/// Core Video pixel format types (`kCVPixelFormatType_*`) commonly used by
/// image models. Any other four-character code works too; see [fourCC].
abstract final class PixelFormat {
  /// `kCVPixelFormatType_32BGRA`: 8-bit B, G, R, A.
  static const int bgra32 = 0x42475241;

  /// `kCVPixelFormatType_32ARGB`: 8-bit A, R, G, B.
  static const int argb32 = 0x00000020;

  /// `kCVPixelFormatType_32RGBA`: 8-bit R, G, B, A.
  static const int rgba32 = 0x52474241;

  /// `kCVPixelFormatType_24RGB`: 8-bit R, G, B.
  static const int rgb24 = 0x00000018;

  /// `kCVPixelFormatType_OneComponent8`: 8-bit grayscale.
  static const int oneComponent8 = 0x4C303038;

  /// `kCVPixelFormatType_OneComponent16Half`: float16 grayscale.
  static const int oneComponent16Half = 0x4C303068;

  /// `kCVPixelFormatType_OneComponent32Float`: float32 grayscale.
  static const int oneComponent32Float = 0x4C303066;

  /// `kCVPixelFormatType_64RGBAHalf`: float16 R, G, B, A.
  static const int rgba64Half = 0x52476841;

  /// `kCVPixelFormatType_128RGBAFloat`: float32 R, G, B, A.
  static const int rgba128Float = 0x52476641;

  /// `kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`: NV12, video range.
  static const int yuv420BiPlanarVideoRange = 0x34323076;

  /// `kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`: NV12, full range.
  static const int yuv420BiPlanarFullRange = 0x34323066;

  /// The pixel format for a four-character [code] such as `'BGRA'`.
  static int fourCC(String code) {
    if (code.length != 4) {
      throw ArgumentError.value(code, 'code', 'must be four characters');
    }
    return code.codeUnits.fold(0, (value, unit) => (value << 8) | unit);
  }

  /// A readable name for [pixelFormatType], such as `'BGRA'`.
  static String describe(int pixelFormatType) {
    final bytes = [24, 16, 8, 0].map((s) => (pixelFormatType >> s) & 0xFF);
    if (bytes.every((b) => b >= 0x20 && b < 0x7F)) {
      return String.fromCharCodes(bytes);
    }
    return '0x${pixelFormatType.toRadixString(16).padLeft(8, '0')}';
  }
}

/// One plane of a [PixelBuffer]. Rows are [bytesPerRow] apart, which may be
/// more than the pixel data itself because of padding.
@immutable
final class PixelBufferPlane {
  /// Creates a plane.
  const PixelBufferPlane({
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.bytes,
  });

  /// Plane width in pixels.
  final int width;

  /// Plane height in rows.
  final int height;

  /// The distance in bytes between the starts of consecutive rows.
  final int bytesPerRow;

  /// The plane's bytes: [height] rows of [bytesPerRow] bytes.
  final Uint8List bytes;
}

/// An image held in Dart memory, mirroring a `CVPixelBuffer`.
///
/// Use it for model inputs and outputs whose descriptor is an
/// [ImageDescriptor]. To feed an encoded image (PNG, JPEG, HEIC, ...) without
/// converting it in Dart, use [NativeValue.fromEncodedImage], which decodes,
/// resizes and converts on the native side.
@immutable
final class PixelBuffer implements InferenceValue {
  /// Creates a buffer from explicit [planes] (one plane for packed formats).
  PixelBuffer({
    required this.width,
    required this.height,
    required this.pixelFormatType,
    required List<PixelBufferPlane> planes,
  }) : planes = List.unmodifiable(planes);

  /// Creates a single-plane (packed) buffer. [bytesPerRow] defaults to the
  /// tightest row size that fits [bytes].
  factory PixelBuffer.packed({
    required int width,
    required int height,
    required int pixelFormatType,
    required Uint8List bytes,
    int? bytesPerRow,
  }) {
    final rowBytes = bytesPerRow ?? bytes.length ~/ math.max(height, 1);
    if (rowBytes * height > bytes.length) {
      throw ArgumentError(
        '$height rows of $rowBytes bytes do not fit in ${bytes.length} bytes.',
      );
    }
    return PixelBuffer(
      width: width,
      height: height,
      pixelFormatType: pixelFormatType,
      planes: [
        PixelBufferPlane(
          width: width,
          height: height,
          bytesPerRow: rowBytes,
          bytes: bytes,
        ),
      ],
    );
  }

  /// Converts tightly packed RGBA8888 pixels (as produced by
  /// `dart:ui` `Image.toByteData(format: ImageByteFormat.rawRgba)`) into
  /// [pixelFormatType]: [PixelFormat.bgra32], [PixelFormat.argb32],
  /// [PixelFormat.rgba32], [PixelFormat.rgb24] or [PixelFormat.oneComponent8]
  /// (BT.601 luma).
  factory PixelBuffer.fromRgba8888(
    Uint8List rgba, {
    required int width,
    required int height,
    int pixelFormatType = PixelFormat.bgra32,
  }) {
    if (rgba.length < width * height * 4) {
      throw ArgumentError('Expected ${width * height * 4} RGBA bytes.');
    }
    final order = _channelOrder(pixelFormatType);
    final pixels = width * height;
    final out = Uint8List(pixels * order.length);
    for (var p = 0; p < pixels; p++) {
      final r = rgba[p * 4], g = rgba[p * 4 + 1], b = rgba[p * 4 + 2];
      final a = rgba[p * 4 + 3];
      for (var c = 0; c < order.length; c++) {
        out[p * order.length + c] = switch (order[c]) {
          'r' => r,
          'g' => g,
          'b' => b,
          'a' => a,
          _ => (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255),
        };
      }
    }
    return PixelBuffer.packed(
      width: width,
      height: height,
      pixelFormatType: pixelFormatType,
      bytes: out,
      bytesPerRow: width * order.length,
    );
  }

  /// Converts from the Pigeon representation.
  factory PixelBuffer.fromMessage(PixelBufferMessage message) => PixelBuffer(
    width: message.width,
    height: message.height,
    pixelFormatType: message.pixelFormatType,
    planes: [
      for (final plane in message.planes)
        PixelBufferPlane(
          width: plane.width,
          height: plane.height,
          bytesPerRow: plane.bytesPerRow,
          bytes: plane.data,
        ),
    ],
  );

  /// Width in pixels.
  final int width;

  /// Height in pixels.
  final int height;

  /// The Core Video pixel format (see [PixelFormat]).
  final int pixelFormatType;

  /// The image planes; packed formats have one.
  final List<PixelBufferPlane> planes;

  /// Converts to tightly packed RGBA8888, for example to display with
  /// `dart:ui` `decodeImageFromPixels`. Supports the formats accepted by
  /// [PixelBuffer.fromRgba8888].
  Uint8List toRgba8888() {
    final order = _channelOrder(pixelFormatType);
    final plane = planes.single;
    final out = Uint8List(width * height * 4);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final source = y * plane.bytesPerRow + x * order.length;
        final target = (y * width + x) * 4;
        out[target + 3] = 255;
        for (var c = 0; c < order.length; c++) {
          final value = plane.bytes[source + c];
          switch (order[c]) {
            case 'r':
              out[target] = value;
            case 'g':
              out[target + 1] = value;
            case 'b':
              out[target + 2] = value;
            case 'a':
              out[target + 3] = value;
            default:
              out[target] = out[target + 1] = out[target + 2] = value;
          }
        }
      }
    }
    return out;
  }

  /// The Pigeon representation.
  PixelBufferMessage toMessage() => PixelBufferMessage(
    width: width,
    height: height,
    pixelFormatType: pixelFormatType,
    planes: [
      for (final plane in planes)
        PixelBufferPlaneMessage(
          width: plane.width,
          height: plane.height,
          bytesPerRow: plane.bytesPerRow,
          data: plane.bytes,
        ),
    ],
  );

  static List<String> _channelOrder(int pixelFormatType) =>
      switch (pixelFormatType) {
        PixelFormat.bgra32 => const ['b', 'g', 'r', 'a'],
        PixelFormat.argb32 => const ['a', 'r', 'g', 'b'],
        PixelFormat.rgba32 => const ['r', 'g', 'b', 'a'],
        PixelFormat.rgb24 => const ['r', 'g', 'b'],
        PixelFormat.oneComponent8 => const ['y'],
        _ => throw UnsupportedError(
          'RGBA8888 conversion does not support pixel format '
          '${PixelFormat.describe(pixelFormatType)}.',
        ),
      };

  @override
  String toString() =>
      'PixelBuffer(${width}x$height ${PixelFormat.describe(pixelFormatType)})';
}
