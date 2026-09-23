import 'package:flutter/foundation.dart';

import 'messages.g.dart';
import 'types.dart';

/// Options for loading a model (`MLModelConfiguration`).
@immutable
final class MLModelConfiguration {
  /// Creates a configuration. The defaults match Core ML's.
  const MLModelConfiguration({
    this.computeUnits = MLComputeUnits.all,
    this.allowLowPrecisionAccumulationOnGPU = false,
    this.functionName,
    this.modelDisplayName,
    this.reshapeFrequency,
    this.specializationStrategy,
  });

  /// Converts from the Pigeon representation.
  factory MLModelConfiguration.fromMessage(ModelConfigurationMessage message) =>
      MLModelConfiguration(
        computeUnits: MLComputeUnits.fromMessage(message.computeUnits),
        allowLowPrecisionAccumulationOnGPU:
            message.allowLowPrecisionAccumulationOnGPU,
        functionName: message.functionName,
        modelDisplayName: message.modelDisplayName,
        reshapeFrequency: message.reshapeFrequency == null
            ? null
            : MLReshapeFrequency.values[message.reshapeFrequency!.index],
        specializationStrategy: message.specializationStrategy == null
            ? null
            : MLSpecializationStrategy.values[message
                  .specializationStrategy!
                  .index],
      );

  /// Where Core ML may run the model.
  final MLComputeUnits computeUnits;

  /// Lets the GPU accumulate in float16 where it can.
  final bool allowLowPrecisionAccumulationOnGPU;

  /// The function of a multi-function model to load; the default function
  /// when null.
  final String? functionName;

  /// A name shown by Instruments and in logs.
  final String? modelDisplayName;

  /// `MLOptimizationHints.reshapeFrequency`; Core ML's default when null.
  final MLReshapeFrequency? reshapeFrequency;

  /// `MLOptimizationHints.specializationStrategy`; Core ML's default when
  /// null.
  final MLSpecializationStrategy? specializationStrategy;

  /// A copy with the given fields replaced.
  MLModelConfiguration copyWith({
    MLComputeUnits? computeUnits,
    bool? allowLowPrecisionAccumulationOnGPU,
    String? functionName,
    String? modelDisplayName,
    MLReshapeFrequency? reshapeFrequency,
    MLSpecializationStrategy? specializationStrategy,
  }) => MLModelConfiguration(
    computeUnits: computeUnits ?? this.computeUnits,
    allowLowPrecisionAccumulationOnGPU:
        allowLowPrecisionAccumulationOnGPU ??
        this.allowLowPrecisionAccumulationOnGPU,
    functionName: functionName ?? this.functionName,
    modelDisplayName: modelDisplayName ?? this.modelDisplayName,
    reshapeFrequency: reshapeFrequency ?? this.reshapeFrequency,
    specializationStrategy:
        specializationStrategy ?? this.specializationStrategy,
  );

  /// The Pigeon representation.
  ModelConfigurationMessage toMessage() => ModelConfigurationMessage(
    computeUnits: computeUnits.toMessage(),
    allowLowPrecisionAccumulationOnGPU: allowLowPrecisionAccumulationOnGPU,
    functionName: functionName,
    modelDisplayName: modelDisplayName,
    reshapeFrequency: reshapeFrequency?.toMessage(),
    specializationStrategy: specializationStrategy?.toMessage(),
  );

  @override
  bool operator ==(Object other) =>
      other is MLModelConfiguration &&
      other.computeUnits == computeUnits &&
      other.allowLowPrecisionAccumulationOnGPU ==
          allowLowPrecisionAccumulationOnGPU &&
      other.functionName == functionName &&
      other.modelDisplayName == modelDisplayName &&
      other.reshapeFrequency == reshapeFrequency &&
      other.specializationStrategy == specializationStrategy;

  @override
  int get hashCode => Object.hash(
    computeUnits,
    allowLowPrecisionAccumulationOnGPU,
    functionName,
    modelDisplayName,
    reshapeFrequency,
    specializationStrategy,
  );

  @override
  String toString() =>
      'MLModelConfiguration(computeUnits: ${computeUnits.name}, '
      'functionName: $functionName)';
}
