# core_ml_example

A small Material 3 app that runs the core_ml plugin against six tiny bundled
Core ML models (see `../tool/models/README.md`): an affine function, a
multi-output model, a classifier, an image-input model, a stateful
accumulator (the multi-function model is used by the integration tests), and batch prediction on every compute-unit setting.

```sh
flutter run -d macos
flutter test integration_test/core_ml_test.dart -d macos
flutter test integration_test/app_test.dart -d macos
```
