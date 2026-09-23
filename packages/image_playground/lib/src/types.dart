import 'dart:typed_data';
import 'package:meta/meta.dart';
import 'messages.g.dart';

/// An image used as a concept or as the source to edit. File and encoded
/// inputs honor EXIF orientation. Pixels use premultiplied BGRA bytes.
@immutable
sealed class ImageInput {
  const ImageInput();

  /// A local image file readable by the application.
  const factory ImageInput.file(String path) = FileImageInput;

  /// Encoded PNG, JPEG, HEIC or another ImageIO-supported format.
  factory ImageInput.encoded(Uint8List bytes) = EncodedImageInput;

  /// Premultiplied BGRA rows; [bytesPerRow] defaults to width * 4.
  factory ImageInput.pixels({
    required int width,
    required int height,
    required Uint8List bgra,
    int? bytesPerRow,
  }) = PixelImageInput;

  /// Converts to a platform message.
  ImageInputMessage toMessage();
}

/// A local file image.
final class FileImageInput extends ImageInput {
  /// Creates a file input.
  const FileImageInput(this.path);

  /// Local path.
  final String path;
  @override
  ImageInputMessage toMessage() =>
      ImageInputMessage(kind: ImageKindMessage.file, path: path);
}

/// An encoded image copied from the caller's data.
final class EncodedImageInput extends ImageInput {
  /// Creates an input with an owned, read-only copy of [bytes].
  EncodedImageInput(Uint8List bytes)
    : bytes = Uint8List.fromList(bytes).asUnmodifiableView();

  /// Encoded image data.
  final Uint8List bytes;
  @override
  ImageInputMessage toMessage() =>
      ImageInputMessage(kind: ImageKindMessage.encoded, bytes: bytes);
}

/// Raw premultiplied BGRA pixels.
final class PixelImageInput extends ImageInput {
  /// Copies [bgra] so later caller mutations cannot change the image.
  PixelImageInput({
    required this.width,
    required this.height,
    required Uint8List bgra,
    this.bytesPerRow,
  }) : bgra = Uint8List.fromList(bgra).asUnmodifiableView();

  /// Pixel width.
  final int width;

  /// Pixel height.
  final int height;

  /// Row stride, or width * 4 when null.
  final int? bytesPerRow;

  /// Read-only pixel data.
  final Uint8List bgra;
  @override
  ImageInputMessage toMessage() => ImageInputMessage(
    kind: ImageKindMessage.pixels,
    width: width,
    height: height,
    bytes: bgra,
    bytesPerRow: bytesPerRow,
  );
}

/// A concept passed to Apple's system image-generation interface.
@immutable
sealed class ImagePlaygroundConcept {
  const ImagePlaygroundConcept();

  /// A short description of an image concept.
  const factory ImagePlaygroundConcept.text(String text) = TextConcept;

  /// Text from which Apple extracts concepts, optionally labelled with [title].
  const factory ImagePlaygroundConcept.extracted(String text, {String? title}) =
      ExtractedConcept;

  /// An image concept.
  const factory ImagePlaygroundConcept.image(ImageInput image) = ImageConcept;

  /// Serialized `PKDrawing.dataRepresentation()` data from PencilKit.
  factory ImagePlaygroundConcept.drawing(Uint8List data) = DrawingConcept;

  /// Converts to a platform message.
  ConceptMessage toMessage();
}

/// A short text concept.
final class TextConcept extends ImagePlaygroundConcept {
  /// Creates a concept.
  const TextConcept(this.text);

  /// Concept description.
  final String text;
  @override
  ConceptMessage toMessage() =>
      ConceptMessage(kind: ConceptKindMessage.text, text: text);
}

/// A longer text from which to extract concepts.
final class ExtractedConcept extends ImagePlaygroundConcept {
  /// Creates an extracted-text concept.
  const ExtractedConcept(this.text, {this.title});

  /// Source text.
  final String text;

  /// Optional label.
  final String? title;
  @override
  ConceptMessage toMessage() => ConceptMessage(
    kind: ConceptKindMessage.extracted,
    text: text,
    title: title,
  );
}

/// An image as a concept, separate from the source image being edited.
final class ImageConcept extends ImagePlaygroundConcept {
  /// Creates an image concept.
  const ImageConcept(this.image);

  /// The image.
  final ImageInput image;
  @override
  ConceptMessage toMessage() =>
      ConceptMessage(kind: ConceptKindMessage.image, image: image.toMessage());
}

/// A serialized PencilKit drawing concept.
final class DrawingConcept extends ImagePlaygroundConcept {
  /// Copies the caller's serialized drawing.
  DrawingConcept(Uint8List data)
    : data = Uint8List.fromList(data).asUnmodifiableView();

  /// Read-only PencilKit data.
  final Uint8List data;
  @override
  ConceptMessage toMessage() =>
      ConceptMessage(kind: ConceptKindMessage.drawing, drawing: data);
}

/// Styles supported by the installed framework. External-provider styles may
/// use a service chosen by the user in Apple's interface.
enum ImagePlaygroundStyle {
  /// Animated illustration style.
  animation,

  /// Illustration style.
  illustration,

  /// Sketch style.
  sketch,

  /// Adaptive-image-glyph creation.
  emoji,

  /// External generation provider (OS 26+).
  externalProvider,

  /// Any available style (OS 27+).
  any,
}

/// Whether people/personalization features are enabled.
enum Personalization {
  /// Let Apple decide.
  automatic,

  /// Enable personalization.
  enabled,

  /// Disable personalization.
  disabled,
}

/// How much results vary for the same input (OS 26.4+).
enum CreationVariety {
  /// Let Apple choose.
  automatic,

  /// More variation.
  high,

  /// Less variation.
  low,
}

/// How the source image influences generation (OS 27+).
enum CreationStrategy {
  /// Let Apple choose.
  automatic,

  /// Preserve/edit the existing content.
  editExisting,

  /// Use the source as inspiration for a new image.
  generateNew,
}

/// Requested dimensions. Apple chooses the closest supported size (OS 27+).
@immutable
final class ImageSize {
  /// Creates a size in pixels.
  const ImageSize(this.width, this.height);

  /// Width in pixels.
  final double width;

  /// Height in pixels.
  final double height;
}

/// Options mapped to `ImagePlaygroundOptions`, with older personalization
/// policy support. Explicit unsupported options fail instead of being ignored.
@immutable
final class ImagePlaygroundOptions {
  /// Null fields preserve Apple's defaults.
  const ImagePlaygroundOptions({
    this.personalization,
    this.variety,
    this.strategy,
    this.size,
  });

  /// Personalization (iOS 18.4 / macOS 15.4+).
  final Personalization? personalization;

  /// Creation variety (OS 26.4+).
  final CreationVariety? variety;

  /// Creation strategy (OS 27+).
  final CreationStrategy? strategy;

  /// Closest supported output size (OS 27+).
  final ImageSize? size;

  /// Converts to a platform message.
  OptionsMessage toMessage() => OptionsMessage(
    personalization: personalization == null
        ? null
        : PersonalizationMessage.values[personalization!.index],
    variety: variety == null ? null : VarietyMessage.values[variety!.index],
    strategy: strategy == null ? null : StrategyMessage.values[strategy!.index],
    width: size?.width,
    height: size?.height,
  );
}

/// Platform support is separate from current device/model availability.
@immutable
final class ImagePlaygroundCapabilities {
  /// Converts a platform response.
  ImagePlaygroundCapabilities.fromMessage(CapabilitiesMessage message)
    : isSupported = message.isSupported,
      isAvailable = message.isAvailable,
      supportsStyles = message.supportsStyles,
      supportsOptions = message.supportsOptions,
      supportsVersion27Options = message.supportsVersion27Options,
      styles = List.unmodifiable(
        message.styles.map((style) => ImagePlaygroundStyle.values[style.index]),
      );

  /// Whether the framework API exists on this OS.
  final bool isSupported;

  /// Whether Apple's interface is currently available on this device.
  final bool isAvailable;

  /// Whether style selection and personalization are supported.
  final bool supportsStyles;

  /// Whether creation-variety options are supported.
  final bool supportsOptions;

  /// Whether creation strategy and requested size are supported.
  final bool supportsVersion27Options;

  /// Known styles advertised by the framework, not a model-readiness guarantee.
  final List<ImagePlaygroundStyle> styles;
}

/// Snapshot of the actual native controller configuration.
@immutable
final class ImagePlaygroundSessionInfo {
  /// Converts platform information.
  ImagePlaygroundSessionInfo.fromMessage(SessionInfoMessage message)
    : conceptCount = message.conceptCount,
      hasSourceImage = message.hasSourceImage,
      allowedStyles = List.unmodifiable(
        message.allowedStyles.map((s) => ImagePlaygroundStyle.values[s.index]),
      ),
      selectedStyle = message.selectedStyle == null
          ? null
          : ImagePlaygroundStyle.values[message.selectedStyle!.index],
      isPresenting = message.isPresenting;

  /// Number of configured concepts.
  final int conceptCount;

  /// Whether a source image is set.
  final bool hasSourceImage;

  /// Controller's allowed styles.
  final List<ImagePlaygroundStyle> allowedStyles;

  /// Controller's selected style, when style APIs exist.
  final ImagePlaygroundStyle? selectedStyle;

  /// Whether the system sheet is open.
  final bool isPresenting;
}

/// Generated content copied out of Apple's temporary output before dismissal.
@immutable
final class ImagePlaygroundResult {
  /// Converts generated content, taking a read-only copy of its bytes.
  ImagePlaygroundResult.fromMessage(ResultMessage message)
    : bytes = Uint8List.fromList(message.bytes).asUnmodifiableView(),
      typeIdentifier = message.typeIdentifier,
      width = message.width,
      height = message.height,
      contentIdentifier = message.contentIdentifier,
      contentDescription = message.contentDescription;

  /// PNG for ordinary images; original adaptive-glyph data for emoji output.
  final Uint8List bytes;

  /// Uniform type identifier, e.g. `public.png` or `com.apple.emoji.sticker`.
  final String typeIdentifier;

  /// Output width in pixels.
  final int width;

  /// Output height in pixels.
  final int height;

  /// Adaptive glyph identifier, or null for an ordinary image.
  final String? contentIdentifier;

  /// Adaptive glyph accessibility description, when present.
  final String? contentDescription;

  /// Whether the result contains adaptive-glyph data.
  bool get isAdaptiveImageGlyph => contentIdentifier != null;
}
