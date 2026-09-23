# Handoff notes (2026-09-22)

Read this, then `docs/CONVENTIONS.md` (binding) and the root `README.md`.
Nothing is committed. Don't commit unless the user asks.

Codex continuation: see `docs/CODEX_HANDOFF.md` for subsequent changes and
verification. The notes below preserve the original handoff.

## Goal

The user asked: "fully support [Apple's] Core AI via Swift platform channels
using Pigeon and Flutter", then "build out everything needed to take advantage
of Apple's AI ecosystem", as a monorepo of plugins. Each Apple framework gets
its own package under `packages/`.

## Status by package

| Package | State |
|---|---|
| core_ai | Done. Tested on macOS 27 (unit and integration) and on an iPhone with iOS 27 (21/21). |
| foundation_models | Done. Tested on macOS 27 and on the iPhone (18/18). |
| apple_natural_language | Done on macOS: 14 unit, 15 integration and 1 app test pass; the iOS build succeeds. **On the iPhone, 14/15 pass**, see below. |
| apple_vision | A background agent was building it. Read `packages/apple_vision/HANDOFF_NOTES.md` if it exists, then verify. |
| core_ml | Same: a background agent; see `packages/core_ml/HANDOFF_NOTES.md`. |
| apple_speech | Same: a background agent; see `packages/apple_speech/HANDOFF_NOTES.md`. |
| apple_translation | Same: a background agent; see `packages/apple_translation/HANDOFF_NOTES.md`. |
| apple_sound_analysis | **Partly written** (by me), see below. |
| image_playground | Not started (scaffold only). |
| media_intelligence | Not started (scaffold only). |

The four background agents may still be running, or may have stopped partway.
Check whether files are still changing before you edit those packages. Don't
trust any report without rerunning analyze and the tests yourself. When a
package is verified, update its row in the root `README.md` status table.

## apple_natural_language: open item

On the iPhone, the "finds named entities" test fails; on macOS it passes. The
diagnostic rerun shows that **every token is tagged `Other`**: "Tim", "Cook",
"Paris" and "Apple" all come back as `Other`, and the names aren't joined.
So the named-entity model isn't installed on that phone.

Suggested fix: in the test, call
`Tagger.requestAssets(language: 'en', scheme: TagScheme.nameType)` first. If
the tags are still all `Other`, mark the test skipped with the reason
(`markTestSkipped`) rather than failing. Also add a note under "Known
platform behavior" in the package README: named-entity tagging may need
downloaded assets on iOS, and without them it returns `Other`. Then update its "Tested:" line and the root README row,
which currently says "tested on macOS 27".

Command:

```sh
cd packages/apple_natural_language/example
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/apple_natural_language_test.dart \
  -d 00008150-001229241AF8401C --publish-port
```

Over wireless this takes more than 10 minutes, so run it in the background.

## apple_sound_analysis: where I stopped

Done:
- `pigeons/apple_sound_analysis_api.dart`, with the Pigeon code generated
  (Dart and Swift).
- The API has three kinds of analysis:
  - **File:** `startFileAnalysis`.
  - **PCM pushed from Dart:** `startStreamAnalysis`, `analyzeSamples`,
    `completeStreamAnalysis`. Samples travel as the bytes of a little-endian
    Float32List, because Pigeon has no float32 list type.
  - **Microphone:** `startMicrophoneAnalysis`.
- All three deliver results through `AppleSoundAnalysisCallbackApi`
  (`onResult`, `onComplete`, `onError`), routed by a request id chosen in
  Dart.
- `Errors.swift`: error codes, including a translation of the SNErrorDomain
  codes.
- `Analyses.swift`: `AnalysisRegistry`, `EventSink` (drops events for
  stopped requests), `ResultForwarder` (the SNResultsObserving
  implementation), and `FileAnalysis`, `StreamAnalysis` and
  `MicrophoneAnalysis`. **Neither Swift file has been typechecked yet.**

Still to do:
1. `AppleSoundAnalysisHostApiImpl.swift`:
   - `makeRequest(config)`: the built-in classifier is
     `SNClassifySoundRequest(classifierIdentifier: .version1)`. Otherwise
     load `MLModel` from the path, compiling `.mlmodel`/`.mlpackage` with
     `MLModel.compileModel`, and cache it by path.
   - Validate `windowDurationSeconds` against `windowDurationConstraint`
     before setting it. An invalid value may raise an ObjC exception, which
     would crash. Validate `overlapFactor` is in [0, 1).
   - `classifierInfo`.
   - The start methods: check `registry.microphoneIsRunning` and throw
     `busy`. Check `AVCaptureDevice.authorizationStatus(for: .audio)` and
     throw `permission_denied`.
   - `cancel`/`cancelAll`, and permission status and request via
     `AVCaptureDevice`.
2. `AppleSoundAnalysisPlugin.swift`: register the three APIs, as in
   `FoundationModelsPlugin.swift`.
3. Typecheck against iOS 15 and macOS 12. Everything used is available at
   those targets, so no `@available` is needed.
4. The Dart layer:
   - bindings with a callback router (copy
     `foundation_models/lib/src/bindings.dart`), errors and `testing.dart`;
   - `SoundClassifier` (built-in or model, window and overlap) with
     `info()`;
   - `SoundAnalyzer.classifyFile` and `classifyMicrophone`, returning
     Streams whose cancellation calls `cancel`;
   - `SoundStreamClassifier` with `add(Float32List)` and `close()`;
   - `MicrophonePermission`.
5. Unit tests with fakes.
6. Integration tests using `example/assets/` (declare them in pubspec):
   - `speech.wav`: the built-in classifier scores it "speech" at about 0.91
     top-1, with 3 s windows at 0, 1.5 s, …
   - `tone.wav`: a 550 Hz sine.
   - `SpeechOrTone.mlmodel`: a 4.6 KB Create ML model with labels
     `["speech","tone"]` and a 0.975 s window. It scores 1.00 on the right
     file.
   - For the stream test, decode the WAV in Dart (16 kHz 16-bit mono PCM)
     to Float32 and push it.
   - Error cases: a missing file gives SNErrorDomain code 5, which maps to
     `invalid_file`.
   - The microphone test can only check permission status, since there's no
     TCC prompt in the test runner.
7. Example app:
   - Add `NSMicrophoneUsageDescription` to both Info.plists.
   - Add `com.apple.security.device.audio-input` to the macOS entitlements.
8. README, CHANGELOG, `flutter build ios --no-codesign --debug`, and
   `example/test_driver/integration_test.dart`.

The scripts that generated the assets, and my probes, are in
`packages/apple_sound_analysis/tool/`.

Facts from probing the built-in classifier:
- It has 303 labels, including speech, whistling and beep.
- The default window is 3.0 s with overlap 0.5; the allowed window range is
  0.5–15 s.
- `windowDurationConstraint`'s switch needs `@unknown default`.

## image_playground, media_intelligence

Scaffolds only. Both frameworks are in the iOS and macOS 27 SDKs
(swiftinterfaces of about 460 and 190 lines). Read the interface first. The
brief I gave the agents is in this session's transcript; its content is
mostly `docs/CONVENTIONS.md` plus "assert concrete outputs against the real
framework."

## Environment facts

- Flutter has SwiftPM disabled globally, so builds use CocoaPods. Don't
  change global config.
- After a podspec change, run `pod install` in `example/macos` and
  `example/ios`.
- Run macOS integration tests one file at a time:
  `flutter test integration_test/<file>.dart -d macos`.
- The iPhone (wireless, iOS 27) needs `flutter drive` (see the command
  above), not `flutter test`.
- Core AI isn't in the iOS Simulator SDK.
- Never list Apple frameworks in a podspec or `Package.swift`; they're
  weak-linked automatically.
- Gate code with `#if canImport` plus `@available`. A newer-OS type inside
  an enum payload must be stored as `AnyObject`.
- Pigeon 29:
  - `description` can't be a field name.
  - The only typed lists are `Uint8List`, `Int32List`, `Int64List` and
    `Float64List`.
  - Imports other than `package:pigeon/pigeon.dart` are rejected.
  - Run it from the package directory, then run `dart format` on
    `messages.g.dart`.
- `flutter_test` exports a `Tags` class, so don't name public API `Tags`.
  apple_natural_language uses `TagValue`.
- BSD `sed` ignores `\b`; use `perl -pi -e`.
- I fixed the `pigeons/copyright.txt` headers (they all said
  `core_ai_api.dart`) in natural_language, sound_analysis,
  foundation_models, media_intelligence and image_playground. I regenerated
  the first three; only the header comment changed.

## Left for the user to decide

`LICENSE` contents and the podspec `homepage` / author.
