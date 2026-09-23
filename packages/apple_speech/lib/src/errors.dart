import 'dart:convert';

import 'package:flutter/services.dart';

import 'messages.g.dart';

/// Categories of [SpeechException].
enum SpeechErrorCode {
  /// The Speech framework or the feature is not available (for example,
  /// `SpeechAnalyzer` needs iOS 26 / macOS 26).
  unsupported('unsupported'),

  /// An argument was rejected before reaching the framework.
  invalidArgument('invalid_argument'),

  /// An audio file does not exist.
  notFound('not_found'),

  /// Speech recognition (`SFSpeechRecognizer`) is not authorized.
  notAuthorized('not_authorized'),

  /// Microphone access is not authorized.
  microphoneNotAuthorized('microphone_not_authorized'),

  /// The app's Info.plist lacks a required usage description.
  missingUsageDescription('missing_usage_description'),

  /// The locale is not supported by the recognizer or transcriber.
  unsupportedLocale('unsupported_locale'),

  /// The recognizer is temporarily unavailable (for example, offline and
  /// without on-device support).
  recognizerUnavailable('recognizer_unavailable'),

  /// The speech model for the locale is not installed; see
  /// `AssetInventory.installAssets`.
  assetsNotInstalled('assets_not_installed'),

  /// The app already reserved the maximum number of locales.
  tooManyReservedLocales('too_many_reserved_locales'),

  /// The audio format is not supported or could not be converted.
  audioFormat('audio_format'),

  /// The audio could not be read.
  audioReadFailed('audio_read_failed'),

  /// No audio input device is available, or it could not be started.
  microphoneUnavailable('microphone_unavailable'),

  /// The recognizer heard no speech.
  noSpeechDetected('no_speech_detected'),

  /// The system does not have the resources to run the model right now.
  insufficientResources('insufficient_resources'),

  /// The speech service was interrupted or could not be reached.
  serviceUnavailable('service_unavailable'),

  /// Siri or Dictation is disabled on the device.
  dictationDisabled('dictation_disabled'),

  /// Another recognition is still running.
  busy('busy'),

  /// The request timed out.
  timeout('timeout'),

  /// The request was cancelled.
  cancelled('cancelled'),

  /// Any other Speech framework error.
  speechError('speech_error'),

  /// An error this version of the plugin does not recognize.
  unknown('unknown');

  const SpeechErrorCode(this.wireName);

  /// The code used on the platform channel.
  final String wireName;

  static SpeechErrorCode _fromWire(String code) => values.firstWhere(
    (value) => value.wireName == code,
    orElse: () => unknown,
  );
}

/// An error reported by the Speech framework or by the plugin.
class SpeechException implements Exception {
  /// Creates an exception.
  const SpeechException(this.code, this.message, {this.details = const {}});

  /// Converts a [PlatformException] from the plugin's channels.
  factory SpeechException.fromPlatformException(PlatformException error) {
    if (error.code == 'channel-error') {
      return const SpeechException(
        SpeechErrorCode.unsupported,
        'The Speech framework is not available on this platform.',
      );
    }
    return SpeechException(
      SpeechErrorCode._fromWire(error.code),
      error.message ?? error.code,
      details: _decodeDetails(error.details),
    );
  }

  /// Converts an error delivered through the callback API.
  factory SpeechException.fromMessage(ErrorMessage error) => SpeechException(
    SpeechErrorCode._fromWire(error.code),
    error.message,
    details: _decodeDetails(error.details),
  );

  static Map<String, Object?> _decodeDetails(Object? raw) {
    if (raw is String && raw.startsWith('{')) {
      try {
        return (jsonDecode(raw) as Map).cast<String, Object?>();
      } on FormatException {
        return {'debug': raw};
      }
    }
    if (raw != null) return {'debug': raw.toString()};
    return const {};
  }

  /// The category of the error.
  final SpeechErrorCode code;

  /// A description of what went wrong.
  final String message;

  /// Extra structured information, such as the native error `domain` and
  /// `nativeCode`, the `locale`, the `path` or the Info.plist `key`.
  final Map<String, Object?> details;

  /// The native error domain, such as `SFSpeechErrorDomain`, when known.
  String? get domain => details['domain'] as String?;

  /// The native error code within [domain], when known.
  int? get nativeCode => details['nativeCode'] as int?;

  @override
  String toString() =>
      'SpeechException(${code.wireName}): $message'
      '${details.isEmpty ? '' : ' $details'}';
}

/// Awaits [body], converting platform errors.
Future<T> guardPlatformCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PlatformException catch (error) {
    throw SpeechException.fromPlatformException(error);
  }
}
