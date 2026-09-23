import 'package:flutter/foundation.dart';

import 'messages.g.dart';

/// An image to send to the model.
@immutable
sealed class ImageInput {
  const ImageInput();

  /// An image file on disk.
  const factory ImageInput.file(String path) = _FileImage;

  /// Encoded image bytes (PNG, JPEG, HEIC, ...).
  const factory ImageInput.encoded(Uint8List bytes) = _EncodedImage;

  /// Raw BGRA8 pixels.
  const factory ImageInput.pixels({
    required int width,
    required int height,
    required Uint8List bytes,
    int? bytesPerRow,
  }) = _PixelImage;

  /// The Pigeon representation.
  ImageInputMessage toMessage();
}

final class _FileImage extends ImageInput {
  const _FileImage(this.path);

  final String path;

  @override
  ImageInputMessage toMessage() =>
      ImageInputMessage(kind: ImageInputKindMessage.file, path: path);
}

final class _EncodedImage extends ImageInput {
  const _EncodedImage(this.bytes);

  final Uint8List bytes;

  @override
  ImageInputMessage toMessage() =>
      ImageInputMessage(kind: ImageInputKindMessage.encoded, bytes: bytes);
}

final class _PixelImage extends ImageInput {
  const _PixelImage({
    required this.width,
    required this.height,
    required this.bytes,
    this.bytesPerRow,
  });

  final int width;
  final int height;
  final Uint8List bytes;
  final int? bytesPerRow;

  @override
  ImageInputMessage toMessage() => ImageInputMessage(
    kind: ImageInputKindMessage.pixels,
    bytes: bytes,
    width: width,
    height: height,
    bytesPerRow: bytesPerRow,
  );
}

/// An image attached to a prompt.
///
/// Needs a model with the vision capability and iOS 27 / macOS 27. Give the
/// attachment a [label] so the prompt and tools can refer to it ("the receipt
/// image").
@immutable
final class ImageAttachment {
  /// Attaches [image].
  const ImageAttachment(this.image, {this.label});

  /// The image.
  final ImageInput image;

  /// A name the model can refer to.
  final String? label;

  /// The Pigeon representation.
  ImageAttachmentMessage toMessage() =>
      ImageAttachmentMessage(image: image.toMessage(), label: label);
}

/// A prompt: text plus optional image attachments (Apple's `Prompt`).
@immutable
final class Prompt {
  /// A text prompt, with optional [images] attached after the text.
  const Prompt(this.text, {this.images = const []});

  /// The prompt text.
  final String text;

  /// Images attached to the prompt.
  final List<ImageAttachment> images;

  /// The Pigeon representation.
  PromptMessage toMessage() => PromptMessage(
    text: text,
    images: [for (final image in images) image.toMessage()],
  );

  @override
  String toString() =>
      'Prompt("$text"${images.isEmpty ? '' : ', ${images.length} image(s)'})';
}
