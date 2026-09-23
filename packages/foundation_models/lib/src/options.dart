import 'package:flutter/foundation.dart';

import 'messages.g.dart';

/// How the model picks each token (Apple's `GenerationOptions.SamplingMode`).
@immutable
final class SamplingMode {
  const SamplingMode._(this._kind, {this.topK, this.threshold, this.seed});

  /// Always take the most likely token.
  static const SamplingMode greedy = SamplingMode._(SamplingKindMessage.greedy);

  /// Sample from the [k] most likely tokens.
  const SamplingMode.topK(int k, {int? seed})
    : this._(SamplingKindMessage.topK, topK: k, seed: seed);

  /// Sample from the most likely tokens whose probabilities sum to
  /// [threshold] (nucleus sampling).
  const SamplingMode.probabilityThreshold(double threshold, {int? seed})
    : this._(
        SamplingKindMessage.probabilityThreshold,
        threshold: threshold,
        seed: seed,
      );

  final SamplingKindMessage _kind;

  /// The number of candidate tokens, for [SamplingMode.topK].
  final int? topK;

  /// The probability mass, for [SamplingMode.probabilityThreshold].
  final double? threshold;

  /// A seed, to make sampling reproducible.
  final int? seed;
}

/// Whether the model may call tools (Apple's `ToolCallingMode`).
enum ToolCallingMode {
  /// The model decides.
  allowed,

  /// The model must call a tool.
  required,

  /// The model must not call tools.
  disallowed;

  ToolCallingModeMessage _toMessage() => ToolCallingModeMessage.values[index];
}

/// Options for one request (Apple's `GenerationOptions`).
@immutable
final class GenerationOptions {
  /// Creates options. Omitted values use the model's defaults.
  const GenerationOptions({
    this.sampling,
    this.temperature,
    this.maximumResponseTokens,
    this.toolCallingMode,
  });

  /// How tokens are sampled.
  final SamplingMode? sampling;

  /// Higher values make output more random. Typically 0.0 to 2.0.
  final double? temperature;

  /// Caps how many tokens the response may use.
  final int? maximumResponseTokens;

  /// Whether the model may call tools. Needs iOS 27 / macOS 27.
  final ToolCallingMode? toolCallingMode;

  /// The Pigeon representation.
  GenerationOptionsMessage toMessage() => GenerationOptionsMessage(
    samplingKind: sampling?._kind,
    topK: sampling?.topK,
    probabilityThreshold: sampling?.threshold,
    seed: sampling?.seed,
    temperature: temperature,
    maximumResponseTokens: maximumResponseTokens,
    toolCallingMode: toolCallingMode?._toMessage(),
  );
}

/// How much the model should reason before answering (Apple's
/// `ContextOptions.ReasoningLevel`). Needs a model with the reasoning
/// capability, such as Private Cloud Compute.
@immutable
final class ReasoningLevel {
  const ReasoningLevel._(this._level, [this.customValue]);

  /// Minimal reasoning.
  static const ReasoningLevel light = ReasoningLevel._(
    ReasoningLevelMessage.light,
  );

  /// Moderate reasoning.
  static const ReasoningLevel moderate = ReasoningLevel._(
    ReasoningLevelMessage.moderate,
  );

  /// Thorough reasoning.
  static const ReasoningLevel deep = ReasoningLevel._(
    ReasoningLevelMessage.deep,
  );

  /// A model-specific level.
  const ReasoningLevel.custom(String value)
    : this._(ReasoningLevelMessage.custom, value);

  final ReasoningLevelMessage _level;

  /// The value for [ReasoningLevel.custom].
  final String? customValue;
}

/// Per-request context settings (Apple's `ContextOptions`). Needs iOS 27 /
/// macOS 27.
@immutable
final class ContextOptions {
  /// Creates context options.
  const ContextOptions({this.includeSchemaInPrompt, this.reasoningLevel});

  /// Whether the schema is included in the prompt for guided generation.
  /// Defaults to true.
  final bool? includeSchemaInPrompt;

  /// How much the model should reason.
  final ReasoningLevel? reasoningLevel;

  /// The Pigeon representation.
  ContextOptionsMessage toMessage() => ContextOptionsMessage(
    includeSchemaInPrompt: includeSchemaInPrompt,
    reasoningLevel: reasoningLevel?._level,
    customReasoningLevel: reasoningLevel?.customValue,
  );
}

/// How many tokens a request used (Apple's `LanguageModelSession.Usage`).
/// Needs iOS 27 / macOS 27; otherwise the counts are zero.
@immutable
final class Usage {
  /// Creates a usage record.
  const Usage({
    required this.inputTokens,
    required this.cachedInputTokens,
    required this.outputTokens,
    required this.reasoningTokens,
  });

  /// Converts from the Pigeon representation.
  factory Usage.fromMessage(UsageMessage message) => Usage(
    inputTokens: message.inputTokens,
    cachedInputTokens: message.cachedInputTokens,
    outputTokens: message.outputTokens,
    reasoningTokens: message.reasoningTokens,
  );

  /// Tokens consumed by the prompt, instructions and transcript.
  final int inputTokens;

  /// How many input tokens came from the model's cache.
  final int cachedInputTokens;

  /// Tokens produced.
  final int outputTokens;

  /// Output tokens spent on reasoning.
  final int reasoningTokens;

  /// Input plus output tokens.
  int get totalTokens => inputTokens + outputTokens;

  @override
  String toString() => 'Usage(input: $inputTokens, output: $outputTokens)';
}
