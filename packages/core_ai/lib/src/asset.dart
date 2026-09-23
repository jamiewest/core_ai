import 'package:flutter/foundation.dart';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';

/// An `.aimodel` asset on disk (Core AI's `AIModelAsset`): its metadata, a
/// structural summary, and cleanup of derived artifacts.
///
/// Reading metadata does not specialize or load the model.
@immutable
final class AIModelAsset {
  /// Refers to the `.aimodel` at [path]. Nothing is read until a method is
  /// called.
  const AIModelAsset(this.path);

  /// The path of the `.aimodel` directory.
  final String path;

  /// Whether [path] holds a valid `.aimodel`.
  static Future<bool> isValid(String path) {
    final host = CoreAIBindings.instance.host;
    return guardPlatformCall(() => host.isValidAsset(path));
  }

  /// The author, license, description and creator-defined metadata.
  Future<AIModelAssetMetadata> metadata() async {
    final host = CoreAIBindings.instance.host;
    final message = await guardPlatformCall(() => host.assetMetadata(path));
    final millis = message.creationDateMillis;
    return AIModelAssetMetadata(
      author: message.author,
      license: message.license,
      description: message.modelDescription,
      creationDate: millis == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
      creatorDefined: Map.unmodifiable(message.creatorDefined),
    );
  }

  /// The functions, storage types, compute types and operation counts of the
  /// model, or null if the asset has no summary.
  ///
  /// [includeStatistics] also counts operations, which reads more of the
  /// asset.
  Future<AIModelAssetSummary?> summary({bool includeStatistics = false}) async {
    final host = CoreAIBindings.instance.host;
    final message = await guardPlatformCall(
      () => host.assetSummary(path, includeStatistics),
    );
    return message == null ? null : AIModelAssetSummary._fromMessage(message);
  }

  /// Updates metadata in place. Null arguments leave fields unchanged.
  ///
  /// [creatorDefined] values may be String, int, double, bool, or Lists and
  /// Maps of those. Keys in [removeCreatorDefined] are deleted. The asset
  /// must be writable, so copy bundled models to a writable directory first.
  ///
  /// Core AI (as of iOS/macOS 27.0) stores integers 0 and 1 correctly but
  /// reads them back as `false` and `true`; store flags as bools and avoid
  /// relying on 0/1 integers round-tripping.
  Future<void> updateMetadata({
    String? author,
    String? license,
    String? description,
    DateTime? creationDate,
    bool clearCreationDate = false,
    Map<String, Object?> creatorDefined = const {},
    Iterable<String> removeCreatorDefined = const [],
  }) {
    final host = CoreAIBindings.instance.host;
    return guardPlatformCall(
      () => host.updateAssetMetadata(
        path,
        AssetMetadataUpdateMessage(
          author: author,
          license: license,
          modelDescription: description,
          creationDateMillis: creationDate?.millisecondsSinceEpoch,
          clearCreationDate: clearCreationDate,
          creatorDefined: creatorDefined,
          creatorDefinedRemovals: removeCreatorDefined.toList(),
        ),
      ),
    );
  }

  /// Deletes artifacts Core AI derived from the asset (Core AI's
  /// `removeDerivedArtifacts()`).
  Future<void> removeDerivedArtifacts() {
    final host = CoreAIBindings.instance.host;
    return guardPlatformCall(() => host.removeAssetDerivedArtifacts(path));
  }

  @override
  bool operator ==(Object other) => other is AIModelAsset && other.path == path;

  @override
  int get hashCode => path.hashCode;

  @override
  String toString() => 'AIModelAsset($path)';
}

/// Descriptive metadata stored in an `.aimodel`.
@immutable
final class AIModelAssetMetadata {
  /// Creates metadata.
  const AIModelAssetMetadata({
    required this.author,
    required this.license,
    required this.description,
    required this.creationDate,
    required this.creatorDefined,
  });

  /// Who created the model.
  final String author;

  /// The model's license.
  final String license;

  /// A description of the model.
  final String description;

  /// When the model was created, if recorded.
  final DateTime? creationDate;

  /// Free-form values added by the model's creator.
  final Map<String, Object?> creatorDefined;

  @override
  String toString() =>
      'AIModelAssetMetadata(author: $author, license: '
      '$license, description: $description, creationDate: $creationDate, '
      'creatorDefined: $creatorDefined)';
}

/// A named argument in an [AIModelAssetSummary], with its type as text.
@immutable
final class AssetValueSummary {
  /// Creates a summary entry.
  const AssetValueSummary({required this.name, required this.typeName});

  /// The argument name.
  final String name;

  /// A textual description of the argument's type.
  final String typeName;

  @override
  String toString() => '$name: $typeName';
}

/// A function in an [AIModelAssetSummary].
@immutable
final class AssetFunctionSummary {
  /// Creates a summary entry.
  const AssetFunctionSummary({
    required this.name,
    required this.inputs,
    required this.states,
    required this.outputs,
  });

  /// The function name.
  final String name;

  /// The inputs.
  final List<AssetValueSummary> inputs;

  /// The states.
  final List<AssetValueSummary> states;

  /// The outputs.
  final List<AssetValueSummary> outputs;

  @override
  String toString() => '$name($inputs, states: $states) -> $outputs';
}

/// The structure of an `.aimodel` (Core AI's `AIModelAsset.Summary`).
@immutable
final class AIModelAssetSummary {
  /// Creates a summary.
  const AIModelAssetSummary({
    required this.functions,
    required this.storageTypes,
    required this.computeTypes,
    required this.operationCounts,
  });

  factory AIModelAssetSummary._fromMessage(AssetSummaryMessage message) {
    List<AssetValueSummary> values(List<AssetValueDescriptorMessage> list) => [
      for (final value in list)
        AssetValueSummary(name: value.name, typeName: value.typeName),
    ];
    return AIModelAssetSummary(
      functions: [
        for (final function in message.functions)
          AssetFunctionSummary(
            name: function.name,
            inputs: values(function.inputs),
            states: values(function.states),
            outputs: values(function.outputs),
          ),
      ],
      storageTypes: {
        for (final entry in message.storageTypes) entry.name: entry.count,
      },
      computeTypes: List.unmodifiable(message.computeTypes),
      operationCounts: {
        for (final entry in message.operationDistribution)
          entry.name: entry.count,
      },
    );
  }

  /// The model's functions.
  final List<AssetFunctionSummary> functions;

  /// How many weights use each storage type.
  final Map<String, int> storageTypes;

  /// The compute types the model uses.
  final List<String> computeTypes;

  /// How many times each operation occurs (with statistics only).
  final Map<String, int> operationCounts;

  @override
  String toString() =>
      'AIModelAssetSummary(functions: $functions, '
      'storageTypes: $storageTypes, computeTypes: $computeTypes, '
      'operationCounts: $operationCounts)';
}
