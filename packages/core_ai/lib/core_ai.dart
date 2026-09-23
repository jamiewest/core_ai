/// Flutter bindings for Apple's Core AI framework (iOS 27+ / macOS 27+).
///
/// * Load and specialize `.aimodel` files with [AIModel], manage the
///   specialized-model cache with [AIModelCache].
/// * Inspect functions with [FunctionDescriptor], and run them with
///   [InferenceFunction.run] on [NDArray]s, [PixelBuffer]s and
///   [NativeValue]s.
/// * Keep state (such as key-value caches) on the native side with
///   [InferenceState], and pipeline work on a [ComputeStream].
/// * Read and edit model metadata with [AIModelAsset].
///
/// ```dart
/// if (!await CoreAI.isSupported()) return;
/// final model = await AIModel.loadAsset('assets/Model.aimodel');
/// final function = await model.loadFunction('main');
/// final outputs = await function.run({'x': NDArray.float32([1, 2, 3])});
/// print(outputs.ndArray('y').toDoubleList());
/// ```
library;

export 'src/asset.dart';
export 'src/core_ai.dart';
export 'src/descriptors.dart';
export 'src/errors.dart' show CoreAIErrorCode, CoreAIException;
export 'src/model.dart' hide resolveAssetPath;
export 'src/native_resource.dart' show NativeResource;
export 'src/scalar_type.dart' show ScalarType;
export 'src/specialization.dart';
export 'src/values.dart'
    hide adoptNativeValue, valueFromMessage, valueToMessage;
