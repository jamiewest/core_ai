import 'package:flutter/services.dart';

/// Categories of [TranslationException], mirroring Apple's
/// `TranslationError` plus a few plugin-level cases.
enum TranslationErrorCode {
  /// The Translation framework, or this feature, is unavailable on this OS
  /// version.
  unsupported('unsupported'),

  /// An object was used after being disposed.
  invalidHandle('invalid_handle'),

  /// An argument was rejected, such as an empty language identifier.
  invalidArgument('invalid_argument'),

  /// The source language is not supported (`unsupportedSourceLanguage`).
  unsupportedSourceLanguage('unsupported_source_language'),

  /// The target language is not supported (`unsupportedTargetLanguage`).
  unsupportedTargetLanguage('unsupported_target_language'),

  /// Both languages are supported, but not as a pair
  /// (`unsupportedLanguagePairing`), for example English to English.
  unsupportedLanguagePairing('unsupported_language_pairing'),

  /// The framework could not tell which language the text is in
  /// (`unableToIdentifyLanguage`).
  unableToIdentifyLanguage('unable_to_identify_language'),

  /// The text was empty (`nothingToTranslate`).
  nothingToTranslate('nothing_to_translate'),

  /// The session was cancelled with `TranslationSession.cancel`
  /// (`alreadyCancelled`).
  alreadyCancelled('already_cancelled'),

  /// The languages (or the model for the chosen strategy) are not downloaded
  /// on this device (`notInstalled`).
  notInstalled('not_installed'),

  /// The framework failed internally (`internalError`).
  internalError('internal_error'),

  /// The request was cancelled from Dart, for example by cancelling a
  /// batch stream subscription.
  cancelled('cancelled'),

  /// Another error reported by the framework.
  translationError('translation_error'),

  /// An error this version of the plugin does not recognize.
  unknown('unknown');

  const TranslationErrorCode(this.wireName);

  /// The code used on the platform channel.
  final String wireName;

  /// The code for [wireName], or [unknown].
  static TranslationErrorCode fromWire(String wireName) => values.firstWhere(
    (value) => value.wireName == wireName,
    orElse: () => unknown,
  );
}

/// An error reported by the Translation framework or the plugin.
class TranslationException implements Exception {
  /// Creates an exception.
  const TranslationException(this.code, this.message, {this.details});

  /// Converts a [PlatformException] from the plugin's channels.
  factory TranslationException.fromPlatformException(PlatformException error) {
    if (error.code == 'channel-error') {
      return const TranslationException(
        TranslationErrorCode.unsupported,
        'The Translation framework is not available on this platform. '
        'It needs iOS 18 or macOS 15.',
      );
    }
    return TranslationException(
      TranslationErrorCode.fromWire(error.code),
      error.message ?? error.code,
      details: error.details?.toString(),
    );
  }

  /// The category of the error.
  final TranslationErrorCode code;

  /// A description of what went wrong, such as Apple's failure reason
  /// ("This language pairing is not supported.").
  final String message;

  /// Extra diagnostic information, such as the underlying Swift error.
  final String? details;

  @override
  String toString() => 'TranslationException(${code.wireName}): $message';
}

/// Awaits [body], converting platform errors.
Future<T> guardPlatformCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PlatformException catch (error) {
    throw TranslationException.fromPlatformException(error);
  }
}
