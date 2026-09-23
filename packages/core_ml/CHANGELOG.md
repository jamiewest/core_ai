## 0.1.0

* Initial release: Core ML bindings for iOS 18+ and macOS 15+ over Pigeon
  platform channels.
* `MLModel`: runtime compilation of `.mlmodel` / `.mlpackage` with an optional
  persistent destination, loading compiled `.mlmodelc` models and Flutter
  assets, `MLModelAsset` function names and descriptions.
* `MLModelConfiguration`: compute units, low-precision GPU accumulation,
  function name, display name and optimization hints.
* `MLModelDescription`: input, output, state and training features with
  multi-array, image, dictionary, sequence and state constraints, metadata,
  class labels, predicted feature names and `isUpdatable`.
* Predictions with every `MLFeatureValue` type: `MLMultiArray` (float16,
  float32, float64, int32, int8 as raw bytes with shape and strides), images
  from pixels, encoded bytes or files (resized to the input constraint),
  strings, int64s, doubles, dictionaries, sequences and undefined values.
* Async prediction, batch prediction and stateful prediction with `MLState`
  read/write access.
* `CoreML.availableComputeDevices` / `allComputeDevices`, PNG/JPEG export of
  image outputs, stable error codes for `MLModelError`.
