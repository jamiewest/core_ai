part of 'vision.dart';

/// Core Video pixel formats Vision returns masks and heat maps in.
abstract final class MaskPixelFormat {
  /// `kCVPixelFormatType_OneComponent8`: 8-bit grayscale.
  static const int oneComponent8 = 0x4C303038;

  /// `kCVPixelFormatType_OneComponent16Half`: float16 grayscale.
  static const int oneComponent16Half = 0x4C303068;

  /// `kCVPixelFormatType_OneComponent32Float`: float32 grayscale.
  static const int oneComponent32Float = 0x4C303066;

  /// A readable name for [pixelFormatType], such as `'L00f'`.
  static String describe(int pixelFormatType) {
    final bytes = [
      24,
      16,
      8,
      0,
    ].map((shift) => (pixelFormatType >> shift) & 0xFF);
    if (bytes.every((byte) => byte >= 0x20 && byte < 0x7F)) {
      return String.fromCharCodes(bytes);
    }
    return '0x${pixelFormatType.toRadixString(16).padLeft(8, '0')}';
  }
}

/// A single-channel mask or heat map produced by Vision.
///
/// The bytes are exactly what Vision produced, so the size is the mask's own
/// resolution, which is usually smaller than the analyzed image. Rows are
/// [bytesPerRow] bytes apart, which may be more than one byte per pixel.
@immutable
final class MaskImage {
  /// Creates a mask from raw bytes.
  const MaskImage({
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.pixelFormatType,
    required this.bytes,
  });

  MaskImage._(MaskImageMessage message)
    : width = message.width,
      height = message.height,
      bytesPerRow = message.bytesPerRow,
      pixelFormatType = message.pixelFormatType,
      bytes = message.bytes;

  /// The mask width in pixels.
  final int width;

  /// The mask height in pixels.
  final int height;

  /// The distance in bytes between the starts of consecutive rows.
  final int bytesPerRow;

  /// The Core Video pixel format; see [MaskPixelFormat].
  final int pixelFormatType;

  /// [height] rows of [bytesPerRow] bytes.
  final Uint8List bytes;

  /// The mask size in pixels.
  Size get size => Size(width.toDouble(), height.toDouble());

  /// A readable name for [pixelFormatType], such as `'L00f'`.
  String get pixelFormat => MaskPixelFormat.describe(pixelFormatType);

  /// The value at pixel ([x], [y]), normalized to `0...1`.
  ///
  /// [y] is measured from the **top** row, like every other pixel coordinate
  /// in Flutter. Throws a [RangeError] outside the mask.
  double valueAt(int x, int y) {
    if (x < 0 || x >= width) {
      throw RangeError.range(x, 0, width - 1, 'x');
    }
    if (y < 0 || y >= height) {
      throw RangeError.range(y, 0, height - 1, 'y');
    }
    final data = ByteData.sublistView(bytes);
    final row = y * bytesPerRow;
    switch (pixelFormatType) {
      case MaskPixelFormat.oneComponent32Float:
        return data.getFloat32(row + x * 4, Endian.host);
      case MaskPixelFormat.oneComponent16Half:
        return _float16(data.getUint16(row + x * 2, Endian.host));
      default:
        return data.getUint8(row + x) / 255.0;
    }
  }

  /// The value at a normalized [point], using Vision's lower-left origin.
  double valueAtPoint(NormalizedPoint point) => valueAt(
    (point.x * width).clamp(0, width - 1).floor(),
    ((1 - point.y) * height).clamp(0, height - 1).floor(),
  );

  /// Encodes this mask as an 8-bit grayscale PNG, using Vision's own
  /// ImageIO encoder. Float values are clamped to `0...1`.
  Future<Uint8List> toPng() => guardPlatformCall(
    () => AppleVisionBindings.instance.host.encodeMaskAsPng(
      MaskImageMessage(
        width: width,
        height: height,
        bytesPerRow: bytesPerRow,
        pixelFormatType: pixelFormatType,
        bytes: bytes,
      ),
    ),
  );

  static double _float16(int bits) {
    final sign = (bits & 0x8000) != 0 ? -1.0 : 1.0;
    final exponent = (bits >> 10) & 0x1F;
    final fraction = bits & 0x3FF;
    if (exponent == 0) {
      return sign * fraction * 5.960464477539063e-8;
    }
    if (exponent == 0x1F) {
      return fraction == 0 ? sign * double.infinity : double.nan;
    }
    return sign * (fraction + 1024) * _pow2(exponent - 25);
  }

  static double _pow2(int exponent) {
    var value = 1.0;
    for (var i = 0; i < exponent.abs(); i++) {
      value *= 2;
    }
    return exponent < 0 ? 1 / value : value;
  }

  @override
  String toString() => 'MaskImage(${width}x$height, $pixelFormat)';
}
