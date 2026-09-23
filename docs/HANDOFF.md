# Handoff notes

## Current status (2026-09-23)

### Publication preparation

The Vision package is now `apple_vision_native` because `apple_vision` is
already published by another owner. The root and all ten packages now carry
the MIT license, copyright Jamie West. Package and podspec metadata point to
`https://github.com/jamiewest/core_ai`; the podspec author is Jamie West.
Earlier license/homepage/author TODOs below are historical. See
[RELEASING.md](RELEASING.md) for independent package releases and the
non-publishing validation script. Nothing has been uploaded to pub.dev.

Publication preparation verification:

- Workspace analysis and formatting pass.
- All 214 package unit tests and eight example widget tests pass.
- The renamed Vision plugin passes all 16 macOS framework integration tests;
  its iOS example builds with signing disabled.
- All ten CocoaPods specs and Swift package manifests parse successfully.
- All ten publication dry-runs pass with zero warnings in a separate source
  copy outside Git. Archives are approximately 222–420 KB. In this working
  tree, pub reports uncommitted-file warnings until the release is committed.
- MIT licenses and initial `0.1.0` changelog entries exist in every package.

The existing Media Intelligence device limitations remain; they are now
recorded in its published README and changelog as well as in these notes.

### Implementation status

All ten packages are implemented. `image_playground` and
`media_intelligence` were finished on 2026-09-23, after Codex's
continuation in `docs/CODEX_HANDOFF.md`.

### Setup and iPhone follow-up (2026-09-23, afternoon)

The setup review passed workspace static analysis, formatting (after formatting
the Natural Language Pigeon schema), all 214 package unit tests, and eight
example widget tests. All ten Swift package manifests parse; this is not a
SwiftPM build verification. Flutter 3.47.4 / Dart 3.13.3, Xcode 27.0 and
CocoaPods 1.16.2 are installed. The Apple toolchain passes `flutter doctor`;
the missing Android SDK is unrelated to these Apple-only plugins.

Physical iPhone runs on iOS 27.0 (24A437), via `flutter drive`:

| Package | Passing | Failing | Skipped |
|---|---:|---:|---:|
| apple_natural_language | 15 | 0 | 0 |
| apple_vision_native | 16 | 0 | 0 |
| core_ml | 30 | 0 | 0 |
| apple_sound_analysis | 14 | 0 | 0 |
| apple_speech | 14 | 0 | 0 |
| apple_translation | 23 | 0 | 0 |
| image_playground | 11 | 0 | 0 |
| media_intelligence | 9 | 1 | 1 |
| **Total** | **132** | **1** | **1** |

Counts exclude setup/teardown hooks. Core AI and Foundation Models retain
their prior successful iPhone results; they were not rerun in this pass.
Natural Language's named-entity test now passes without skipping. Translation
has all language packs needed by its suite, and Speech has English assets.

**Open device issue:** Media Intelligence's `finds the second scene as the
highlight` test fails reproducibly. The native framework returns an empty
highlight list and twelve half-second intervals with score zero for the
synthetic clip, before any Pigeon conversion. The failing assertion remains
intact. A fresh macOS run of the same suite passes all ten tests with one
optional skip (`/tmp/apple_ai_setup_media_intelligence_macos.log`). Temporary
native diagnostic logging was removed after verification. Validate highlight
selection with representative real video before
calling this feature device-verified. Real-face grouping remains the optional
skipped test. The cancellation test also emits native store-save errors when
the test purges the library while Apple's work continues; callback and handle
cleanup assertions pass, but this is not proof of native cancellation.

The first Natural Language launch hit stale build output: Xcode succeeded,
but Flutter could not find `build/ios/iphoneos/Runner.app`. `flutter clean`
and `flutter pub get` resolved it. Each remaining example was cleaned before
its run. Allow Local Network access on the phone for each example when using
wireless debugging. Device logs are `/tmp/apple_ai_setup_*_ios*.log`; the
Natural Language log uses `natural_language` without the `apple_` prefix.

No dependencies, global configuration, or runtime behavior were changed.
Documentation and one schema's formatting were updated; nothing was committed.
The initial worktree was clean at `b5ce074`. Free disk space was about 14 GiB
after device builds, so the earlier low-disk and uncommitted-state notes below
are historical.

### Verification

Re-run from clean example builds on macOS 27 on 2026-09-23:
- `dart analyze --fatal-infos packages` and `dart format` are clean.
- Unit tests: 214 pass across the ten packages.
- Framework integration tests: 172 pass. The one skip is media_intelligence's
  optional face-photo test.
- Example-app integration tests: all 10 pass.

| Package | Framework integration tests |
|---|---|
| natural_language | 15 |
| sound_analysis | 14 |
| speech | 14 |
| translation | 23 |
| vision | 16 |
| core_ai | 21 |
| core_ml | 30 |
| foundation_models | 18 |
| image_playground | 11 |
| media_intelligence | 10 |

The iOS example builds succeed for every package.

### Manual checks completed (user confirmation, 2026-09-23)

The user confirmed completion of checklist items 1–3 on the iPhone:

- Speech microphone transcription, stop/finalize and restart.
- Sound Analysis microphone classification, stop and restart.
- Image Playground image creation and return to the Flutter app.

These are user-confirmed manual results, separate from the automated counts
above.

### What is still unverified

- **iPhone highlight selection.** Media Intelligence's synthetic highlight
  test fails on the phone as described above. All other automated framework
  suites now have successful iPhone runs.
- **Manual checks** that need a person or real media:
  - grouping real faces in media_intelligence. Run its integration test with
    `--dart-define=MEDIA_INTELLIGENCE_FACE_DIR=<photos of people>`.
- **Headless image generation isn't possible on 27.** `ImageCreator()`
  throws `notSupported` on macOS 27, even from a foreground app, so
  image_playground bridges only the system sheet.

### Environment

- **Disk space.** The disk filled up during verification: 119 MiB were left
  of 228 GiB. Each example build takes about 750 MB. Delete
  `packages/*/example/build` when you're done; Flutter regenerates it. A
  full disk shows up as strange failures, such as "Failed to obtain model
  compilation cache" and truncated module caches.
- **Git.** Codex created a repository with one commit, `aae85a1`. Everything
  since is uncommitted. Don't commit unless the user asks.
- **Left for the user:** LICENSE, and the podspec homepage and author.

---

## Original handoff (2026-09-22)

Read this, then `docs/CONVENTIONS.md` (binding) and the root `README.md`.

Codex continuation: see `docs/CODEX_HANDOFF.md` for subsequent changes and
verification. The notes below preserve the original handoff, and the status
above supersedes them.

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
| apple_vision_native | A background agent was building it. Read `packages/apple_vision_native/HANDOFF_NOTES.md` if it exists, then verify. |
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
