part of 'vision.dart';

/// Where the origin of an image's pixel coordinate space lies.
///
/// Vision itself always reports [lowerLeft]. Flutter's `Rect`, `Offset` and
/// `Canvas` all use [upperLeft], which is why it is the default when
/// converting to pixels.
enum CoordinateOrigin {
  /// The origin is the top-left corner and y grows downwards, as in Flutter.
  upperLeft,

  /// The origin is the bottom-left corner and y grows upwards, as in Vision
  /// and Core Graphics.
  lowerLeft,
}

/// A point in Vision's normalized coordinate space.
///
/// Both coordinates run from 0 to 1. The origin is the **lower-left** corner
/// of the image and y grows upwards; use [toImageCoordinates] to get pixels.
@immutable
final class NormalizedPoint {
  /// Creates a normalized point.
  const NormalizedPoint(this.x, this.y);

  NormalizedPoint._(NormalizedPointMessage message)
    : x = message.x,
      y = message.y;

  /// The horizontal position, 0 at the left edge and 1 at the right edge.
  final double x;

  /// The vertical position, 0 at the **bottom** edge and 1 at the top edge.
  final double y;

  /// This point in pixels within an image of [imageSize].
  Offset toImageCoordinates(
    Size imageSize, {
    CoordinateOrigin origin = CoordinateOrigin.upperLeft,
  }) => Offset(
    x * imageSize.width,
    (origin == CoordinateOrigin.upperLeft ? 1 - y : y) * imageSize.height,
  );

  /// The same point measured from the opposite vertical edge.
  NormalizedPoint get verticallyFlipped => NormalizedPoint(x, 1 - y);

  @override
  bool operator ==(Object other) =>
      other is NormalizedPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'NormalizedPoint($x, $y)';
}

/// A rectangle in Vision's normalized coordinate space.
///
/// The origin is the **lower-left** corner of the image and y grows upwards,
/// so [y] is the distance from the bottom edge to the bottom of the rectangle.
@immutable
final class NormalizedRect {
  /// Creates a normalized rectangle.
  const NormalizedRect({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  NormalizedRect._(NormalizedRectMessage message)
    : x = message.x,
      y = message.y,
      width = message.width,
      height = message.height;

  /// The whole image.
  static const NormalizedRect full = NormalizedRect(
    x: 0,
    y: 0,
    width: 1,
    height: 1,
  );

  /// The distance from the left edge to the left side of the rectangle.
  final double x;

  /// The distance from the **bottom** edge to the bottom of the rectangle.
  final double y;

  /// The width, as a fraction of the image width.
  final double width;

  /// The height, as a fraction of the image height.
  final double height;

  /// The lower-left corner.
  NormalizedPoint get origin => NormalizedPoint(x, y);

  /// The distance from the bottom edge to the top of the rectangle.
  double get maxY => y + height;

  /// The distance from the left edge to the right side of the rectangle.
  double get maxX => x + width;

  /// This rectangle in pixels within an image of [imageSize].
  Rect toImageCoordinates(
    Size imageSize, {
    CoordinateOrigin origin = CoordinateOrigin.upperLeft,
  }) => Rect.fromLTWH(
    x * imageSize.width,
    (origin == CoordinateOrigin.upperLeft ? 1 - maxY : y) * imageSize.height,
    width * imageSize.width,
    height * imageSize.height,
  );

  /// The same rectangle measured from the opposite vertical edge.
  NormalizedRect get verticallyFlipped =>
      NormalizedRect(x: x, y: 1 - maxY, width: width, height: height);

  NormalizedRectMessage _toMessage() =>
      NormalizedRectMessage(x: x, y: y, width: width, height: height);

  @override
  bool operator ==(Object other) =>
      other is NormalizedRect &&
      other.x == x &&
      other.y == y &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(x, y, width, height);

  @override
  String toString() =>
      'NormalizedRect(x: $x, y: $y, width: $width, height: $height)';
}

/// Four corners of a detected shape, plus their bounding box.
///
/// The corner names are in Vision's lower-left-origin space, so [topLeft] is
/// the corner nearest the top-left of the image as a person sees it.
@immutable
final class NormalizedQuad {
  /// Creates a quadrilateral.
  const NormalizedQuad({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
    required this.boundingBox,
    required this.confidence,
  });

  NormalizedQuad._(QuadrilateralMessage message)
    : topLeft = NormalizedPoint._(message.topLeft),
      topRight = NormalizedPoint._(message.topRight),
      bottomRight = NormalizedPoint._(message.bottomRight),
      bottomLeft = NormalizedPoint._(message.bottomLeft),
      boundingBox = NormalizedRect._(message.boundingBox),
      confidence = message.confidence;

  /// The upper-left corner.
  final NormalizedPoint topLeft;

  /// The upper-right corner.
  final NormalizedPoint topRight;

  /// The lower-right corner.
  final NormalizedPoint bottomRight;

  /// The lower-left corner.
  final NormalizedPoint bottomLeft;

  /// The axis-aligned box that contains all four corners.
  final NormalizedRect boundingBox;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  /// The four corners in pixels, clockwise from the top-left.
  List<Offset> toImageCoordinates(
    Size imageSize, {
    CoordinateOrigin origin = CoordinateOrigin.upperLeft,
  }) => [
    topLeft.toImageCoordinates(imageSize, origin: origin),
    topRight.toImageCoordinates(imageSize, origin: origin),
    bottomRight.toImageCoordinates(imageSize, origin: origin),
    bottomLeft.toImageCoordinates(imageSize, origin: origin),
  ];

  @override
  String toString() => 'NormalizedQuad($boundingBox, confidence: $confidence)';
}
