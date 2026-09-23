## 0.1.0

* Initial release: Core AI bindings for iOS 27+ and macOS 27+ over Pigeon
  platform channels.
* `AIModel`: load, load from assets, specialize, bookmarks, function
  descriptors, dynamic-dimension resolution.
* `InferenceFunction`: `run` with NDArray, pixel-buffer and native inputs,
  states, output views and retained outputs; `encode` on a `ComputeStream`.
* `NDArray` covering all 35 Core AI scalar types, with float16/bfloat16
  conversion, strided and interleaved layouts.
* `PixelBuffer`, native image decoding and resizing, PNG/JPEG export.
* `NativeValue`, `InferenceState` and reader/writer leasing for native data.
* `AIModelCache` (shared and app-group), `CachePolicy`,
  `SpecializationOptions`.
* `AIModelAsset` metadata, summaries and derived-artifact cleanup.
* Graceful `unsupported` behavior on older OS versions and the iOS Simulator.
