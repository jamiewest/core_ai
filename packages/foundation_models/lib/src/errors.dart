import 'dart:convert';

import 'package:flutter/services.dart';

/// Categories of [FoundationModelsException].
enum FoundationModelsErrorCode {
  /// Foundation Models is not available (it needs iOS 26+ / macOS 26+), or
  /// the feature needs iOS 27 / macOS 27.
  unsupported('unsupported'),

  /// A session or adapter was used after being disposed.
  invalidHandle('invalid_handle'),

  /// An argument was rejected before reaching the framework.
  invalidArgument('invalid_argument'),

  /// A file or name does not exist.
  notFound('not_found'),

  /// The model is not available on this device right now.
  modelUnavailable('model_unavailable'),

  /// The model's assets are not downloaded yet.
  assetsUnavailable('assets_unavailable'),

  /// The prompt plus transcript exceeded the model's context window.
  contextWindowExceeded('context_window_exceeded'),

  /// The prompt or the response tripped Apple's safety guardrails.
  guardrailViolation('guardrail_violation'),

  /// The model refused to answer.
  refusal('refusal'),

  /// The schema used a guide the model does not support.
  unsupportedGuide('unsupported_guide'),

  /// The language or locale is not supported by the model.
  unsupportedLanguage('unsupported_language'),

  /// The model does not have a required capability, such as vision.
  unsupportedCapability('unsupported_capability'),

  /// The transcript contains content this model cannot consume.
  unsupportedTranscriptContent('unsupported_transcript_content'),

  /// The response could not be decoded into the requested schema.
  decodingFailure('decoding_failure'),

  /// Too many requests.
  rateLimited('rate_limited'),

  /// The Private Cloud Compute quota is used up.
  quotaLimitReached('quota_limit_reached'),

  /// Private Cloud Compute could not be reached.
  networkFailure('network_failure'),

  /// Private Cloud Compute is unavailable.
  serviceUnavailable('service_unavailable'),

  /// The request timed out.
  timeout('timeout'),

  /// The session is already responding.
  concurrentRequests('concurrent_requests'),

  /// A Dart tool threw.
  toolCallFailed('tool_call_failed'),

  /// A generation schema was rejected.
  schemaError('schema_error'),

  /// An adapter could not be loaded or compiled.
  adapterError('adapter_error'),

  /// The request was cancelled.
  cancelled('cancelled'),

  /// Any other Foundation Models error.
  foundationModelsError('foundation_models_error'),

  /// An error this version of the plugin does not recognize.
  unknown('unknown');

  const FoundationModelsErrorCode(this.wireName);

  /// The code used on the platform channel.
  final String wireName;

  static FoundationModelsErrorCode _fromWire(String code) => values.firstWhere(
    (value) => value.wireName == code,
    orElse: () => unknown,
  );
}

/// An error reported by Foundation Models or by the plugin.
class FoundationModelsException implements Exception {
  /// Creates an exception.
  const FoundationModelsException(
    this.code,
    this.message, {
    this.details = const {},
  });

  /// Converts a [PlatformException] from the plugin's channels.
  factory FoundationModelsException.fromPlatformException(
    PlatformException error,
  ) {
    if (error.code == 'channel-error') {
      return const FoundationModelsException(
        FoundationModelsErrorCode.unsupported,
        'Foundation Models is not available on this device. It requires '
        'iOS 26 or macOS 26 or later with Apple Intelligence.',
      );
    }
    var details = const <String, Object?>{};
    final raw = error.details;
    if (raw is String && raw.startsWith('{')) {
      try {
        details = (jsonDecode(raw) as Map).cast<String, Object?>();
      } on FormatException {
        details = {'debug': raw};
      }
    } else if (raw != null) {
      details = {'debug': raw.toString()};
    }
    return FoundationModelsException(
      FoundationModelsErrorCode._fromWire(error.code),
      error.message ?? error.code,
      details: details,
    );
  }

  /// The category of the error.
  final FoundationModelsErrorCode code;

  /// A description of what went wrong.
  final String message;

  /// Extra structured information, such as `contextSize`, `tokenCount`,
  /// `resetDateMillis` or the failing `tool`.
  final Map<String, Object?> details;

  /// For [FoundationModelsErrorCode.contextWindowExceeded]: the model's
  /// context size in tokens.
  int? get contextSize => details['contextSize'] as int?;

  /// For [FoundationModelsErrorCode.contextWindowExceeded]: how many tokens
  /// the request needed.
  int? get tokenCount => details['tokenCount'] as int?;

  /// For [FoundationModelsErrorCode.rateLimited] and
  /// [FoundationModelsErrorCode.quotaLimitReached]: when the limit resets.
  DateTime? get resetDate => switch (details['resetDateMillis']) {
    final int millis => DateTime.fromMillisecondsSinceEpoch(millis),
    _ => null,
  };

  /// For [FoundationModelsErrorCode.toolCallFailed]: the tool that failed.
  String? get toolName => details['tool'] as String?;

  @override
  String toString() =>
      'FoundationModelsException(${code.wireName}): $message'
      '${details.isEmpty ? '' : ' $details'}';
}

/// Awaits [body], converting platform errors.
Future<T> guardPlatformCall<T>(Future<T> Function() body) async {
  try {
    return await body();
  } on PlatformException catch (error) {
    throw FoundationModelsException.fromPlatformException(error);
  }
}
