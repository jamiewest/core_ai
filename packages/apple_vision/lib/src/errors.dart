import 'package:flutter/services.dart';

/// Categories of [AppleVisionException].
enum AppleVisionErrorCode {
  /// Vision's still-image requests are not available on this device (they
  /// need iOS 27+ / macOS 27+).
  unsupported('unsupported'),

  /// An argument was rejected before reaching Vision, for example a region of
  /// interest outside the unit square or pixel data of the wrong size.
  invalidArgument('invalid_argument'),

  /// A file does not exist.
  notFound('not_found'),

  /// An image could not be read or decoded.
  imageError('image_error'),

  /// A mask or heat map could not be copied or encoded.
  maskError('mask_error'),

  /// Vision reported an error (`VisionError`).
  visionError('vision_error'),

  /// An error this version of the plugin does not recognize.
  unknown('unknown');

  const AppleVisionErrorCode(this.wireName);

  /// The code used on the platform channel.
  final String wireName;

  /// The code for [wire], or [unknown].
  static AppleVisionErrorCode fromWire(String wire) => values.firstWhere(
    (value) => value.wireName == wire,
    orElse: () => unknown,
  );
}

/// An error reported by Vision or by the apple_vision plugin.
class AppleVisionException implements Exception {
  /// Creates an exception with a [code] and a human-readable [message].
  const AppleVisionException(this.code, this.message, {this.details});

  /// Converts a [PlatformException] from the plugin's channels.
  factory AppleVisionException.fromPlatformException(PlatformException error) {
    // Pigeon reports an unregistered API as a channel error; the host API is
    // only registered when Vision is available.
    if (error.code == 'channel-error') {
      return AppleVisionException(
        AppleVisionErrorCode.unsupported,
        'Apple Vision is not available on this device. It requires iOS 27 or '
        'macOS 27 or later.',
        details: error.message,
      );
    }
    return AppleVisionException(
      AppleVisionErrorCode.fromWire(error.code),
      error.message ?? error.code,
      details: error.details?.toString(),
    );
  }

  /// The category of the error.
  final AppleVisionErrorCode code;

  /// A description of what went wrong.
  final String message;

  /// Extra diagnostic information, such as the underlying `VisionError`.
  final String? details;

  @override
  String toString() {
    final extra = details == null ? '' : ' ($details)';
    return 'AppleVisionException(${code.wireName}): $message$extra';
  }
}

/// Awaits [body], converting platform errors into [AppleVisionException]s.
Future<T> guardPlatformCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PlatformException catch (error) {
    throw AppleVisionException.fromPlatformException(error);
  }
}
