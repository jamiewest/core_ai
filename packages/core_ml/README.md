# core_ml

Flutter bindings for Apple's Core ML framework on iOS and macOS, over Pigeon
platform channels: compile and load `.mlmodel` / `.mlpackage` models, inspect
their descriptions and run predictions on multi-arrays, images, strings,
numbers, dictionaries and sequences, including batch and stateful
predictions.

```dart
import 'package:core_ml/core_ml.dart';

if (!await CoreML.isSupported()) return;
final model = await MLModel.loadAsset('assets/models/affine.mlpackage');
final prediction = await model.predict({
  'x': MLMultiArray.float32([1, 2, 3]),
});
print(prediction.multiArray('y').toDoubleList()); // [3.0, 5.0, 7.0]
await model.dispose();
```

### core_ml and core_ai

Core ML and Core AI are different runtimes with different model formats:

* **core_ml** (this package) runs Core ML models, `.mlmodel` and
  `.mlpackage` files (compiled to `.mlmodelc`), which `coremltools` produces.
  It works from iOS 18 / macOS 15.
* **core_ai** (`packages/core_ai`) runs `.aimodel` files with Core AI, the
  successor runtime introduced in iOS 27 / macOS 27.

A Core ML model cannot be loaded by core_ai and vice versa. Use core_ml for
existing Core ML models or when you must support OS versions before 27.

## Requirements

* iOS 18+ or macOS 15+ at runtime. The plugin's deployment target stays at
  iOS 15 / macOS 12: on older systems `CoreML.isSupported()` returns false and
  every other call throws `CoreMLException(unsupported)`. The floor is iOS 18
  because `MLState`, multi-function models and strided `MLMultiArray`
  creation need it.
* `MLMultiArrayDataType.int8` arrays need iOS 26 / macOS 26.
* Flutter 3.38+, Dart 3.11+. A podspec and a `Package.swift` are provided
  (builds were verified with CocoaPods). Core ML is never listed as a linked
  framework; every use is behind `@available`, so it is weak-linked
  automatically.
* Verified on macOS 27 and on an iPhone running iOS 27.

## Quick start

1. Put the model in your app's assets. `.mlpackage` (and `.mlmodelc`) are
   directory trees and Flutter's asset directory entries are **not
   recursive**, so list every directory that holds files:

   ```yaml
   flutter:
     assets:
       - assets/models/MyModel.mlpackage/
       - assets/models/MyModel.mlpackage/Data/com.apple.CoreML/
       - assets/models/MyModel.mlpackage/Data/com.apple.CoreML/weights/
   ```

   Flutter never bundles empty directories. See
   [Known Core ML behavior](#known-core-ml-behavior) if your model has no
   weights.

2. Compile and load. Core ML only loads compiled `.mlmodelc` directories, so
   `loadAsset` compiles first. Pass `compiledDestination` to keep the result
   and load it directly with `MLModel.load` on later launches:

   ```dart
   final model = await MLModel.loadAsset(
     'assets/models/MyModel.mlpackage',
     configuration: const MLModelConfiguration(
       computeUnits: MLComputeUnits.cpuAndNeuralEngine,
     ),
     compiledDestination: '$supportDir/MyModel.mlmodelc',
   );
   ```

3. Inspect `model.modelDescription` for input names, types and constraints,
   then predict:

   ```dart
   final prediction = await model.predict({
     'image': ImageInput.file(photoPath), // resized to the input constraint
     'threshold': const MLFeatureValue.float64(0.5),
   });
   print(prediction.stringValue('classLabel'));
   ```

4. `dispose()` models and states when done.

## Swift → Dart

| Core ML (Swift) | core_ml (Dart) |
|---|---|
| `MLModel.compileModel(at:)` | `MLModel.compile(path, destination:)` |
| `MLModel.load(contentsOf:configuration:)` | `MLModel.load(compiledPath, configuration:)` |
| — (compile + load) | `MLModel.compileAndLoad`, `MLModel.loadAsset` |
| `MLModelAsset(url:).functionNames` | `MLModel.functionNames(compiledPath)` |
| `MLModelAsset.modelDescription` / `modelDescription(of:)` | `MLModel.describe(compiledPath, functionName:)` |
| `MLModelConfiguration` | `MLModelConfiguration` |
| `.computeUnits` (`MLComputeUnits`) | `computeUnits` (`MLComputeUnits`) |
| `.allowLowPrecisionAccumulationOnGPU` | `allowLowPrecisionAccumulationOnGPU` |
| `.functionName` | `functionName` |
| `.modelDisplayName` | `modelDisplayName` |
| `.optimizationHints.reshapeFrequency` / `.specializationStrategy` | `reshapeFrequency` / `specializationStrategy` |
| `MLModel.modelDescription` | `MLModel.modelDescription` (`MLModelDescription`) |
| `MLModel.configuration` | `MLModel.configuration` |
| `MLModelDescription.inputDescriptionsByName` etc. | `inputs`, `outputs`, `states`, `trainingInputs` |
| `.metadata[.author]` etc. | `metadata.author`, `license`, `description`, `versionString`, `creatorDefined` |
| `.classLabels`, `.predictedFeatureName`, `.predictedProbabilitiesName`, `.isUpdatable` | same names |
| `MLFeatureDescription` (+ `isOptional`) | `MLFeatureDescription` |
| `MLMultiArrayConstraint` / `MLMultiArrayShapeConstraint` | `MLMultiArrayConstraint` |
| `MLImageConstraint` / `MLImageSizeConstraint` / `MLImageSize` | `MLImageConstraint` / `MLImageSize` |
| `MLDictionaryConstraint`, `MLSequenceConstraint`, `MLStateConstraint` | same names |
| `MLFeatureValue` | sealed `MLFeatureValue` |
| `MLFeatureValue(multiArray:)` / `MLMultiArray` | `MLMultiArray` (raw bytes + shape + strides) |
| `MLFeatureValue(pixelBuffer:)` | `PixelBuffer`, `ImageInput.pixels` |
| `MLFeatureValue(imageAt:constraint:options:)` (equivalent; decoded with Core Image) | `ImageInput.file(path)`, `ImageInput.encoded(bytes)` |
| `MLFeatureValue(string:)` / `(int64:)` / `(double:)` | `MLFeatureValue.string` / `.int64` / `.float64` |
| `MLFeatureValue(dictionary:)` | `MLDictionaryValue.strings` / `.int64s` |
| `MLFeatureValue(sequence:)` / `MLSequence` | `MLSequenceValue.strings` / `.int64s` |
| `MLFeatureValue(undefined:)` | `MLUndefinedValue` |
| `model.prediction(from:options:) async` | `model.predict(inputs)` |
| `model.predictions(from:options:)` | `model.predictBatch(listOfInputs)` |
| `model.makeState()` → `MLState` | `model.makeState()` → `MLState` |
| `model.prediction(from:using:options:) async` | `model.predict(inputs, state: state)` |
| `MLState.withMultiArray(for:)` | `state.read(name)`, `state.write(name, array)` |
| `MLModel.availableComputeDevices` | `CoreML.availableComputeDevices()` |
| `MLComputeDevice.allComputeDevices` | `CoreML.allComputeDevices()` |
| `MLModelError` codes | `CoreMLException.code` (`CoreMLErrorCode`) |

### Values

* `MLMultiArray` keeps raw little-endian storage with its data type, shape and
  element strides. Constructors: `float16`, `float32`, `float64`, `int32`,
  `int8`, `fromList`, `fromBytes`. Read with `toDoubleList`, `toIntList`,
  `elementAt`, `toFloat32List`, or the zero-copy `asFloat32List`. Float16 is
  encoded and decoded in Dart (round to nearest even).
* Image inputs are `ImageInput.file`, `ImageInput.encoded` or `PixelBuffer`
  (`ImageInput.pixels`, `PixelBuffer.fromRgba8888`). Files and encoded images
  are decoded natively and resized to the feature's `MLImageConstraint` size
  and pixel format unless you pass `width` / `height` / `pixelFormatType`.
  Image outputs are `PixelBuffer`s; `CoreML.encodeImage` turns one into PNG or
  JPEG bytes for `Image.memory`.
* `MLPrediction` is a read-only map of outputs with typed accessors:
  `multiArray`, `image`, `stringValue`, `int64Value`, `doubleValue`,
  `dictionary`, `sequence`.

### Stateful models

```dart
final state = await model.makeState();   // zero-filled buffers
for (final token in tokens) {
  final prediction = await model.predict({'x': token}, state: state);
}
final total = await state.read('total');  // copy a buffer into Dart
await state.write('total', MLMultiArray.float16([0, 0, 0]));
await state.dispose();
```

Predicting a stateful model without a state throws `invalid_argument`.

## Not bridged

* **`MLUpdateTask`, `MLUpdateContext`, `MLParameterKey`, model parameters**:
  on-device training needs updatable (neural-network) specs, parameter
  dictionaries and progress-handler callbacks that would double the API. The
  description still reports `isUpdatable` and `trainingInputs`.
* **`MLModelCollection`**: deprecated and sunset by Apple in iOS 17.4 /
  macOS 14.4 (use Background Assets or `URLSession`).
* **`MLComputePlan`, `MLModelStructure`**: per-operation device placement and
  cost analysis is a debugging tool with a large type graph.
* **`MLTensor`** and `MLShapedArray`: Swift-only value types; `MLMultiArray`
  covers the same data across the channel.
* **Custom layers and custom models** (`MLCustomLayer`, `MLCustomModel`):
  they must be implemented in Swift inside the app.
* **`MLPredictionOptions.outputBackings`** and native-resident values: all
  values travel by value; there is no way to keep an output on the native
  side and feed it back without a copy.
* **`MLModelConfiguration.preferredMetalDevice`** and `parameters`.
* **`MLModel.load(asset:)` from in-memory specifications** and encrypted-model
  key fetching (decryption errors are still reported as `model_decryption`).
* **Image crop-and-scale options** (`MLFeatureValue.ImageOption`): they
  depend on Vision. Images are stretched to the constraint size instead.

## Resources, threading and errors

* `MLModel` and `MLState` are native handles. Call `dispose()`; a `Finalizer`
  releases forgotten ones eventually. Using a disposed object throws
  `StateError`. `CoreML.releaseAll()` frees everything (useful after hot
  restart) and `CoreML.liveHandleCount()` helps catch leaks.
* A state keeps its model alive natively, so disposing the model first is
  safe.
* Loading, compiling, predicting and image decoding run off the platform
  thread. One `MLModel` may serve concurrent predictions.
* Core ML requires predictions that share an `MLState` to be serialized. An
  overlapping prediction or state read/write fails fast with `busy` instead
  of blocking; `await` each step.
* Errors are `CoreMLException` with a stable `code` (`CoreMLErrorCode`):
  `MLModelError` maps to `feature_type`, `io_error`, `custom_model`,
  `update_error`, `parameters`, `model_decryption`, `prediction_cancelled` or
  `core_ml_error`; the plugin adds `unsupported`, `invalid_handle`,
  `invalid_argument`, `not_found`, `busy` and `pixel_buffer_error`.

## Known Core ML behavior

* **`.mlpackage` without weights and Flutter assets.** `coremltools` always
  lists a `Data/com.apple.CoreML/weights` item in `Manifest.json`. When the
  model has no weights that directory is empty, Flutter does not bundle it,
  and Core ML refuses the package ("Item does not exist for identifier").
  Remove the empty item from the manifest (see
  `tool/models/flutter_bundle.py`) or ship a compiled `.mlmodelc`.
* `MLModel.compileModel(at:)` writes to a temporary directory the system may
  delete; persist the result with `destination:`.
* `MLModel.functionNames` is empty for an ordinary single-function model;
  only multi-function packages (built with `coremltools`'
  `save_multifunction`) list names. Loading with an unknown `functionName`
  fails with a `CoreMLException`.
* Core ML converts multi-array inputs to the declared data type: a `float64`
  array is accepted for a `float32` input.
* Outputs may be non-contiguous (for example float16 arrays backed by a
  padded `CVPixelBuffer`); `MLMultiArray` carries the real strides, so
  `toDoubleList()` is always in logical order, but `bytes` may contain
  padding.
* Core ML state buffers are float16. GPU and Neural Engine configurations may
  compute in float16 even for float32 models; compare with a tolerance.
* Image features declared as `RGB` or `BGR` use `kCVPixelFormatType_32BGRA`
  buffers; `PixelFormat.bgra32` is the matching constant.
* Supplying an input of the wrong type or shape, or leaving a required input
  out, fails with a `CoreMLException` carrying Core ML's own message (for
  example "MultiArray shape (2) does not match the shape (3) specified in the
  model description").

## Development

```sh
# Regenerate the Pigeon bindings
dart run pigeon --input pigeons/core_ml_api.dart
dart format lib/src/messages.g.dart

# Unit tests (fakes, no device)
flutter test

# Integration tests against real Core ML, one file at a time
cd example
flutter test integration_test/core_ml_test.dart -d macos
flutter test integration_test/app_test.dart -d macos

# On a physical device (wireless debugging needs flutter drive):
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/core_ml_test.dart -d <device-id> --publish-port
```

The test models are generated by `tool/models/` (see its README).
