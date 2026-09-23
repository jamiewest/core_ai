part of 'vision.dart';

/// How an image is rotated and mirrored relative to how it was captured.
///
/// Mirrors `CGImagePropertyOrientation`. Vision reports its results in the
/// oriented image's coordinate space.
enum ImageOrientation {
  /// The image is already the right way up.
  up(ImageOrientationMessage.up),

  /// Mirrored horizontally.
  upMirrored(ImageOrientationMessage.upMirrored),

  /// Rotated 180 degrees.
  down(ImageOrientationMessage.down),

  /// Rotated 180 degrees and mirrored horizontally.
  downMirrored(ImageOrientationMessage.downMirrored),

  /// Rotated 90 degrees clockwise and mirrored horizontally.
  leftMirrored(ImageOrientationMessage.leftMirrored),

  /// Rotated 90 degrees clockwise.
  right(ImageOrientationMessage.right),

  /// Rotated 90 degrees counter-clockwise and mirrored horizontally.
  rightMirrored(ImageOrientationMessage.rightMirrored),

  /// Rotated 90 degrees counter-clockwise.
  left(ImageOrientationMessage.left);

  const ImageOrientation(this._message);

  final ImageOrientationMessage _message;
}

/// An image to analyze.
///
/// Use [ImageInput.file] for an image on disk, [ImageInput.asset] for a
/// bundled Flutter asset, [ImageInput.encoded] for PNG/JPEG/HEIF bytes and
/// [ImageInput.pixels] for raw BGRA8888 pixels, for example a camera frame.
@immutable
sealed class ImageInput {
  const ImageInput();

  /// An image file at [path].
  const factory ImageInput.file(String path) = FileImageInput;

  /// Encoded image [bytes], in any format ImageIO can read.
  const factory ImageInput.encoded(Uint8List bytes) = EncodedImageInput;

  /// Raw 8-bit BGRA pixels, [height] rows of [bytesPerRow] bytes.
  ///
  /// [bytesPerRow] defaults to `width * 4`.
  const factory ImageInput.pixels({
    required int width,
    required int height,
    required Uint8List bytes,
    int? bytesPerRow,
  }) = PixelsImageInput;

  /// Resolves a Flutter asset to a file on disk.
  ///
  /// Throws an [AppleVisionException] with
  /// [AppleVisionErrorCode.notFound] when the asset is not bundled.
  static Future<ImageInput> asset(String key, {String? package}) async {
    final path = await guardPlatformCall(
      () => AppleVisionBindings.instance.platform.assetPath(key, package),
    );
    if (path == null) {
      throw AppleVisionException(
        AppleVisionErrorCode.notFound,
        "The asset '$key' is not bundled with this app.",
      );
    }
    return ImageInput.file(path);
  }

  ImageInputMessage _toMessage();
}

/// An image read from a file.
final class FileImageInput extends ImageInput {
  /// Creates an input that reads [path].
  const FileImageInput(this.path);

  /// The absolute path of the image file.
  final String path;

  @override
  ImageInputMessage _toMessage() =>
      ImageInputMessage(kind: ImageInputKindMessage.file, path: path);

  @override
  String toString() => 'ImageInput.file($path)';
}

/// An image held in memory in an encoded format such as PNG or JPEG.
final class EncodedImageInput extends ImageInput {
  /// Creates an input from encoded [bytes].
  const EncodedImageInput(this.bytes);

  /// The encoded image.
  final Uint8List bytes;

  @override
  ImageInputMessage _toMessage() =>
      ImageInputMessage(kind: ImageInputKindMessage.encoded, bytes: bytes);

  @override
  String toString() => 'ImageInput.encoded(${bytes.length} bytes)';
}

/// An image held in memory as raw 8-bit BGRA pixels.
final class PixelsImageInput extends ImageInput {
  /// Creates an input from raw pixels.
  const PixelsImageInput({
    required this.width,
    required this.height,
    required this.bytes,
    this.bytesPerRow,
  });

  /// The width in pixels.
  final int width;

  /// The height in pixels.
  final int height;

  /// [height] rows of [bytesPerRow] bytes, blue first.
  final Uint8List bytes;

  /// The distance in bytes between the starts of consecutive rows.
  ///
  /// Defaults to `width * 4`.
  final int? bytesPerRow;

  @override
  ImageInputMessage _toMessage() => ImageInputMessage(
    kind: ImageInputKindMessage.pixels,
    bytes: bytes,
    width: width,
    height: height,
    bytesPerRow: bytesPerRow,
  );

  @override
  String toString() => 'ImageInput.pixels(${width}x$height)';
}
