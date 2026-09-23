import 'package:flutter/services.dart';

/// Categories of [CoreMLException].
enum CoreMLErrorCode {
  /// Core ML's iOS 18 / macOS 15 surface is not available on this device.
  unsupported('unsupported'),

  /// A model or state was used after being disposed.
  invalidHandle('invalid_handle'),

  /// An argument was rejected before reaching Core ML, for example a multi
  /// array whose data does not match its shape.
  invalidArgument('invalid_argument'),

  /// A file, function or feature name does not exist.
  notFound('not_found'),

  /// An [MLState] is already taking part in another prediction. Core ML
  /// requires predictions that share a state to be serialized.
  busy('busy'),

  /// A feature value had the wrong type for the model's input
  /// (`MLModelErrorFeatureType`).
  featureType('feature_type'),

  /// A file could not be read or written (`MLModelErrorIO`).
  ioError('io_error'),

  /// The model could not be decrypted (`MLModelErrorModelDecryption`).
  modelDecryption('model_decryption'),

  /// The prediction was cancelled (`MLModelErrorPredictionCancelled`).
  predictionCancelled('prediction_cancelled'),

  /// A custom layer or custom model implementation is missing.
  customModel('custom_model'),

  /// An on-device model update failed (`MLModelErrorUpdate`).
  updateError('update_error'),

  /// An unsupported model parameter was queried (`MLModelErrorParameters`).
  parameters('parameters'),

  /// Core ML reported an error, for example while compiling or predicting.
  coreMLError('core_ml_error'),

  /// A pixel buffer could not be created, converted or encoded.
  pixelBufferError('pixel_buffer_error'),

  /// An error this version of the plugin does not recognize.
  unknown('unknown');

  const CoreMLErrorCode(this.wireName);

  /// The code used on the platform channel.
  final String wireName;

  static CoreMLErrorCode _fromWire(String code) => values.firstWhere(
    (value) => value.wireName == code,
    orElse: () => unknown,
  );
}

/// An error reported by Core ML or by the core_ml plugin.
class CoreMLException implements Exception {
  /// Creates an exception with a [code] and a human-readable [message].
  const CoreMLException(this.code, this.message, {this.details});

  /// Converts a [PlatformException] from the plugin's channels.
  factory CoreMLException.fromPlatformException(PlatformException error) {
    // Pigeon reports an unregistered API as a channel error; the host API is
    // only registered on iOS 18+ / macOS 15+.
    if (error.code == 'channel-error') {
      return CoreMLException(
        CoreMLErrorCode.unsupported,
        'core_ml is not available on this device. It requires iOS 18 or '
        'macOS 15 or later.',
        details: error.message,
      );
    }
    return CoreMLException(
      CoreMLErrorCode._fromWire(error.code),
      error.message ?? error.code,
      details: error.details?.toString(),
    );
  }

  /// The category of the error.
  final CoreMLErrorCode code;

  /// A description of what went wrong.
  final String message;

  /// Extra diagnostic information, such as the underlying `NSError` domain.
  final String? details;

  @override
  String toString() {
    final extra = details == null ? '' : ' ($details)';
    return 'CoreMLException(${code.wireName}): $message$extra';
  }
}

/// Awaits [body], converting platform errors into [CoreMLException]s.
Future<T> guardPlatformCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PlatformException catch (error) {
    throw CoreMLException.fromPlatformException(error);
  }
}
