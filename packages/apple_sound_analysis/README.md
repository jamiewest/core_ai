# apple_sound_analysis

Flutter bindings for Apple's **SoundAnalysis** framework through Pigeon
platform channels. Classify audio files, raw PCM from Dart, or the microphone
with Apple's built-in classifier or your own Core ML sound model. Analysis
runs on the device.

## Requirements

* iOS 15+ or macOS 12+; build with Xcode 27 and Flutter 3.38+.
* `SoundAnalyzer.isSupported()` returns false on unsupported platforms.
* File and PCM analysis need no microphone permission. Microphone capture
  requires user authorization and the app configuration described below.
* Custom models must be Core ML **sound classifiers**: `.mlmodel`,
  `.mlpackage`, or compiled `.mlmodelc` files. Arbitrary Core ML models and
  Core AI `.aimodel` files are not interchangeable with sound classifiers.

## Classify a file

```dart
import 'dart:developer';
import 'package:apple_sound_analysis/apple_sound_analysis.dart';

Future<void> classify(String path) async {
  if (!await SoundAnalyzer.isSupported()) return;
  await for (final window in SoundAnalyzer.classifyFile(
    path,
    maximumClassifications: 3,
  )) {
    final top = window.top;
    log('${window.startSeconds}s: ${top?.identifier} ${top?.confidence}');
  }
}
```

Pass a file path readable by the app, not an asset key or URL. To classify a
Flutter asset, copy its bytes to an app-owned file first; the example's
`SoundFixtures` shows this without extra dependencies. Files stream results
when listened to and close on completion. Cancelling the subscription stops
native work. A stream supports one subscriber.

Each `ClassificationResult` contains its window start and duration in seconds,
and an immutable list of `Classification` values sorted by confidence.
`maximumClassifications` must be positive; omit it to receive all labels.
`top` is the first classification, or null for an empty result.

## Classifier settings and custom models

```dart
const classifier = SoundClassifier.builtIn(
  windowDurationSeconds: 1,
  overlapFactor: 0.5,
);
final info = await classifier.info();
// info.knownClassifications, windowDurationSeconds, overlapFactor
// info.allowedWindowDurationsSeconds OR minimumWindowSeconds/maximumWindowSeconds

final custom = SoundClassifier.model('/path/SpeechOrTone.mlmodel');
final results = await SoundAnalyzer.classifyFile(
  '/path/tone.wav', classifier: custom,
).toList();
```

Omitting settings uses the model defaults. The built-in version-1 classifier
on the test Mac exposes 303 labels, including `speech`, `whistling`, and
`beep`, with a 3-second default window and 0.5 overlap. Window constraints
come from the framework, not a hard-coded model assumption. An enumerated
constraint lists exact allowed durations; a continuous constraint has an
inclusive minimum and **exclusive** maximum. The observed upper bound was
15.0000625 seconds. The custom fixture defaults to 0.975 seconds but also
accepts other supported window lengths.

Native code rejects nonfinite or unsupported window durations and overlap
outside `[0, 1)` before configuring the request. It does not silently choose
a different window for an invalid setting.

Source models are compiled automatically and cached by their standardized
file path for the Flutter engine's lifetime. Compiled temporary files are
removed when the plugin detaches. To reload changed model contents, use a
different path or recreate the engine. `cancelAll()` stops analyses, not the
model cache.

## Push PCM from Dart

```dart
import 'dart:typed_data';

Future<List<ClassificationResult>> classifySamples(Float32List samples) async {
  final analyzer = await SoundStreamClassifier.create(
    sampleRate: 16000,
    channelCount: 1,
    maximumClassifications: 3,
  );
  final results = analyzer.results.toList();
  try {
    await analyzer.add(samples);
    await analyzer.close();
    return await results;
  } finally {
    await analyzer.cancel();
  }
}
```

Supply decoded interleaved float32 samples, normally in `[-1, 1]`, without a
WAV header. With two channels the order is `left0, right0, left1, right1, …`.
Buffers must contain whole frames and finite samples. The plugin accepts
1–32 channels and a finite positive sample rate up to 384 kHz; SoundAnalysis
may reject formats unsupported by the selected model.

`add` copies the supplied view and sends little-endian float32 bytes. Calls
are serialized; await each one to keep queued memory bounded. Native code
deinterleaves channels and assigns consecutive frame positions. `close()`
finishes input after queued writes; it does **not** wait for every result.
Consume `results` until it closes to receive the final windows. The result
stream can be listened to after creation because callbacks are buffered.

Call `cancel()` when abandoning an analyzer. Cancelling the result subscription
also cancels the native analyzer. Adds after close, cancellation or completion
throw `StateError`. Close and cancellation are idempotent. A rejected sample
buffer does not prevent subsequent valid writes.

## Microphone

Add to the app's iOS and macOS `Info.plist`:

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Classify sounds when you choose to use the microphone.</string>
```

For a sandboxed macOS app, add to both debug and release entitlements:

```xml
<key>com.apple.security.device.audio-input</key>
<true/>
```

Request permission only in response to the user's microphone action:

```dart
if (await MicrophonePermission.request()) {
  final subscription = SoundAnalyzer.classifyMicrophone(
    maximumClassifications: 3,
  ).listen((window) {
    log('${window.top?.identifier}');
  }, onError: (Object error) {
    log('Microphone analysis failed', error: error);
  });
  // Later, when the user stops listening:
  await subscription.cancel();
}
```

`MicrophonePermission.status()` reads authorization without prompting.
Starting microphone analysis never requests permission implicitly: it emits
`permissionDenied` unless authorization has already been granted. Only one
microphone analysis runs per plugin instance; a second emits `busy`.

On iOS the plugin activates a recording session using `.record` and
`.measurement`. Stopping deactivates it and restores the prior category,
mode and options; apps that also play audio should manage reactivation of
their own session. The microphone tap copies buffers before asynchronous
analysis and stops capture on cancellation or a terminal error.

## Cancellation and errors

`SoundAnalyzer.cancelAll()` waits for pending starts, stops native analyses,
closes the corresponding Dart streams, and returns the number of native
analyses still running when cancellation occurred. Call it after a hot restart
before creating new analyses. New starts during a cancel-all operation fail
with `StateError`. A cancelled stream ignores late native callbacks.

Failures are `SoundAnalysisException` values with a stable
`SoundAnalysisErrorCode`, readable `message`, and optional native `details`.
File/microphone failures arrive on their streams; PCM creation and writes
can fail through their returned futures. Categories include `unsupported`,
`invalidArgument`, `notFound` (model file), `invalidFile`, `invalidFormat`,
`invalidModel`, `notRunning`, `permissionDenied`, `busy`, `noInputDevice`,
`operationFailed`, `soundAnalysisError` and `unknown`. Dart-side PCM argument
validation throws `ArgumentError` before contacting native code.

## Swift → Dart

| SoundAnalysis / AVFoundation | Dart |
|---|---|
| `SNClassifySoundRequest(classifierIdentifier: .version1)` | `SoundClassifier.builtIn` |
| `SNClassifySoundRequest(mlModel:)` | `SoundClassifier.model` |
| `knownClassifications`, `windowDurationConstraint` | `SoundClassifier.info`, `ClassifierInfo` |
| `windowDuration`, `overlapFactor` | Classifier configuration and info |
| `SNAudioFileAnalyzer` | `SoundAnalyzer.classifyFile` |
| `SNAudioStreamAnalyzer` | `SoundStreamClassifier` |
| `AVAudioEngine` + stream analyzer | `SoundAnalyzer.classifyMicrophone` |
| `SNClassificationResult`, `SNClassification` | `ClassificationResult`, `Classification` |
| `SNResultsObserving` | Result stream events, errors and completion |
| `completeAnalysis()` | `SoundStreamClassifier.close()` |
| `cancelAnalysis()` / `removeAllRequests()` | Subscription cancellation / `cancel()` |
| `AVCaptureDevice` audio authorization | `MicrophonePermission` |

## Not bridged and known behavior

* Model training belongs to Create ML; this plugin loads its sound classifiers.
* Sharing one native analyzer among several classifier requests is not
  exposed. Create separate analyses for separate classifier configurations.
* Explicit frame-position gaps, seeking within files, device selection,
  interruption recovery, and advanced audio-session configuration are not
  exposed. PCM input represents a continuous stream; microphone input uses
  the default device.
* Classification needs a window of context. Short audio may produce no
  windows; always flush PCM input and wait for completion.
* Built-in labels and confidence depend on Apple's model and the actual
  recording.
* The user confirmed manual iPhone microphone classification, stop and restart
  on 2026-09-23. Automated tests check authorization without displaying a
  permission prompt or recording the microphone.

## Example and development

Verified on macOS 27 with Xcode 27: 16 unit tests, 14 framework integration
tests and one example-app integration test pass, with no skips. Workspace
analysis and formatting are clean. The iOS device debug build succeeds.
All 14 framework integration tests also pass on the iOS 27 iPhone. The user
confirmed the live microphone check on 2026-09-23.

The Material example has light/dark themes and buttons for speech, tone,
PCM tone, and microphone input, plus a custom-model toggle and Stop button.
The bundled fixtures are small; `tool/` contains the original generation and
probing scripts. See [example/README.md](example/README.md).

```sh
dart run pigeon --input pigeons/apple_sound_analysis_api.dart
dart format lib/src/messages.g.dart
flutter analyze
flutter test
cd example
flutter test integration_test/apple_sound_analysis_test.dart -d macos
flutter test integration_test/app_test.dart -d macos
flutter build ios --no-codesign --debug
```

Run macOS integration files separately. Tests assert real speech/tone labels,
confidence, window timing, mono/stereo PCM conversion, validation errors and
cancellation without leaked analyses. `package:apple_sound_analysis/testing.dart`
exposes the injectable bindings and Pigeon types for hand-written fake hosts.

On an unlocked physical device:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/apple_sound_analysis_test.dart -d <device-id> \
  --publish-port
```
