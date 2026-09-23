import 'package:flutter/foundation.dart';

import 'messages.g.dart';
import 'types.dart';

/// What a model needs and produces (`MLModelDescription`).
@immutable
final class MLModelDescription {
  /// Creates a description.
  MLModelDescription({
    required Map<String, MLFeatureDescription> inputs,
    required Map<String, MLFeatureDescription> outputs,
    required Map<String, MLFeatureDescription> states,
    required Map<String, MLFeatureDescription> trainingInputs,
    this.predictedFeatureName,
    this.predictedProbabilitiesName,
    List<Object>? classLabels,
    required this.isUpdatable,
    required this.metadata,
  }) : inputs = Map.unmodifiable(inputs),
       outputs = Map.unmodifiable(outputs),
       states = Map.unmodifiable(states),
       trainingInputs = Map.unmodifiable(trainingInputs),
       classLabels = classLabels == null
           ? null
           : List<Object>.unmodifiable(classLabels);

  /// Converts from the Pigeon representation.
  factory MLModelDescription.fromMessage(ModelDescriptionMessage message) {
    Map<String, MLFeatureDescription> features(
      List<FeatureDescriptionMessage> list,
    ) => {
      for (final feature in list)
        feature.name: MLFeatureDescription.fromMessage(feature),
    };
    return MLModelDescription(
      inputs: features(message.inputs),
      outputs: features(message.outputs),
      states: features(message.states),
      trainingInputs: features(message.trainingInputs),
      predictedFeatureName: message.predictedFeatureName,
      predictedProbabilitiesName: message.predictedProbabilitiesName,
      classLabels: message.classLabelStrings ?? message.classLabelInts,
      isUpdatable: message.isUpdatable,
      metadata: MLModelMetadata.fromMessage(message.metadata),
    );
  }

  /// The input features, by name.
  final Map<String, MLFeatureDescription> inputs;

  /// The output features, by name.
  final Map<String, MLFeatureDescription> outputs;

  /// The state buffers of a stateful model, by name.
  final Map<String, MLFeatureDescription> states;

  /// The training inputs of an updatable model, by name.
  final Map<String, MLFeatureDescription> trainingInputs;

  /// The output holding a classifier's predicted label, if any.
  final String? predictedFeatureName;

  /// The output holding a classifier's class probabilities, if any.
  final String? predictedProbabilitiesName;

  /// The class labels of a classifier: `String`s or `int`s.
  final List<Object>? classLabels;

  /// Whether the model supports on-device updates. core_ml does not bridge
  /// `MLUpdateTask`, so this is informational.
  final bool isUpdatable;

  /// The author, license, description, version and creator-defined values.
  final MLModelMetadata metadata;

  /// Whether the model has state buffers, so predictions need an `MLState`.
  bool get isStateful => states.isNotEmpty;

  @override
  String toString() =>
      'MLModelDescription(inputs: ${inputs.keys.toList()}, outputs: '
      '${outputs.keys.toList()}, states: ${states.keys.toList()})';
}

/// The author, license and other metadata stored in a model.
@immutable
final class MLModelMetadata {
  /// Creates metadata.
  MLModelMetadata({
    this.author,
    this.license,
    this.description,
    this.versionString,
    Map<String, String> creatorDefined = const {},
  }) : creatorDefined = Map.unmodifiable(creatorDefined);

  /// Converts from the Pigeon representation.
  factory MLModelMetadata.fromMessage(ModelMetadataMessage message) =>
      MLModelMetadata(
        author: message.author,
        license: message.license,
        description: message.modelDescription,
        versionString: message.versionString,
        creatorDefined: message.creatorDefined,
      );

  /// `MLModelAuthorKey`.
  final String? author;

  /// `MLModelLicenseKey`.
  final String? license;

  /// `MLModelDescriptionKey`, the model's short description.
  final String? description;

  /// `MLModelVersionStringKey`.
  final String? versionString;

  /// `MLModelCreatorDefinedKey`, flattened to strings.
  final Map<String, String> creatorDefined;

  @override
  String toString() =>
      'MLModelMetadata(author: $author, license: $license, description: '
      '$description, versionString: $versionString)';
}

/// One input, output or state of a model (`MLFeatureDescription`).
@immutable
final class MLFeatureDescription {
  /// Creates a feature description.
  const MLFeatureDescription({
    required this.name,
    required this.type,
    required this.isOptional,
    this.multiArrayConstraint,
    this.imageConstraint,
    this.dictionaryConstraint,
    this.sequenceConstraint,
    this.stateConstraint,
  });

  /// Converts from the Pigeon representation.
  factory MLFeatureDescription.fromMessage(FeatureDescriptionMessage message) =>
      MLFeatureDescription(
        name: message.name,
        type: MLFeatureType.fromMessage(message.type),
        isOptional: message.optional,
        multiArrayConstraint: message.multiArrayConstraint == null
            ? null
            : MLMultiArrayConstraint.fromMessage(message.multiArrayConstraint!),
        imageConstraint: message.imageConstraint == null
            ? null
            : MLImageConstraint.fromMessage(message.imageConstraint!),
        dictionaryConstraint: message.dictionaryConstraint == null
            ? null
            : MLDictionaryConstraint(
                keyType: MLFeatureType.fromMessage(
                  message.dictionaryConstraint!.keyType,
                ),
              ),
        sequenceConstraint: message.sequenceConstraint == null
            ? null
            : MLSequenceConstraint(
                valueType: MLFeatureType.fromMessage(
                  message.sequenceConstraint!.valueType,
                ),
                minimumCount: message.sequenceConstraint!.minimumCount,
                maximumCount: message.sequenceConstraint!.maximumCount,
              ),
        stateConstraint: message.stateConstraint == null
            ? null
            : MLStateConstraint(
                dataType: MLMultiArrayDataType.fromMessage(
                  message.stateConstraint!.dataType,
                ),
                bufferShape: message.stateConstraint!.bufferShape,
              ),
      );

  /// The feature name.
  final String name;

  /// The feature type.
  final MLFeatureType type;

  /// Whether the model accepts the feature being left undefined.
  final bool isOptional;

  /// Set for [MLFeatureType.multiArray] features.
  final MLMultiArrayConstraint? multiArrayConstraint;

  /// Set for [MLFeatureType.image] features.
  final MLImageConstraint? imageConstraint;

  /// Set for [MLFeatureType.dictionary] features.
  final MLDictionaryConstraint? dictionaryConstraint;

  /// Set for [MLFeatureType.sequence] features.
  final MLSequenceConstraint? sequenceConstraint;

  /// Set for [MLFeatureType.state] features.
  final MLStateConstraint? stateConstraint;

  @override
  String toString() => 'MLFeatureDescription($name: ${type.name})';
}

/// The shape and element type a multi-array feature accepts
/// (`MLMultiArrayConstraint`).
@immutable
final class MLMultiArrayConstraint {
  /// Creates a constraint.
  MLMultiArrayConstraint({
    required this.dataType,
    required List<int> shape,
    required this.shapeConstraintType,
    List<List<int>> enumeratedShapes = const [],
    List<int> minimumSizes = const [],
    List<int> maximumSizes = const [],
  }) : shape = List.unmodifiable(shape),
       enumeratedShapes = List.unmodifiable(
         enumeratedShapes.map(List<int>.unmodifiable),
       ),
       minimumSizes = List.unmodifiable(minimumSizes),
       maximumSizes = List.unmodifiable(maximumSizes);

  /// Converts from the Pigeon representation.
  factory MLMultiArrayConstraint.fromMessage(
    MultiArrayConstraintMessage message,
  ) => MLMultiArrayConstraint(
    dataType: MLMultiArrayDataType.fromMessage(message.dataType),
    shape: message.shape,
    shapeConstraintType:
        MLShapeConstraintType.values[message.shapeConstraintType.index],
    enumeratedShapes: [
      for (final shape in message.enumeratedShapes) shape.dimensions,
    ],
    minimumSizes: message.minimumSizes,
    maximumSizes: message.maximumSizes,
  );

  /// The element type.
  final MLMultiArrayDataType dataType;

  /// The default shape.
  final List<int> shape;

  /// How the shape may vary.
  final MLShapeConstraintType shapeConstraintType;

  /// The allowed shapes, for [MLShapeConstraintType.enumerated].
  final List<List<int>> enumeratedShapes;

  /// Per-dimension lower bounds, for [MLShapeConstraintType.range].
  final List<int> minimumSizes;

  /// Per-dimension upper bounds; `-1` means unbounded.
  final List<int> maximumSizes;

  @override
  String toString() => 'MLMultiArrayConstraint(${dataType.name}, $shape)';
}

/// The size and pixel format an image feature accepts
/// (`MLImageConstraint`).
@immutable
final class MLImageConstraint {
  /// Creates a constraint.
  MLImageConstraint({
    required this.pixelsWide,
    required this.pixelsHigh,
    required this.pixelFormatType,
    required this.sizeConstraintType,
    List<MLImageSize> enumeratedSizes = const [],
    this.minimumWidth = 0,
    this.maximumWidth = -1,
    this.minimumHeight = 0,
    this.maximumHeight = -1,
  }) : enumeratedSizes = List.unmodifiable(enumeratedSizes);

  /// Converts from the Pigeon representation.
  factory MLImageConstraint.fromMessage(ImageConstraintMessage message) =>
      MLImageConstraint(
        pixelsWide: message.pixelsWide,
        pixelsHigh: message.pixelsHigh,
        pixelFormatType: message.pixelFormatType,
        sizeConstraintType:
            MLImageSizeConstraintType.values[message.sizeConstraintType.index],
        enumeratedSizes: [
          for (final size in message.enumeratedSizes)
            MLImageSize(width: size.width, height: size.height),
        ],
        minimumWidth: message.minimumWidth,
        maximumWidth: message.maximumWidth,
        minimumHeight: message.minimumHeight,
        maximumHeight: message.maximumHeight,
      );

  /// The default width.
  final int pixelsWide;

  /// The default height.
  final int pixelsHigh;

  /// The Core Video pixel format (see `PixelFormat`).
  final int pixelFormatType;

  /// How the size may vary.
  final MLImageSizeConstraintType sizeConstraintType;

  /// The allowed sizes, for [MLImageSizeConstraintType.enumerated].
  final List<MLImageSize> enumeratedSizes;

  /// The smallest allowed width, for [MLImageSizeConstraintType.range].
  final int minimumWidth;

  /// The largest allowed width; `-1` means unbounded.
  final int maximumWidth;

  /// The smallest allowed height, for [MLImageSizeConstraintType.range].
  final int minimumHeight;

  /// The largest allowed height; `-1` means unbounded.
  final int maximumHeight;

  @override
  String toString() => 'MLImageConstraint(${pixelsWide}x$pixelsHigh)';
}

/// A width and height (`MLImageSize`).
@immutable
final class MLImageSize {
  /// Creates a size.
  const MLImageSize({required this.width, required this.height});

  /// The width in pixels.
  final int width;

  /// The height in pixels.
  final int height;

  @override
  bool operator ==(Object other) =>
      other is MLImageSize && other.width == width && other.height == height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => '${width}x$height';
}

/// The key type a dictionary feature accepts (`MLDictionaryConstraint`).
@immutable
final class MLDictionaryConstraint {
  /// Creates a constraint.
  const MLDictionaryConstraint({required this.keyType});

  /// [MLFeatureType.string] or [MLFeatureType.int64].
  final MLFeatureType keyType;

  @override
  String toString() => 'MLDictionaryConstraint(${keyType.name})';
}

/// The element type and length a sequence feature accepts
/// (`MLSequenceConstraint`).
@immutable
final class MLSequenceConstraint {
  /// Creates a constraint.
  const MLSequenceConstraint({
    required this.valueType,
    required this.minimumCount,
    required this.maximumCount,
  });

  /// [MLFeatureType.string] or [MLFeatureType.int64].
  final MLFeatureType valueType;

  /// The smallest allowed length.
  final int minimumCount;

  /// The largest allowed length; `-1` means unbounded.
  final int maximumCount;

  @override
  String toString() =>
      'MLSequenceConstraint(${valueType.name}, $minimumCount..$maximumCount)';
}

/// The shape and element type of a state buffer (`MLStateConstraint`).
@immutable
final class MLStateConstraint {
  /// Creates a constraint.
  MLStateConstraint({required this.dataType, required List<int> bufferShape})
    : bufferShape = List.unmodifiable(bufferShape);

  /// The element type, usually [MLMultiArrayDataType.float16].
  final MLMultiArrayDataType dataType;

  /// The shape of the state buffer.
  final List<int> bufferShape;

  @override
  String toString() => 'MLStateConstraint(${dataType.name}, $bufferShape)';
}
