import 'package:flutter/services.dart';

import 'messages.g.dart';

/// Categories of [MediaIntelligenceException].
enum MediaIntelligenceErrorCode {
  /// MediaIntelligence is unavailable: it needs iOS 27 or macOS 27.
  unsupported('unsupported'),

  /// An argument was rejected, such as an empty or duplicate asset id.
  invalidArgument('invalid_argument'),

  /// A face analyzer was used after being disposed.
  invalidHandle('invalid_handle'),

  /// A media file does not exist.
  notFound('not_found'),

  /// The working directory cannot be created or used.
  workingDirectory('working_directory'),

  /// A video could not be processed.
  mediaProcessing('media_processing'),

  /// Images could not be processed for faces, for example an unreadable file.
  faceGroupProcessing('face_group_processing'),

  /// Stored results could not be read.
  resultFetching('result_fetching'),

  /// Another error reported by the framework.
  mediaIntelligenceError('media_intelligence_error'),

  /// An error this version of the plugin does not recognize.
  unknown('unknown');

  const MediaIntelligenceErrorCode(this.wireName);

  /// The code used on the platform channel.
  final String wireName;

  /// Maps a platform code, keeping unknown codes inspectable as [unknown].
  static MediaIntelligenceErrorCode fromWire(String code) => values.firstWhere(
    (value) => value.wireName == code,
    orElse: () => unknown,
  );
}

/// An error reported by the MediaIntelligence framework or the plugin.
class MediaIntelligenceException implements Exception {
  /// Creates an exception.
  const MediaIntelligenceException(this.code, this.message, {this.details});

  /// Converts a [PlatformException] from the plugin's channels.
  factory MediaIntelligenceException.fromPlatformException(
    PlatformException error,
  ) {
    if (error.code == 'channel-error') {
      return const MediaIntelligenceException(
        MediaIntelligenceErrorCode.unsupported,
        'MediaIntelligence needs iOS 27 or macOS 27.',
      );
    }
    return MediaIntelligenceException(
      MediaIntelligenceErrorCode.fromWire(error.code),
      error.message ?? error.code,
      details: error.details?.toString(),
    );
  }

  /// Converts the error of one failed request.
  factory MediaIntelligenceException.fromMessage(RequestErrorMessage error) =>
      MediaIntelligenceException(
        MediaIntelligenceErrorCode.fromWire(error.code),
        error.message,
        details: error.details,
      );

  /// The category of the error.
  final MediaIntelligenceErrorCode code;

  /// A description of what went wrong.
  final String message;

  /// Extra diagnostic information.
  final String? details;

  @override
  String toString() => 'MediaIntelligenceException(${code.wireName}): $message';
}

/// Awaits [body], converting platform errors.
Future<T> guardPlatformCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PlatformException catch (error) {
    throw MediaIntelligenceException.fromPlatformException(error);
  }
}
