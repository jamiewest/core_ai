// Pigeon schema for the core_ai plugin.
//
// Regenerate with:
//   dart run pigeon --input pigeons/core_ai_api.dart
//
// Wire-format conventions:
// * Every native object (model, function, native value, compute stream, async
//   value) is referenced by an opaque `int` handle owned by the plugin's
//   registry. Handles are released explicitly via `CoreAIHostApi.release`.
// * NDArray data always travels as raw storage bytes plus scalar type, shape,
//   strides and interleave layout, so every Core AI scalar type (including
//   sub-byte integer and fp8/fp4 types) round-trips without loss.
// * Pixel buffers travel as a list of planes with their row strides.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'darwin/core_ai/Sources/core_ai/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'CoreAIPigeonError'),
    dartPackageName: 'core_ai',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------
/// Mirrors `ComputeUnitKind`.
enum ComputeUnitKindMessage { cpu, gpu, neuralEngine }

/// Mirrors `NDArray.ScalarType`. Order is significant: it is kept identical to
/// the public Dart `ScalarType` enum.
enum ScalarTypeMessage {
  boolean,
  int2,
  int3,
  int4,
  int5,
  int6,
  int7,
  int8,
  int16,
  int32,
  int64,
  int128,
  uint1,
  uint2,
  uint3,
  uint4,
  uint5,
  uint6,
  uint7,
  uint8,
  uint16,
  uint32,
  uint64,
  uint128,
  float8e5m2,
  float8e4m3fn,
  float8e8m0fn,
  float4e2m1fn,
  float16,
  float32,
  float64,
  bfloat16,
  cfloat16,
  cfloat32,
  cfloat64,
}

/// Mirrors `InferenceValue.Kind`, plus the async variants used by compute
/// streams.
enum ValueKindMessage { ndArray, image, asyncValue, asyncMutableValue }

/// Which argument list of a function a value belongs to.
enum ValueRoleMessage { input, state, output }

/// Presets of `SpecializationOptions`.
enum SpecializationPresetMessage { defaults, cpuOnly, preferred }

/// Encoded image formats for pixel-buffer export.
enum ImageEncodingMessage { png, jpeg }

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------
class SpecializationOptionsMessage {
  SpecializationOptionsMessage({
    required this.preset,
    this.preferredComputeUnitKind,
    required this.expectFrequentReshapes,
  });

  SpecializationPresetMessage preset;

  /// Required when [preset] is `preferred`.
  ComputeUnitKindMessage? preferredComputeUnitKind;
  bool expectFrequentReshapes;
}

class SpecializationInfoMessage {
  SpecializationInfoMessage({
    required this.allowedComputeUnitKinds,
    this.preferredComputeUnitKind,
    required this.expectFrequentReshapes,
  });

  List<ComputeUnitKindMessage> allowedComputeUnitKinds;
  ComputeUnitKindMessage? preferredComputeUnitKind;
  bool expectFrequentReshapes;
}

/// Identifies an `AIModelCache`: the app's default cache when
/// [appGroupIdentifier] is null, otherwise the shared app-group cache.
class ModelCacheMessage {
  ModelCacheMessage({this.appGroupIdentifier});

  String? appGroupIdentifier;
}

/// Mirrors `AIModelCache.Policy`.
class CachePolicyMessage {
  CachePolicyMessage({
    required this.purgeOnStoragePressure,
    required this.purgeOnSourceAssetChangedOrDeleted,
  });

  bool purgeOnStoragePressure;
  bool purgeOnSourceAssetChangedOrDeleted;
}

// ---------------------------------------------------------------------------
// Descriptors
// ---------------------------------------------------------------------------
class InterleaveLayoutMessage {
  InterleaveLayoutMessage({required this.dimension, required this.factor});

  int dimension;
  int factor;
}

/// Mirrors `NDArrayDescriptor`. [preferredStrides] and [minimumByteCount] are
/// only present when the shape is fully static.
class NDArrayDescriptorMessage {
  NDArrayDescriptorMessage({
    required this.scalarType,
    required this.shape,
    required this.hasDynamicShape,
    this.interleaveLayout,
    this.preferredStrides,
    this.minimumByteCount,
  });

  ScalarTypeMessage scalarType;
  List<int> shape;
  bool hasDynamicShape;
  InterleaveLayoutMessage? interleaveLayout;
  List<int>? preferredStrides;
  int? minimumByteCount;
}

/// Mirrors `ImageDescriptor`. `-1` in width/height means dynamic.
class ImageDescriptorMessage {
  ImageDescriptorMessage({
    required this.width,
    required this.height,
    required this.pixelFormatType,
  });

  int width;
  int height;
  int pixelFormatType;
}

/// A named `InferenceValue.Descriptor`. Exactly one of [ndArray] / [image] is
/// set, according to [kind].
class ValueDescriptorMessage {
  ValueDescriptorMessage({
    required this.name,
    required this.kind,
    this.ndArray,
    this.image,
  });

  String name;
  ValueKindMessage kind;
  NDArrayDescriptorMessage? ndArray;
  ImageDescriptorMessage? image;
}

/// Mirrors `InferenceFunctionDescriptor`.
class FunctionDescriptorMessage {
  FunctionDescriptorMessage({
    required this.name,
    required this.inputs,
    required this.states,
    required this.outputs,
  });

  String name;
  List<ValueDescriptorMessage> inputs;
  List<ValueDescriptorMessage> states;
  List<ValueDescriptorMessage> outputs;
}

class ModelInfoMessage {
  ModelInfoMessage({required this.handle, required this.functionNames});

  int handle;
  List<String> functionNames;
}

class FunctionInfoMessage {
  FunctionInfoMessage({required this.handle, required this.descriptor});

  int handle;
  FunctionDescriptorMessage descriptor;
}

// ---------------------------------------------------------------------------
// Values
// ---------------------------------------------------------------------------

/// Any value that can be passed to, or returned from, an inference function.
sealed class ValueMessage {}

/// An NDArray, transferred by value.
class NDArrayMessage extends ValueMessage {
  NDArrayMessage({
    required this.scalarType,
    required this.shape,
    required this.strides,
    this.interleaveLayout,
    required this.data,
  });

  ScalarTypeMessage scalarType;
  List<int> shape;

  /// Element strides, same length as [shape]. Empty means row-major
  /// contiguous.
  List<int> strides;
  InterleaveLayoutMessage? interleaveLayout;

  /// The raw backing storage.
  Uint8List data;
}

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

/// A `CVPixelBuffer`, transferred by value. Non-planar formats have exactly
/// one plane.
class PixelBufferMessage extends ValueMessage {
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

/// A reference to a value that lives in the native registry (an NDArray,
/// pixel buffer, compute-stream async value or async mutable value).
class NativeValueRefMessage extends ValueMessage {
  NativeValueRefMessage({required this.handle});

  int handle;
}

/// Metadata about a native value, without its contents.
class NativeValueInfoMessage {
  NativeValueInfoMessage({
    required this.handle,
    required this.kind,
    this.scalarType,
    this.shape,
    this.strides,
    this.interleaveLayout,
    this.byteCount,
    this.width,
    this.height,
    this.pixelFormatType,
  });

  int handle;
  ValueKindMessage kind;
  ScalarTypeMessage? scalarType;
  List<int>? shape;
  List<int>? strides;
  InterleaveLayoutMessage? interleaveLayout;
  int? byteCount;
  int? width;
  int? height;
  int? pixelFormatType;
}

// ---------------------------------------------------------------------------
// Inference
// ---------------------------------------------------------------------------
class RunRequestMessage {
  RunRequestMessage({
    required this.functionHandle,
    required this.inputs,
    required this.states,
    required this.outputViews,
    required this.retainedOutputs,
    required this.retainAllOutputs,
  });

  int functionHandle;

  /// Values may be NDArrays, pixel buffers or native value references.
  Map<String, ValueMessage> inputs;

  /// State name -> native value handle. Updated in place.
  Map<String, int> states;

  /// Output name -> native value handle. Updated in place; not returned.
  Map<String, int> outputViews;

  /// Outputs to keep on the native side (returned as [NativeValueRefMessage]).
  List<String> retainedOutputs;
  bool retainAllOutputs;
}

class RunResultMessage {
  RunResultMessage({required this.outputs});

  /// NDArrayMessage / PixelBufferMessage / NativeValueRefMessage.
  Map<String, ValueMessage> outputs;
}

class EncodeRequestMessage {
  EncodeRequestMessage({
    required this.functionHandle,
    required this.streamHandle,
    required this.inputs,
    required this.states,
    required this.outputViews,
  });

  int functionHandle;
  int streamHandle;

  /// Values may be NDArrays, pixel buffers or native value references
  /// (including async values produced by earlier encodes).
  Map<String, ValueMessage> inputs;

  /// State name -> native value handle (converted to an async mutable value).
  Map<String, int> states;

  /// Output name -> native value handle (converted to an async mutable value).
  Map<String, int> outputViews;
}

// ---------------------------------------------------------------------------
// Assets
// ---------------------------------------------------------------------------
class AssetMetadataMessage {
  AssetMetadataMessage({
    required this.author,
    required this.license,
    required this.modelDescription,
    this.creationDateMillis,
    required this.creatorDefined,
  });

  String author;
  String license;
  String modelDescription;
  int? creationDateMillis;

  /// Values are String, int, double, bool, List or Map (recursively).
  Map<String, Object?> creatorDefined;
}

/// Fields that are null are left unchanged. Keys in [creatorDefinedRemovals]
/// are removed; [creatorDefined] entries are inserted or replaced.
class AssetMetadataUpdateMessage {
  AssetMetadataUpdateMessage({
    this.author,
    this.license,
    this.modelDescription,
    this.creationDateMillis,
    required this.clearCreationDate,
    required this.creatorDefined,
    required this.creatorDefinedRemovals,
  });

  String? author;
  String? license;
  String? modelDescription;
  int? creationDateMillis;
  bool clearCreationDate;
  Map<String, Object?> creatorDefined;
  List<String> creatorDefinedRemovals;
}

class AssetValueDescriptorMessage {
  AssetValueDescriptorMessage({required this.name, required this.typeName});

  String name;
  String typeName;
}

class AssetFunctionDescriptorMessage {
  AssetFunctionDescriptorMessage({
    required this.name,
    required this.inputs,
    required this.states,
    required this.outputs,
  });

  String name;
  List<AssetValueDescriptorMessage> inputs;
  List<AssetValueDescriptorMessage> states;
  List<AssetValueDescriptorMessage> outputs;
}

class NamedCountMessage {
  NamedCountMessage({required this.name, required this.count});

  String name;
  int count;
}

class AssetSummaryMessage {
  AssetSummaryMessage({
    required this.functions,
    required this.storageTypes,
    required this.computeTypes,
    required this.operationDistribution,
  });

  List<AssetFunctionDescriptorMessage> functions;
  List<NamedCountMessage> storageTypes;
  List<String> computeTypes;
  List<NamedCountMessage> operationDistribution;
}

// ---------------------------------------------------------------------------
// APIs
// ---------------------------------------------------------------------------

/// Always available, on every OS version.
@HostApi()
abstract class CoreAIPlatformApi {
  /// Whether Core AI is available (iOS 27+ / macOS 27+).
  bool isSupported();

  /// The OS name and version, for diagnostics.
  String platformVersion();

  /// The absolute on-disk path of a Flutter asset (file or directory, such as
  /// a bundled `.aimodel` package), or null if it is not in the app bundle.
  String? assetPath(String assetKey, String? package);
}

/// Only registered when Core AI is available.
@HostApi()
abstract class CoreAIHostApi {
  // -- Device ---------------------------------------------------------------
  String deviceArchitectureName();
  List<ComputeUnitKindMessage> availableComputeUnitKinds();
  SpecializationInfoMessage describeSpecializationOptions(
    SpecializationOptionsMessage options,
  );

  // -- Models ---------------------------------------------------------------
  /// `AIModel(contentsOf:options:)`.
  @async
  ModelInfoMessage loadModel(String path, SpecializationOptionsMessage options);

  /// `AIModel.specialize(contentsOf:options:cache:cachePolicy:)`.
  @async
  ModelInfoMessage specializeModel(
    String path,
    SpecializationOptionsMessage options,
    ModelCacheMessage cache,
    CachePolicyMessage policy,
  );

  /// `AIModelCache.model(for:options:)`. Never specializes.
  @async
  ModelInfoMessage? cachedModel(
    String path,
    SpecializationOptionsMessage options,
    ModelCacheMessage cache,
  );

  /// `AIModel(resolvingBookmark:)`.
  @async
  ModelInfoMessage? modelFromBookmark(Uint8List bookmark);

  Uint8List modelBookmarkData(int modelHandle);

  FunctionDescriptorMessage? functionDescriptor(
    int modelHandle,
    String functionName,
  );

  /// `AIModel.loadFunction(named:)`. Returns null if there is no such function.
  @async
  FunctionInfoMessage? loadFunction(int modelHandle, String functionName);

  /// `NDArrayDescriptor.resolvingDynamicDimensions(_:)`.
  ///
  /// [ownerHandle] is a model handle (then [functionName] selects the
  /// function) or a function handle (then [functionName] is ignored).
  NDArrayDescriptorMessage resolveDynamicDimensions(
    int ownerHandle,
    String functionName,
    ValueRoleMessage role,
    String valueName,
    List<int> shape,
  );

  // -- Cache ----------------------------------------------------------------
  @async
  void deleteCacheEntry(
    String path,
    SpecializationOptionsMessage options,
    ModelCacheMessage cache,
  );
  @async
  void deleteCacheEntries(String path, ModelCacheMessage cache);
  @async
  void deleteAllCacheEntries(ModelCacheMessage cache);
  @async
  void deleteCacheEntryForBookmark(Uint8List bookmark);
  bool isCacheAvailable(ModelCacheMessage cache);

  // -- Inference --------------------------------------------------------------
  /// `InferenceFunction.run(inputs:states:outputViews:)`.
  @async
  RunResultMessage run(RunRequestMessage request);

  /// `InferenceFunction.encode(inputs:states:outputViews:to:)`. Returns
  /// native handles of `AsyncValue`s, keyed by output name.
  @async
  Map<String, int> encode(EncodeRequestMessage request);

  /// Creates a `ComputeStream` (on a new Metal command queue).
  int createComputeStream();

  /// `ComputeStream.currentWorkCompleted()`.
  @async
  void computeStreamCompleted(int streamHandle);

  // -- Native values ----------------------------------------------------------
  /// Copies [array] into a new native NDArray.
  @async
  int createNDArray(NDArrayMessage array);

  /// Allocates a zero-filled native NDArray.
  @async
  int allocateNDArray(
    ScalarTypeMessage scalarType,
    List<int> shape,
    List<int>? strides,
    InterleaveLayoutMessage? interleaveLayout,
  );

  /// Allocates a zero-filled native value matching a function argument's
  /// descriptor (preferred strides / interleave, or a pixel buffer of the
  /// described size and format). [shape] resolves dynamic NDArray dimensions;
  /// [width]/[height] resolve dynamic image sizes. [ownerHandle] is as in
  /// [resolveDynamicDimensions].
  @async
  int allocateForDescriptor(
    int ownerHandle,
    String functionName,
    ValueRoleMessage role,
    String valueName,
    List<int>? shape,
    int? width,
    int? height,
  );

  /// Copies [pixelBuffer] into a new native `CVPixelBuffer`.
  @async
  int createPixelBuffer(PixelBufferMessage pixelBuffer);

  /// Decodes an encoded image (PNG, JPEG, HEIC, ...), scales it to
  /// [width] x [height] (or keeps its size when null) and renders it into a new
  /// native `CVPixelBuffer` of [pixelFormatType].
  @async
  int createPixelBufferFromEncodedImage(
    Uint8List encoded,
    int pixelFormatType,
    int? width,
    int? height,
  );

  /// Returns the contents of a native value (awaiting async values), as an
  /// NDArrayMessage or PixelBufferMessage.
  @async
  ValueMessage readValue(int handle);

  /// Encodes a native pixel buffer (or image async value) as PNG/JPEG.
  @async
  Uint8List encodePixelBuffer(
    int handle,
    ImageEncodingMessage encoding,
    double quality,
  );

  /// Overwrites the contents of a native NDArray. Scalar type and shape must
  /// match.
  @async
  void writeNDArray(int handle, NDArrayMessage array);

  /// Zero-fills a native NDArray or pixel buffer.
  @async
  void zeroValue(int handle);

  /// Makes an independent native copy of a native value.
  @async
  int copyValue(int handle);

  @async
  NativeValueInfoMessage describeValue(int handle);

  // -- Handles ----------------------------------------------------------------
  /// Releases any handle (model, function, value, stream).
  ///
  /// Async so that freeing a function's weights happens off the platform
  /// thread.
  @async
  void release(int handle);

  /// Releases every handle owned by this engine. Returns how many were freed.
  @async
  int releaseAll();

  int liveHandleCount();

  // -- Assets -----------------------------------------------------------------
  bool isValidAsset(String path);

  @async
  AssetMetadataMessage assetMetadata(String path);

  @async
  AssetSummaryMessage? assetSummary(String path, bool includeStatistics);

  @async
  void updateAssetMetadata(String path, AssetMetadataUpdateMessage update);

  @async
  void removeAssetDerivedArtifacts(String path);
}
