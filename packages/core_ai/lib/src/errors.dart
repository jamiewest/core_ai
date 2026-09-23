import 'package:flutter/services.dart';

/// Categories of [CoreAIException].
enum CoreAIErrorCode {
  /// Core AI is not available on this device (it needs iOS 27+ / macOS 27+).
  unsupported('unsupported'),

  /// A model, function, value or stream was used after being disposed.
  invalidHandle('invalid_handle'),

  /// An argument was rejected before reaching Core AI, for example a shape
  /// with the wrong rank or data of the wrong size.
  invalidArgument('invalid_argument'),

  /// A file, function or argument name does not exist.
  notFound('not_found'),

  /// A native value is being used by another in-flight operation.
  busy('busy'),

  /// A model asset could not be read or updated (`AssetError`).
  assetError('asset_error'),

  /// Core AI reported an error, for example while specializing or running.
  coreAIError('core_ai_error'),

  /// A pixel buffer could not be created, converted or encoded.
  pixelBufferError('pixel_buffer_error'),

  /// An error this version of the plugin does not recognize.
  unknown('unknown');

  const CoreAIErrorCode(this.wireName);

  /// The code used on the platform channel.
  final String wireName;

  static CoreAIErrorCode _fromWire(String code) => values.firstWhere(
    (value) => value.wireName == code,
    orElse: () => unknown,
  );
}

/// An error reported by Core AI or by the core_ai plugin.
class CoreAIException implements Exception {
  /// Creates an exception with a [code] and a human-readable [message].
  const CoreAIException(this.code, this.message, {this.details});

  /// Converts a [PlatformException] from the plugin's channels.
  factory CoreAIException.fromPlatformException(PlatformException error) {
    // Pigeon reports an unregistered API as a channel error; the host API is
    // only registered when Core AI is available.
    if (error.code == 'channel-error') {
      return CoreAIException(
        CoreAIErrorCode.unsupported,
        'Core AI is not available on this device. It requires iOS 27 or '
        'macOS 27 or later.',
        details: error.message,
      );
    }
    return CoreAIException(
      CoreAIErrorCode._fromWire(error.code),
      error.message ?? error.code,
      details: error.details?.toString(),
    );
  }

  /// The category of the error.
  final CoreAIErrorCode code;

  /// A description of what went wrong.
  final String message;

  /// Extra diagnostic information, such as the underlying Swift error.
  final String? details;

  @override
  String toString() {
    final extra = details == null ? '' : ' ($details)';
    return 'CoreAIException(${code.wireName}): $message$extra';
  }
}

/// Awaits [body], converting platform errors into [CoreAIException]s.
Future<T> guardPlatformCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PlatformException catch (error) {
    throw CoreAIException.fromPlatformException(error);
  }
}
