# core_ai

Flutter bindings for Apple's **Core AI** framework (iOS 27+ / macOS 27+),
built on [Pigeon](https://pub.dev/packages/pigeon) platform channels.

Load and specialize `.aimodel` files, inspect their functions, and run
inference on NDArrays and pixel buffers from Dart. The package also covers
stateful models, compute-stream pipelines, the specialized-model cache and
model metadata.

```dart
import 'package:core_ai/core_ai.dart';

if (await CoreAI.isSupported()) {
  final model = await AIModel.loadAsset('assets/models/affine.aimodel');
  final function = await model.loadFunction('main');
  final outputs = await function.run({'x': NDArray.float32([1, 2, 3])});
  print(outputs.ndArray('y').toDoubleList()); // [3.0, 5.0, 7.0]
  await function.dispose();
  await model.dispose();
}
```

## Requirements

| | |
|---|---|
| Runs Core AI on | macOS 27+, and iOS 27+ **on a physical device** |
| Builds for | iOS 15+ and macOS 12+ (Core AI is weak-linked) |
| Toolchain | Xcode 27, Flutter 3.38+ |

On older OS versions, and in the **iOS Simulator** (whose SDK has no
`CoreAI.framework`), the app still builds and launches. In those
environments `CoreAI.isSupported()` returns `false` and every Core AI call
throws `CoreAIException` with `CoreAIErrorCode.unsupported`.

The plugin supports both Swift Package Manager and CocoaPods.

**Tested:** the full integration suite (21 tests) passes against real Core AI
on macOS 27 (with both SwiftPM and CocoaPods) and on an iPhone running
iOS 27.0. The iOS 27 Simulator, where Core AI is absent, launches cleanly and
reports unsupported.

## Bundling models

An `.aimodel` is a **directory** (`main.mlirb`, `main.hash`,
`metadata.json`). List the directory itself as an asset:

```yaml
flutter:
  assets:
    - assets/models/MyModel.aimodel/
```

Then load it with `AIModel.loadAsset('assets/models/MyModel.aimodel')`, or
pass any on-disk path to `AIModel.load`, for example a model you downloaded.
The first load specializes the model for the device and caches the result.
Later loads reuse the cache.

## Swift → Dart

| Core AI (Swift) | core_ai (Dart) |
|---|---|
| `AIModel(contentsOf:options:)` | `AIModel.load(path, options:)`, `AIModel.loadAsset(key)` |
| `AIModel.specialize(contentsOf:options:cache:cachePolicy:)` | `AIModel.specialize(path, options:, cache:, policy:)` |
| `functionNames`, `functionDescriptor(for:)` | `functionNames`, `functionDescriptor(name)` |
| `loadFunction(named:)` | `loadFunction(name)` |
| `bookmarkData`, `init(resolvingBookmark:)` | `bookmarkData()`, `AIModel.fromBookmark(data)` |
| `AIModel.deviceArchitectureName` | `CoreAI.deviceArchitectureName()` |
| `ComputeUnitKind.availableKinds` | `CoreAI.availableComputeUnitKinds()` |
| `SpecializationOptions` (`.default`, `.cpuOnly`, preferred kind, `expectFrequentReshapes`) | `SpecializationOptions.defaults`, `.cpuOnly`, `.preferring(kind)`, `copyWith(...)`, `resolve()` |
| `AIModelCache` (`.default`, `init(appGroup:)`, `model(for:options:)`, `deleteEntry…`, `deleteAll`) | `AIModelCache.shared`, `.appGroup(id)`, `model(path)`, `deleteEntry(path)`, `deleteEntries`, `deleteAll`, `deleteEntryForBookmark` |
| `AIModelCache.Policy` | `CachePolicy.defaults`, `.persistent`, `CachePolicy(...)` |
| `InferenceFunction.run(inputs:states:outputViews:)` | `function.run(inputs, state:, states:, outputViews:, retain:)` |
| `InferenceFunction.encode(inputs:states:outputViews:to:)`, `ComputeStream` | `function.encode(inputs, stream:)`, `ComputeStream.create()`, `completed()` |
| `InferenceFunctionDescriptor`, `InferenceValue.Descriptor` | `FunctionDescriptor`, `NDArrayDescriptor` / `ImageDescriptor` |
| `NDArrayDescriptor.resolvingDynamicDimensions(_:)`, `preferredStrides` | `resolveDynamicDimensions(...)`, `preferredStrides` |
| `NDArray` (all 35 `ScalarType`s, strides, `InterleaveLayout`) | `NDArray` (Dart memory) or `NativeValue` (native memory) |
| `CVPixelBuffer` image values | `PixelBuffer`, `NativeValue.fromEncodedImage` |
| `InferenceFunction.AsyncValue` / `AsyncMutableValue` | `NativeValue` of kind `asyncValue` / `asyncMutableValue` |
| `AIModelAsset` (metadata, summary, `updateMetadata`, `removeDerivedArtifacts`) | `AIModelAsset(path)` with the same operations |

## Values

A function's inputs and outputs are `InferenceValue`s, a sealed type with
three cases:

* **`NDArray`**: data in Dart memory. Typed constructors cover `float32`,
  `float64`, `float16`, `bfloat16`, the 8- to 64-bit integer types and
  `boolean`. Every other Core AI type (sub-byte integers, fp8/fp4, complex)
  round-trips as raw bytes through `NDArray.fromBytes`. Reads respect strides
  and interleaved layouts.
* **`PixelBuffer`**: image data in Dart memory. It has one or more planes.
  `fromRgba8888` and `toRgba8888` convert common 8-bit formats. `PixelFormat`
  holds the Core Video format codes.
* **`NativeValue`**: an NDArray or pixel buffer that stays on the native side.
  No data crosses the platform channel until you call `read()`.

```dart
final image = await NativeValue.fromEncodedImage(
  jpegBytes,
  pixelFormatType: descriptor.pixelFormatType, // from an ImageDescriptor
  width: descriptor.width,
  height: descriptor.height,
); // decoded and resized natively

final outputs = await function.run({'image': image});
switch (outputs['logits']) {
  case NDArray logits: print(logits.toDoubleList());
  case PixelBuffer mask: print(mask);
  case NativeValue value: print(await value.describe());
  case null: print('no such output');
}
```

## Stateful models

Every state has to be supplied on every run. `makeState()` allocates all of
them natively, using the layout the function prefers. The state stays native
and is updated in place, so you can keep, for example, a language model's KV
cache across decoding steps without copying it to Dart:

```dart
final state = await function.makeState();
for (final token in tokens) {
  final outputs = await function.run({'token': NDArray.int32([token])}, state: state);
  // ...
}
await state.reset(); // zero-fill for a new sequence
await state.dispose();
```

## Avoiding copies

* **Chain functions natively.** `run(..., retain: {'hidden'})` keeps an output
  native as a `NativeValue`, which you can pass straight into another
  function.
* **Pre-allocate outputs.** `function.allocate('y')` returns a native value
  with the function's preferred strides. Pass it as `outputViews: {'y': view}`
  and it is updated in place.
* **Pipeline work on the GPU or Neural Engine.** `encode` returns async
  native values immediately. Pass them to further `encode` calls, then `read()`
  the final value, or `await stream.completed()`:

```dart
final stream = await ComputeStream.create();
final a = await encoder.encode({'tokens': tokens}, stream: stream);
final b = await decoder.encode({'embeddings': a['embeddings']!}, stream: stream);
final logits = await b['logits']!.readNDArray(); // waits for the GPU work
```

A native value can have many concurrent readers but only one writer. A
conflicting use throws `CoreAIErrorCode.busy`.

## Cache, bookmarks and assets

```dart
final model = await AIModel.specialize(
  path,
  options: const SpecializationOptions.preferring(ComputeUnitKind.neuralEngine),
  policy: CachePolicy.persistent,
);
final bookmark = await model.bookmarkData(); // persist it; restore later with:
final restored = await AIModel.fromBookmark(bookmark);

final summary = await AIModelAsset(path).summary(includeStatistics: true);
await AIModelAsset(writablePath).updateMetadata(author: 'Me', creatorDefined: {'v': 2});
```

## Not bridged

Three Swift entry points take Metal or IOSurface objects, which have no Dart
counterpart, so they are not exposed:

* `ComputeStream(commandQueue:)`. `ComputeStream.create()` makes its own
  command queue instead.
* The `MTLBuffer`- and `IOSurface`-backed `NDArray.RawView` and
  `MutableRawView` initializers.
* `InferenceFunction.AsyncValue(unsafeBuffer:)` and
  `AsyncMutableValue(unsafeBuffer:)`.

Native values cover the same need of keeping data off the Dart heap. Apps
that share GPU buffers with their own Metal code can call Core AI directly
from Swift alongside this plugin.

## Resources, threading and errors

* Models, functions, native values and streams own native objects. Call
  `dispose()` when you're done with them. A `Finalizer` releases any that you
  forget, but only at some later time. After a hot restart, call
  `CoreAI.releaseAll()`, and use `CoreAI.liveHandleCount()` to check for
  leaks.
* Specialization, inference and data conversion run off the platform thread.
  Data in Dart-side `NDArray`s and `PixelBuffer`s is copied across the
  platform channel, so for large tensors that you reuse, prefer
  `NativeValue`s.
* Errors are thrown as `CoreAIException`, whose `code` is a
  `CoreAIErrorCode`: `unsupported`, `notFound`, `invalidArgument`,
  `invalidHandle`, `busy`, `coreAIError`, `assetError`, or
  `pixelBufferError`. The `details` field carries the underlying Swift error.

## Known Core AI behavior

* The iOS Simulator has no Core AI. Test on macOS 27 or on an iOS 27 device.
* As of iOS/macOS 27.0, `AIModelAsset` reads creator-defined integers `0` and
  `1` back as `false` and `true`. They are stored correctly on disk.
* A missing model path makes Core AI report a malformed asset. The plugin
  checks the path first and throws `notFound` instead.

## Development

```sh
dart run pigeon --input pigeons/core_ai_api.dart   # regenerate bindings
flutter test                                       # Dart unit tests (fakes)
cd example
flutter test integration_test/core_ai_test.dart -d macos      # real Core AI
flutter test integration_test/app_test.dart -d macos          # example app
flutter test integration_test/unsupported_test.dart -d <iOS simulator>

# On a physical device (wireless debugging needs flutter drive):
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/core_ai_test.dart -d <device id> --publish-port
```

Run integration test files one at a time on macOS. Passing several to a single
`flutter test` makes the desktop app relaunch between files, which fails with
"Error waiting for a debug connection".

The four test models in `example/assets/models/` are generated by the
scripts in `tool/models/` (see its README).

For tests of your own app, `package:core_ai/testing.dart` lets you swap in
fake host APIs with `CoreAIBindings.instance = CoreAIBindings(host: ...)`.
