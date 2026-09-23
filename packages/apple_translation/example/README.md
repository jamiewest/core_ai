# apple_translation example

Translate text using Apple's on-device Translation framework. Choose source
and target languages, check installed packs, select a quality/speed strategy,
and translate either the entire input or each nonempty line as a streaming
batch. Batch cards keep their input line numbers even if results arrive in a
different order.

## Run

```sh
flutter pub get
flutter run -d macos
```

Translation needs iOS 26 / macOS 26 or newer and installed language packs.
Language availability checks work on iOS 18 / macOS 15. Strategy selection
appears on iOS/macOS 26.4+. The app displays a notice on older systems.

The default pair is English → Spanish. If the packs are missing, install them
through the device's translation language settings and select **Check language
packs**. The app cannot start downloads. Faster translation may need a
separate pack from the default quality model.

Try **Translate** with `Hello, how are you?`. For **Translate each line**, enter:

```text
Good morning
Thank you
```

Each operation creates a session and disposes it in a `finally` block. Native
failures are displayed in the app. Source language is explicit; text in a
different language is not automatically detected.

## Verify

```sh
flutter test
flutter test integration_test/apple_translation_test.dart -d macos
flutter test integration_test/app_test.dart -d macos
flutter build ios --no-codesign --debug
```

Run the integration files separately. The app integration test translates the
default greeting, streams the two-line sample, asserts the Spanish output,
and checks for leaked sessions. Tests needing missing language packs report
a skip. Widget tests use fakes for unsupported systems, unsupported pairs,
missing packs, refresh behavior and a narrow display.

For a physical device:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/apple_translation_test.dart -d <device-id> \
  --publish-port
```

See [the package README](../README.md) for API coverage and limitations.
