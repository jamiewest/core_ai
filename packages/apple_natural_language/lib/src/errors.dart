import 'package:flutter/services.dart';

/// Categories of [NaturalLanguageException].
enum NaturalLanguageErrorCode {
  /// The Natural Language framework, or this feature, is unavailable.
  unsupported('unsupported'),

  /// An object was used after being disposed.
  invalidHandle('invalid_handle'),

  /// An argument was rejected, such as an offset outside the text.
  invalidArgument('invalid_argument'),

  /// A file does not exist.
  notFound('not_found'),

  /// The language assets are not on this device.
  assetsUnavailable('assets_unavailable'),

  /// The framework reported an error.
  naturalLanguageError('natural_language_error'),

  /// An error this version of the plugin does not recognize.
  unknown('unknown');

  const NaturalLanguageErrorCode(this.wireName);

  /// The code used on the platform channel.
  final String wireName;

  static NaturalLanguageErrorCode _fromWire(String code) => values.firstWhere(
    (value) => value.wireName == code,
    orElse: () => unknown,
  );
}

/// An error reported by the Natural Language framework or the plugin.
class NaturalLanguageException implements Exception {
  /// Creates an exception.
  const NaturalLanguageException(this.code, this.message, {this.details});

  /// Converts a [PlatformException] from the plugin's channels.
  factory NaturalLanguageException.fromPlatformException(
    PlatformException error,
  ) {
    if (error.code == 'channel-error') {
      return const NaturalLanguageException(
        NaturalLanguageErrorCode.unsupported,
        'The Natural Language framework is not available on this platform.',
      );
    }
    return NaturalLanguageException(
      NaturalLanguageErrorCode._fromWire(error.code),
      error.message ?? error.code,
      details: error.details?.toString(),
    );
  }

  /// The category of the error.
  final NaturalLanguageErrorCode code;

  /// A description of what went wrong.
  final String message;

  /// Extra diagnostic information.
  final String? details;

  @override
  String toString() => 'NaturalLanguageException(${code.wireName}): $message';
}

/// Awaits [body], converting platform errors.
Future<T> guardPlatformCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PlatformException catch (error) {
    throw NaturalLanguageException.fromPlatformException(error);
  }
}
