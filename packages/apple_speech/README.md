# apple_speech

**Implemented and verified on macOS 27; iOS device build verified.**

Flutter bindings for Apple's Speech framework, using Pigeon and shared
Darwin Swift code. Includes `SpeechAnalyzer`, `SpeechTranscriber`,
`DictationTranscriber`, `SpeechDetector`, `AssetInventory`, and the legacy
`SFSpeechRecognizer` API.

## Requirements

* Flutter 3.38+, Dart 3.11+, Xcode 27 to compile this source.
* Deployment targets: iOS 15 / macOS 12. Legacy recognition works on these
  targets; analyzer, transcriber and asset APIs require iOS/macOS 26.
* `AudioSource.asset` and `AnalyzerOptions.ignoresResourceLimits` need version
  27. The latter is ignored on 26. Audio files work on 26.
* SpeechTranscriber requires supported hardware and installed locale assets.
  Check both `Speech.isAnalyzerSupported()` and
  `SpeechTranscriber.isAvailable()`. Locale availability varies by device.
* Legacy recognition requires speech authorization, including for files.
  Analyzer file transcription does not need speech or microphone permission.

No Apple framework is explicitly linked in the podspec or Swift package;
availability guards allow deployment to older supported systems.

## Quick start

Use a local audio file and an installed locale:

```dart
import 'dart:developer' as developer;
import 'package:apple_speech/apple_speech.dart';

Future<String> transcribe(String path) async {
  if (!await Speech.isAnalyzerSupported() ||
      !await SpeechTranscriber.isAvailable()) {
    throw StateError('SpeechAnalyzer is unavailable on this device.');
  }
  final locale = await SpeechTranscriber.supportedLocale(equivalentTo: 'en-US');
  if (locale == null ||
      !(await SpeechTranscriber.installedLocales()).contains(locale)) {
    throw StateError('Install the English speech model first.');
  }
  final analysis = await SpeechAnalyzer.analyze(
    source: AudioSource.file(path),
    modules: [
      SpeechTranscriber(
        locale: locale,
        preset: SpeechTranscriberPreset.timeIndexedProgressiveTranscription,
      ),
    ],
  );
  final text = StringBuffer();
  try {
    await for (final result in analysis.results) {
      // Volatile results can be replaced. Only accumulate final text.
      if (result.isFinal && result.text != null) {
        text.write('${result.text} ');
      }
      developer.log('${result.text}', name: 'speech');
    }
    await analysis.done;
    return text.toString().trim();
  } finally {
    await analysis.cancel(); // Also safe after normal completion.
  }
}
```

Results contain the originating `moduleIndex`, audio range and finalization
time, final/volatile status, alternatives and attributed text segments.
Segment string ranges use UTF-16 offsets, matching Dart's `substring`.
Audio times are `Duration`s. To request both word timing and confidence, use:

```dart
const module = SpeechTranscriber.custom(
  locale: 'en-US',
  reportingOptions: {ReportingOption.volatileResults},
  attributeOptions: {
    ResultAttributeOption.audioTimeRange,
    ResultAttributeOption.transcriptionConfidence,
  },
);
```

Preset constructors use Apple's presets; `.custom` constructors use explicit
option sets. Invalid combinations produce `SpeechErrorCode.invalidArgument`.
`SpeechDetector` must accompany a transcriber; detector-only analysis is
rejected before Apple's zero-channel format can trap.

## Models and asset downloads

Query `SpeechTranscriber.supportedLocales()` / `installedLocales()` or the
corresponding `DictationTranscriber` methods. Identifiers use BCP 47 (`en-US`).
`AssetInventory.status(modules)` reports Apple's aggregate asset state.
On this macOS 27 system it can say `supported` even for installed, usable
English models, including a custom SpeechTranscriber. The plugin also checks
the transcriber's installed locales before rejecting a request.

From an explicit user action, install missing models with:

```dart
final downloaded = await AssetInventory.installAssets(
  [const SpeechTranscriber(locale: 'en-US')],
  onProgress: (fraction) => developer.log('Download: $fraction'),
);
// false means Apple reported no installation request was needed.
```

`reserve(locale)`, `release(locale)`, `reservedLocales()` and
`maximumReservedLocales()` expose Apple's app-specific locale reservations.
The plugin does not silently reserve locales or download models.
`SpeechAnalyzer.endModelRetention()` releases retained models; model retention
is separate from installing or reserving assets.

## Microphone and legacy recognition

Add `NSMicrophoneUsageDescription` to the app's Info.plist. On macOS also add
`com.apple.security.device.audio-input` to its entitlements. Query
`Speech.microphoneAuthorizationStatus()` without prompting, or call
`Speech.requestMicrophoneAuthorization()` in response to the user's action.
Pass `AudioSource.microphone()` once authorized.

On iOS the plugin activates a recording audio session and restores its prior
category, mode and options after capture. It deactivates the session when it
stops; it cannot determine and restore another owner's prior active state.
Use `AudioSource.microphone(configureAudioSession: false)` when the app manages
its own session. Keep one microphone capture active at a time.

Legacy recognition additionally needs `NSSpeechRecognitionUsageDescription`.
Call `SpeechRecognizer.requestAuthorization()` explicitly, then:

```dart
final request = await SpeechRecognizer.recognize(
  source: AudioSource.file('/absolute/path/speech.wav'),
  locale: 'en-US',
  requiresOnDeviceRecognition: true,
  shouldReportPartialResults: true,
  addsPunctuation: true,
);
try {
  await for (final result in request.results) {
    // Each hypothesis replaces the previous complete hypothesis.
    developer.log(result.bestTranscription.formattedString);
  }
} finally {
  await request.cancel();
}
```

Without `requiresOnDeviceRecognition: true`, Apple may use its online
recognition service. Network-backed recognition and model downloads require
`com.apple.security.network.client` in sandboxed macOS apps. Query
`SpeechRecognizer.info(locale: ...)` for current availability and on-device
support. `addsPunctuation` is ignored before iOS 16 / macOS 13.

## Lifetime and errors

* A request owns a buffered, single-subscription `results` stream. Registering
  callbacks before starting native work preserves early results.
* `finish()` ends live input and waits for final results. Analyzer file/asset
  input continues to EOF; use `cancel()` to stop it early without finalizing.
* `cancel()` and cancelling the stream subscription stop native work.
  Cancellation closes the stream normally and is idempotent. Native failures
  are delivered to both the stream and `done` as `SpeechException`.
* Always cancel unfinished requests when leaving their owning screen.
  `Speech.cancelAll()` closes current Dart requests and cancels native work,
  including downloads. It returns the number of Dart requests selected.
  Avoid starting new work concurrently with this global cleanup. A pending
  analysis startup is allowed to settle before its cancellation completes.
* `Speech.activeRequestCount()` reports the native registry count for cleanup
  checks; `SpeechBindings.routedRequestCount` is available from `testing.dart`.
* Errors have stable typed codes and, when available, the underlying native
  domain/code. Missing files, invalid modules, unsupported locales and missing
  models are validated. Availability methods return false on missing channels.

## Swift → Dart

| Swift | Dart |
|---|---|
| `SpeechAnalyzer` + input sequence | `SpeechAnalyzer.analyze(source:, modules:)` |
| `SpeechTranscriber`, `.Preset` | `SpeechTranscriber`, `SpeechTranscriberPreset` |
| `DictationTranscriber` | `DictationTranscriber` |
| `SpeechDetector` | `SpeechDetector` alongside a transcriber |
| `SpeechAnalyzer.Options` | `AnalyzerOptions` |
| `AnalysisContext.contextualStrings` | `analyze(contextualStrings:)` |
| `SpeechAnalyzer.bestAvailableAudioFormat` | `SpeechAnalyzer.bestAvailableAudioFormat` |
| Module result `AttributedString` runs | `AnalysisResult.segments` |
| `SpeechModels.endRetention` | `SpeechAnalyzer.endModelRetention` |
| `AssetInventory` | `AssetInventory` static queries/install/reservations |
| `SFSpeechRecognizer` | `SpeechRecognizer` |
| `SFSpeechRecognitionTask` | `SpeechRecognition`, `results`, `finish`, `cancel` |
| `SFTranscription`, `SFTranscriptionSegment` | `Transcription`, `TranscriptionSegment` |
| `SFVoiceAnalytics` and custom language models | Not bridged |

## Scope and platform behavior

The bridge covers file, media-asset and default-microphone inputs; module
configuration; contextual strings; model assets; and streaming recognition.
It does not expose arbitrary pushed PCM, swapping modules during analysis,
manual analyzer timeline control, arbitrary attributed-string styling,
recognizer availability delegates, voice analytics, or custom legacy language
model training. These require additional input/lifetime contracts or broader
message schemas; use the native framework for those advanced flows.

`AudioSource.simulatedMicrophone` is a testing helper that paces file buffers
through the live conversion pipeline without requesting microphone permission.
It does not validate hardware capture. The detector ran alongside transcription
on this Mac but produced no separate detection events; do not assume one
arrives for every clip. Partial results may have one segment covering the whole
phrase; final results provide word runs when timing is requested.

## Verification

See [HANDOFF_NOTES.md](HANDOFF_NOTES.md) for current verification and remaining
manual checks, and [example/README.md](example/README.md) for demo/test commands.
Tests use handwritten API fakes and bundled synthetic audio. Real-framework
tests never request permissions or download models. Live microphone capture,
authorized legacy recognition, asset downloading/reservations, and iPhone
runtime behavior require separate manual verification.
