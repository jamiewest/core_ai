/// Flutter bindings for Apple's Core ML framework (iOS 18+ / macOS 15+):
/// compile and load `.mlmodel` / `.mlpackage` models and run predictions.
///
/// * Compile and load models with [MLModel], configured by
///   [MLModelConfiguration].
/// * Inspect inputs, outputs, states and metadata with [MLModelDescription].
/// * Predict with [MLFeatureValue]s: [MLMultiArray]s, images ([ImageInput],
///   [PixelBuffer]), strings, numbers, dictionaries and sequences.
/// * Keep state across predictions of a stateful model with [MLState].
///
/// ```dart
/// if (!await CoreML.isSupported()) return;
/// final model = await MLModel.loadAsset('assets/models/affine.mlpackage');
/// final prediction = await model.predict({
///   'x': MLMultiArray.float32([1, 2, 3]),
/// });
/// print(prediction.multiArray('y').toDoubleList());
/// await model.dispose();
/// ```
library;

export 'src/configuration.dart';
export 'src/core_ml.dart';
export 'src/description.dart';
export 'src/errors.dart' show CoreMLErrorCode, CoreMLException;
export 'src/model.dart' hide resolveAssetPath;
export 'src/native_resource.dart' show NativeResource;
export 'src/types.dart';
export 'src/values.dart' hide featureValueFromMessage;
