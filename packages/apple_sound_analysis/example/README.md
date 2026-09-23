# apple_sound_analysis example

Classify bundled speech and a 550 Hz tone with Apple's built-in sound model
or a small custom Core ML classifier. The PCM button decodes the tone fixture
and feeds float32 samples in chunks. Microphone capture starts only when you
choose **Listen to microphone** and grant permission.

## Run

```sh
flutter pub get
flutter run -d macos
```

Requires iOS 15+ / macOS 12+, Xcode 27 and Flutter 3.38+. Both app Info.plists
declare microphone usage, and the macOS entitlements allow audio input.
No microphone authorization is needed for the bundled file and PCM demos.

* **Speech file**: the built-in classifier's top label should be `speech`.
* **Use the custom speech-or-tone model**: switches to the bundled Create ML
  model with labels `speech` and `tone` and a 0.975-second default window.
* **Tone file** and **Tone as PCM**: with the custom model, both report `tone`.
* **Listen to microphone**: requests permission when needed, then displays
  classification windows until you choose **Stop**.

The UI retains the latest 40 windows. Analysis subscriptions are cancelled
when stopped or when the page is disposed. Assets are copied to a private
temporary directory, removed when the example is disposed. On iOS, capture
temporarily configures the audio session for recording; see the package
README before combining this with playback in another app.

## Verify

```sh
flutter test integration_test/apple_sound_analysis_test.dart -d macos
flutter test integration_test/app_test.dart -d macos
flutter build ios --no-codesign --debug
```

Run integration files separately. The app test drives built-in speech,
custom-model tone, and PCM tone classification and checks for leaked native
analyses. The framework test additionally verifies stereo PCM, timestamps,
error handling, cancellation, model constraints and authorization status.
Neither test records the microphone or displays a permission prompt.

For an unlocked physical iPhone:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/apple_sound_analysis_test.dart -d <device-id> \
  --publish-port
```

Live microphone capture and iPhone runtime behavior remain manual
verification items. See [the package README](../README.md) for API usage.
