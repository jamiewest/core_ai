// Pigeon schema for the core_ml plugin.
//
// Regenerate with:
//   dart run pigeon --input pigeons/core_ml_api.dart
//   dart format lib/src/messages.g.dart
//
// Wire-format conventions:
// * `MLModel` and `MLState` objects live in the plugin's handle registry and
//   are referenced by an opaque `int`. Everything else travels by value.
// * `MLMultiArray` data travels as raw little-endian storage bytes plus the
//   data type, shape and element strides, so non-contiguous arrays (such as
//   float16 outputs backed by a padded `CVPixelBuffer`) survive the trip.
// * Images travel either as `CVPixelBuffer` planes or, for inputs, as encoded
//   image bytes/a file path that the native side decodes and resizes to the
//   feature's `MLImageConstraint`.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'darwin/core_ml/Sources/core_ml/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'CoreMLPigeonError'),
    dartPackageName: 'core_ml',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------
/// Mirrors `MLComputeUnits`.
enum ComputeUnitsMessage { cpuOnly, cpuAndGpu, all, cpuAndNeuralEngine }

/// Mirrors `MLMultiArrayDataType`. The order matches the public Dart enum.
enum MultiArrayDataTypeMessage { float16, float32, float64, int32, int8 }

/// Mirrors `MLFeatureType`. The order matches the public Dart enum.
enum FeatureTypeMessage {
  invalid,
  int64,
  float64,
  string,
  image,
  multiArray,
  dictionary,
  sequence,
  state,
}

/// Mirrors `MLOptimizationHints.ReshapeFrequency`.
enum ReshapeFrequencyMessage { frequent, infrequent }

/// Mirrors `MLOptimizationHints.SpecializationStrategy`.
enum SpecializationStrategyMessage { defaults, fastPrediction }

/// Mirrors `MLMultiArrayShapeConstraintType`.
enum ShapeConstraintTypeMessage { unspecified, enumerated, range }

/// Mirrors `MLImageSizeConstraintType`.
enum ImageSizeConstraintTypeMessage { unspecified, enumerated, range }

/// Which case of `MLComputeDevice` a device is.
enum ComputeDeviceKindMessage { cpu, gpu, neuralEngine }

/// Encoded image formats for pixel-buffer export.
enum ImageEncodingMessage { png, jpeg }

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

/// Mirrors `MLModelConfiguration`.
class ModelConfigurationMessage {
  ModelConfigurationMessage({
    required this.computeUnits,
    required this.allowLowPrecisionAccumulationOnGPU,
    this.functionName,
    this.modelDisplayName,
    this.reshapeFrequency,
    this.specializationStrategy,
  });

  ComputeUnitsMessage computeUnits;
  bool allowLowPrecisionAccumulationOnGPU;

  /// Selects a function of a multi-function model (iOS 18 / macOS 15).
  String? functionName;
  String? modelDisplayName;

  /// `MLOptimizationHints.reshapeFrequency`, left alone when null.
  ReshapeFrequencyMessage? reshapeFrequency;

  /// `MLOptimizationHints.specializationStrategy`, left alone when null.
  SpecializationStrategyMessage? specializationStrategy;
}

// ---------------------------------------------------------------------------
// Descriptions
// ---------------------------------------------------------------------------

/// One multi-array shape, so nested lists stay off the wire.
class ShapeMessage {
  ShapeMessage({required this.dimensions});

  List<int> dimensions;
}

/// A width/height pair from `MLImageSize`.
class ImageSizeMessage {
  ImageSizeMessage({required this.width, required this.height});

  int width;
  int height;
}

/// Mirrors `MLMultiArrayConstraint` and its `MLMultiArrayShapeConstraint`.
class MultiArrayConstraintMessage {
  MultiArrayConstraintMessage({
    required this.dataType,
    required this.shape,
    required this.shapeConstraintType,
    required this.enumeratedShapes,
    required this.minimumSizes,
    required this.maximumSizes,
  });

  MultiArrayDataTypeMessage dataType;
  List<int> shape;
  ShapeConstraintTypeMessage shapeConstraintType;

  /// Non-empty for [ShapeConstraintTypeMessage.enumerated].
  List<ShapeMessage> enumeratedShapes;

  /// Per-dimension lower bounds for [ShapeConstraintTypeMessage.range].
  List<int> minimumSizes;

  /// Per-dimension upper bounds; `-1` means unbounded.
  List<int> maximumSizes;
}

/// Mirrors `MLImageConstraint` and its `MLImageSizeConstraint`.
class ImageConstraintMessage {
  ImageConstraintMessage({
    required this.pixelsWide,
    required this.pixelsHigh,
    required this.pixelFormatType,
    required this.sizeConstraintType,
    required this.enumeratedSizes,
    required this.minimumWidth,
    required this.maximumWidth,
    required this.minimumHeight,
    required this.maximumHeight,
  });

  int pixelsWide;
  int pixelsHigh;
  int pixelFormatType;
  ImageSizeConstraintTypeMessage sizeConstraintType;
  List<ImageSizeMessage> enumeratedSizes;
  int minimumWidth;

  /// `-1` means unbounded.
  int maximumWidth;
  int minimumHeight;

  /// `-1` means unbounded.
  int maximumHeight;
}

/// Mirrors `MLDictionaryConstraint`.
class DictionaryConstraintMessage {
  DictionaryConstraintMessage({required this.keyType});

  FeatureTypeMessage keyType;
}

/// Mirrors `MLSequenceConstraint`.
class SequenceConstraintMessage {
  SequenceConstraintMessage({
    required this.valueType,
    required this.minimumCount,
    required this.maximumCount,
  });

  FeatureTypeMessage valueType;
  int minimumCount;
  int maximumCount;
}

/// Mirrors `MLStateConstraint`.
class StateConstraintMessage {
  StateConstraintMessage({required this.dataType, required this.bufferShape});

  MultiArrayDataTypeMessage dataType;
  List<int> bufferShape;
}

/// Mirrors `MLFeatureDescription`.
class FeatureDescriptionMessage {
  FeatureDescriptionMessage({
    required this.name,
    required this.type,
    required this.optional,
    this.multiArrayConstraint,
    this.imageConstraint,
    this.dictionaryConstraint,
    this.sequenceConstraint,
    this.stateConstraint,
  });

  String name;
  FeatureTypeMessage type;
  bool optional;
  MultiArrayConstraintMessage? multiArrayConstraint;
  ImageConstraintMessage? imageConstraint;
  DictionaryConstraintMessage? dictionaryConstraint;
  SequenceConstraintMessage? sequenceConstraint;
  StateConstraintMessage? stateConstraint;
}

/// The `metadata` dictionary of an `MLModelDescription`.
class ModelMetadataMessage {
  ModelMetadataMessage({
    this.author,
    this.license,
    this.modelDescription,
    this.versionString,
    required this.creatorDefined,
  });

  String? author;
  String? license;

  /// `MLModelDescriptionKey`.
  String? modelDescription;
  String? versionString;

  /// `MLModelCreatorDefinedKey`, flattened to strings.
  Map<String, String> creatorDefined;
}

/// Mirrors `MLModelDescription`.
class ModelDescriptionMessage {
  ModelDescriptionMessage({
    required this.inputs,
    required this.outputs,
    required this.states,
    required this.trainingInputs,
    this.predictedFeatureName,
    this.predictedProbabilitiesName,
    this.classLabelStrings,
    this.classLabelInts,
    required this.isUpdatable,
    required this.metadata,
  });

  List<FeatureDescriptionMessage> inputs;
  List<FeatureDescriptionMessage> outputs;
  List<FeatureDescriptionMessage> states;
  List<FeatureDescriptionMessage> trainingInputs;
  String? predictedFeatureName;
  String? predictedProbabilitiesName;

  /// Set when the model has string class labels.
  List<String>? classLabelStrings;

  /// Set when the model has int64 class labels.
  List<int>? classLabelInts;
  bool isUpdatable;
  ModelMetadataMessage metadata;
}

/// A loaded `MLModel`.
class ModelInfoMessage {
  ModelInfoMessage({
    required this.handle,
    required this.modelDescription,
    required this.configuration,
  });

  int handle;
  ModelDescriptionMessage modelDescription;

  /// The configuration Core ML actually used.
  ModelConfigurationMessage configuration;
}

// ---------------------------------------------------------------------------
// Feature values
// ---------------------------------------------------------------------------

/// Any `MLFeatureValue`.
sealed class FeatureValueMessage {}

/// An `MLMultiArray`, transferred by value as raw storage bytes.
class MultiArrayMessage extends FeatureValueMessage {
  MultiArrayMessage({
    required this.dataType,
    required this.shape,
    required this.strides,
    required this.data,
  });

  MultiArrayDataTypeMessage dataType;
  List<int> shape;

  /// Element strides, same length as [shape]. Empty means row-major
  /// contiguous.
  List<int> strides;

  /// The raw backing storage.
  Uint8List data;
}

/// One plane of a [PixelBufferMessage].
class PixelBufferPlaneMessage {
  PixelBufferPlaneMessage({
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.data,
  });

  int width;
  int height;
  int bytesPerRow;
  Uint8List data;
}

/// A `CVPixelBuffer` image feature, transferred by value.
class PixelBufferMessage extends FeatureValueMessage {
  PixelBufferMessage({
    required this.width,
    required this.height,
    required this.pixelFormatType,
    required this.planes,
  });

  int width;
  int height;
  int pixelFormatType;
  List<PixelBufferPlaneMessage> planes;
}

/// An image input given as encoded bytes or a file path. The native side
/// decodes it and resizes it to the feature's `MLImageConstraint` unless
/// [width], [height] or [pixelFormatType] override it.
class EncodedImageMessage extends FeatureValueMessage {
  EncodedImageMessage({
    this.bytes,
    this.path,
    this.width,
    this.height,
    this.pixelFormatType,
  });

  Uint8List? bytes;
  String? path;
  int? width;
  int? height;
  int? pixelFormatType;
}

/// An `MLFeatureValue` holding a string.
class StringValueMessage extends FeatureValueMessage {
  StringValueMessage({required this.value});

  String value;
}

/// An `MLFeatureValue` holding an int64.
class Int64ValueMessage extends FeatureValueMessage {
  Int64ValueMessage({required this.value});

  int value;
}

/// An `MLFeatureValue` holding a double.
class DoubleValueMessage extends FeatureValueMessage {
  DoubleValueMessage({required this.value});

  double value;
}

/// An `MLFeatureValue` holding a dictionary. Exactly one map is set.
class DictionaryValueMessage extends FeatureValueMessage {
  DictionaryValueMessage({this.stringKeyed, this.int64Keyed});

  Map<String, double>? stringKeyed;
  Map<int, double>? int64Keyed;
}

/// An `MLSequence`. Exactly one list is set.
class SequenceValueMessage extends FeatureValueMessage {
  SequenceValueMessage({this.strings, this.int64s});

  List<String>? strings;
  List<int>? int64s;
}

/// An undefined `MLFeatureValue` of a given type, used for optional inputs.
class UndefinedValueMessage extends FeatureValueMessage {
  UndefinedValueMessage({required this.featureType});

  FeatureTypeMessage featureType;
}

// ---------------------------------------------------------------------------
// Prediction
// ---------------------------------------------------------------------------

/// A named set of feature values, so nested maps stay off the wire.
class FeatureMapMessage {
  FeatureMapMessage({required this.features});

  Map<String, FeatureValueMessage> features;
}

class PredictionRequestMessage {
  PredictionRequestMessage({
    required this.modelHandle,
    required this.inputs,
    this.stateHandle,
  });

  int modelHandle;
  Map<String, FeatureValueMessage> inputs;

  /// An `MLState` handle for a stateful model.
  int? stateHandle;
}

class PredictionResultMessage {
  PredictionResultMessage({required this.outputs});

  Map<String, FeatureValueMessage> outputs;
}

class BatchPredictionRequestMessage {
  BatchPredictionRequestMessage({
    required this.modelHandle,
    required this.inputs,
  });

  int modelHandle;
  List<FeatureMapMessage> inputs;
}

class BatchPredictionResultMessage {
  BatchPredictionResultMessage({required this.outputs});

  List<FeatureMapMessage> outputs;
}

// ---------------------------------------------------------------------------
// Compute devices
// ---------------------------------------------------------------------------

/// Mirrors a case of `MLComputeDevice`.
class ComputeDeviceMessage {
  ComputeDeviceMessage({
    required this.kind,
    required this.name,
    this.neuralEngineCoreCount,
    this.metalDeviceName,
  });

  ComputeDeviceKindMessage kind;
  String name;
  int? neuralEngineCoreCount;
  String? metalDeviceName;
}

// ---------------------------------------------------------------------------
// APIs
// ---------------------------------------------------------------------------

/// Always available, on every OS version.
@HostApi()
abstract class CoreMLPlatformApi {
  /// Whether this plugin's Core ML surface is available
  /// (iOS 18+ / macOS 15+).
  bool isSupported();

  /// The OS name and version, for diagnostics.
  String platformVersion();

  /// The absolute on-disk path of a Flutter asset (file or directory, such as
  /// a bundled `.mlpackage`), or null if it is not in the app bundle.
  String? assetPath(String assetKey, String? package);
}

/// Only registered when Core ML's iOS 18 / macOS 15 surface is available.
@HostApi()
abstract class CoreMLHostApi {
  // -- Compilation ----------------------------------------------------------
  /// `MLModel.compileModel(at:)`. Compiles a `.mlmodel` or `.mlpackage` to a
  /// `.mlmodelc` directory. When [destinationPath] is given the result is
  /// moved there (replacing anything already at that path) and that path is
  /// returned; otherwise Core ML's temporary path is returned.
  @async
  String compileModel(String path, String? destinationPath);

  // -- Model assets ---------------------------------------------------------
  /// `MLModelAsset.functionNames` for a compiled model.
  @async
  List<String> functionNames(String compiledPath);

  /// `MLModelAsset.modelDescription`, optionally of one function.
  @async
  ModelDescriptionMessage assetModelDescription(
    String compiledPath,
    String? functionName,
  );

  // -- Models ---------------------------------------------------------------
  /// `MLModel.load(contentsOf:configuration:)`.
  @async
  ModelInfoMessage loadModel(
    String compiledPath,
    ModelConfigurationMessage configuration,
  );

  /// `MLModel.prediction(from:options:)`, or `prediction(from:using:options:)`
  /// when the request carries a state handle.
  @async
  PredictionResultMessage predict(PredictionRequestMessage request);

  /// `MLModel.predictions(from:options:)`.
  @async
  BatchPredictionResultMessage predictBatch(
    BatchPredictionRequestMessage request,
  );

  // -- State ----------------------------------------------------------------
  /// `MLModel.makeState()`.
  int makeState(int modelHandle);

  /// Copies a state buffer into Dart (`MLState.withMultiArray(for:)`).
  @async
  MultiArrayMessage readState(int stateHandle, String stateName);

  /// Overwrites a state buffer. The data type and shape must match.
  @async
  void writeState(int stateHandle, String stateName, MultiArrayMessage array);

  // -- Compute devices ------------------------------------------------------
  /// `MLModel.availableComputeDevices`.
  List<ComputeDeviceMessage> availableComputeDevices();

  /// `MLComputeDevice.allComputeDevices`.
  List<ComputeDeviceMessage> allComputeDevices();

  // -- Images ---------------------------------------------------------------
  /// Encodes an image feature value as PNG or JPEG, for display in Dart.
  @async
  Uint8List encodeImage(
    PixelBufferMessage image,
    ImageEncodingMessage encoding,
    double quality,
  );

  // -- Handles --------------------------------------------------------------
  /// Releases a model or state handle.
  @async
  void release(int handle);

  /// Releases every handle owned by this engine. Returns how many were freed.
  @async
  int releaseAll();

  int liveHandleCount();
}
