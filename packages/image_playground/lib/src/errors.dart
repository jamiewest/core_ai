import 'package:flutter/services.dart';

/// Stable categories reported by the Image Playground bridge.
enum ImagePlaygroundErrorCode {
  /// The framework or requested option is absent on this OS.
  unsupported('unsupported'),

  /// Hardware, settings, or model availability prevents presentation.
  unavailable('unavailable'),

  /// The input configuration is invalid.
  invalidArgument('invalid_argument'),

  /// A native session was released or does not exist.
  invalidHandle('invalid_handle'),

  /// A one-use session was already presented or cancelled.
  invalidState('invalid_state'),

  /// Another controller is already presented.
  busy('busy'),

  /// The Flutter engine has no attached presentation window.
  noPresenter('no_presenter'),

  /// An input image file does not exist.
  notFound('not_found'),

  /// Image/drawing decoding, file access or result encoding failed.
  imageError('image_error'),

  /// An error introduced by a newer plugin version.
  unknown('unknown');

  const ImagePlaygroundErrorCode(this.wireName);

  /// Code carried by the platform channel.
  final String wireName;
}

/// A typed failure from the plugin. User cancellation returns null instead.
class ImagePlaygroundException implements Exception {
  /// Creates an exception.
  const ImagePlaygroundException(this.code, this.message, {this.details});

  /// Converts a platform exception.
  factory ImagePlaygroundException.fromPlatformException(
    PlatformException error,
  ) => ImagePlaygroundException(
    error.code == 'channel-error'
        ? ImagePlaygroundErrorCode.unsupported
        : ImagePlaygroundErrorCode.values.firstWhere(
            (code) => code.wireName == error.code,
            orElse: () => ImagePlaygroundErrorCode.unknown,
          ),
    error.message ?? error.code,
    details: error.details,
  );

  /// Stable category.
  final ImagePlaygroundErrorCode code;

  /// Human-readable explanation.
  final String message;

  /// Underlying error domain/code, when available.
  final Object? details;
  @override
  String toString() => 'ImagePlaygroundException(${code.wireName}): $message';
}

/// Converts generated-channel errors into public exceptions.
Future<T> guardPlatformCall<T>(Future<T> Function() action) async {
  try {
    return await action();
  } on PlatformException catch (error) {
    throw ImagePlaygroundException.fromPlatformException(error);
  } on MissingPluginException {
    throw const ImagePlaygroundException(
      ImagePlaygroundErrorCode.unsupported,
      'Image Playground is unavailable on this platform.',
    );
  }
}
