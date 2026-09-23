import 'package:flutter/services.dart';

/// Stable categories of sound-analysis failures.
enum SoundAnalysisErrorCode {
  /// The framework or platform is unavailable.
  unsupported('unsupported'),

  /// A setting or sample buffer is invalid.
  invalidArgument('invalid_argument'),

  /// A custom model does not exist.
  notFound('not_found'),

  /// The analysis already finished or was cancelled.
  notRunning('not_running'),

  /// The microphone is already being analyzed.
  busy('busy'),

  /// The app lacks microphone permission.
  permissionDenied('permission_denied'),

  /// No microphone input is available.
  noInputDevice('no_input_device'),

  /// The audio file cannot be read.
  invalidFile('invalid_file'),

  /// The audio format is unsupported.
  invalidFormat('invalid_format'),

  /// The custom model is not a usable sound classifier.
  invalidModel('invalid_model'),

  /// SoundAnalysis could not complete an operation.
  operationFailed('operation_failed'),

  /// Another native sound-analysis error.
  soundAnalysisError('sound_analysis_error'),

  /// An unrecognized platform error.
  unknown('unknown');

  const SoundAnalysisErrorCode(this.wireName);

  /// The platform-channel error code.
  final String wireName;

  /// Maps a native error code, preserving unknown errors.
  static SoundAnalysisErrorCode fromWire(String code) => values.firstWhere(
    (value) => value.wireName == code,
    orElse: () => unknown,
  );
}

/// An error reported by the native sound analyzer.
class SoundAnalysisException implements Exception {
  /// Creates an error with optional native details.
  const SoundAnalysisException(this.code, this.message, {this.details});

  /// Stable category for choosing recovery behavior.
  final SoundAnalysisErrorCode code;

  /// Human-readable explanation.
  final String message;

  /// Native error domain and code, when available.
  final String? details;

  /// Converts a platform exception.
  factory SoundAnalysisException.fromPlatform(PlatformException error) =>
      SoundAnalysisException(
        error.code == 'channel-error'
            ? SoundAnalysisErrorCode.unsupported
            : SoundAnalysisErrorCode.fromWire(error.code),
        error.message ?? error.code,
        details: error.details?.toString(),
      );

  @override
  String toString() => 'SoundAnalysisException(${code.wireName}): $message';
}

/// Translates channel failures into [SoundAnalysisException].
Future<T> guardPlatformCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PlatformException catch (error) {
    throw SoundAnalysisException.fromPlatform(error);
  }
}
