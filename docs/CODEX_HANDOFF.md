# Codex continuation (updated 2026-09-23)

> Superseded: image_playground and media_intelligence were finished after
> this was written. See "Current status" at the top of `docs/HANDOFF.md`.

Status: Codex is completing `packages/image_playground` only.
Original snapshot: `/Users/jamie/Developer/core_ai_backups/image_playground_20260923_pu8j2z1z`.
Speech is complete; existing changes elsewhere are preserved. Speech originals, completed source, checksums and logs:
`/Users/jamie/Developer/core_ai_backups/speech_20260923_x9ng2hr2`.
A Git repository now exists (initial commit `aae85a1`); earlier no-Git notes
below are historical. Existing SoundAnalysis changes were preserved.

A durable completed snapshot, surviving original files,
and test logs are saved at:
`/Users/jamie/Developer/core_ai_backups/sound_analysis_20260923_pdr1c1od`.
The earlier SoundAnalysis temporary backup is now incomplete after the
overnight pause; it must not be treated as a full original baseline.
Translation is also finished. The user requested
one package at a time, starting with those closest to completion.
Translation source backup:
`/var/folders/54/d3l1d78d4ds62ghx9393wypc0000gn/T/core_ai_translation_codex_jld10hko`.
Read `HANDOFF.md` and `CONVENTIONS.md` for the original context. The entries
below supersede the older status notes where they differ.

The workspace has no `.git` directory. Originals of edited existing files
and source hashes were saved at:
`/var/folders/54/d3l1d78d4ds62ghx9393wypc0000gn/T/core_ai_codex_handoff_yk0r0z4i`.

No commits, global configuration changes, or dependency additions. Existing
Claude processes were left alone. The selected source trees were idle before
editing, and a final comparison found no unexpected source edits there.

## Speech completion (fourth continuation)

Completed `apple_speech` on 2026-09-23, continuing Claude's existing native
implementation and partial Dart files. Finished analyzer/recognizer/assets/
permission APIs, typed results, buffered/cancellable requests, testing bindings,
Material 3 example, synthetic fixture, tests and docs.

Fixed startup/duplicate-ID cleanup, terminal callback ordering, retained
microphone buffers, conversion-error propagation and iOS session restoration.
The schema was formatted; generated messages were unchanged. No dependencies,
global settings or commits. Existing Claude processes and other package source
were left alone. iOS CocoaPods build wiring was generated normally and kept.

Verified: 17 API unit + four widget + 14 framework integration + one real app
integration test = **36 passing tests**, no skips. Tests verify exact speech
text, word times/confidence, UTF-16 ranges, dictation, file/media/simulated-live
sources, finalization, errors, cancellation and zero leaked requests. The iOS
unsigned device build succeeds (14.6 s); workspace analysis and formatting are
clean. The example test requires real output and makes missed taps fatal.

Manual checks remain: live microphone hardware, iPhone runtime, authorized
legacy recognition, model downloads and locale-reservation mutations. Tests
never prompt, record, download assets or change reservations. An iOS build is
not a runtime result. Apple's aggregate asset status reported `supported` even
for an installed working English model; the API also checks installedLocales.
Detector-only analysis is rejected to prevent a native trap; detector alongside
transcription produced no independent events on this Mac.

Detailed takeover notes: `packages/apple_speech/HANDOFF_NOTES.md`.
Final logs: `/tmp/core_ai_codex_speech_{unit_final,macos_final,app_macos,ios_build,workspace_analysis}.log`,
also copied into the durable backup's `logs/` directory.

**Next: ImagePlayground, then MediaIntelligence**, both still scaffolds. Keep
working one package at a time and recheck for active edits. Manual/device
verification may be handled separately. All older “Speech next” entries below
are historical checkpoints superseded by this completion.

## SoundAnalysis completion (third continuation)

Completed `apple_sound_analysis` on 2026-09-23. The Pigeon schema/generated
messages were already present and are unchanged. Added the Swift host API,
plugin registration, public Dart API, callback routing, test bindings,
example, tests, and docs around Claude's original native analysis classes.

Features: built-in/custom Core ML classifiers; labels/window constraints;
file, pushed float32 PCM, and microphone classification; typed results and
errors; permission queries/requests; cancellation and cancel-all cleanup.
The example has speech/tone/PCM buttons, a custom-model toggle, explicit
microphone permission flow and Stop. App permissions and macOS audio-input
entitlements are configured.

Lifecycle fixes include native event ordering, copied microphone tap buffers,
serialized/copied PCM input, cancellation during startup, duplicate-ID
protection, and iOS audio-session category restoration. Fixed the unfinished
native error enum reference (`SNError.Code`). Models and compiled temporary
files are cached for the engine lifetime; cancel-all does not clear the cache.

Verified results, all without skips:

* 16 Dart unit tests with fakes.
* 14 real-framework macOS integration tests (speech/tone confidence and timing,
  mono/stereo PCM, constraints, malformed input, duplicate IDs and cleanup).
* One real-framework macOS example integration test.
* Final iOS device debug build succeeds (8.2 s Xcode build).
* Workspace static analysis clean; Dart formatting produces no changes.

Live microphone capture and iPhone runtime testing are still unverified.
Automated tests do not request permission or record the microphone. Use the
example's Listen and Stop buttons for a manual microphone check. An iOS
build result is not a device-runtime result.

The built-in maximum window is an exclusive upper bound of 15.0000625 s on
this SDK, and the custom fixture's default 0.975 s is not its only valid
window. The API exposes the real model constraints and validates against
them. These correct two assumptions in the original SoundAnalysis notes.

Source changes are confined to `packages/apple_sound_analysis`, plus the root
README and this handoff. No dependencies, global settings, or other package
implementations changed. No commits. Generated Flutter/Xcode build artifacts
were refreshed normally.

Main files: native `AppleSoundAnalysisHostApiImpl.swift`, plugin registration,
`Analyses.swift` and `Errors.swift`; Dart `lib/src/{sound,bindings,errors}.dart`,
public exports and `testing.dart`; `test/api_test.dart`; example
`lib/{main,fixtures}.dart`, two integration tests, test driver, asset manifest,
microphone usage strings and entitlements; README, CHANGELOG and package
`HANDOFF_NOTES.md`.

Detailed package handoff: `packages/apple_sound_analysis/HANDOFF_NOTES.md`.
Final logs are copied into the durable snapshot's `logs/` directory, as well
as `/tmp/core_ai_codex_sound_{unit_final,macos_final,app_macos,ios_build_final,workspace_analysis}.log`.

**Next package: Speech.** Recheck for active edits, then use its existing
handoff to finish the remaining Dart API, tests, example and docs. Keep
ImagePlayground and MediaIntelligence for later; both remain scaffolds.
Unlocked-device verification can be a separate pass.

## Translation completion (second continuation)

`apple_translation` now meets the package definition of done for its existing
installed-language API. No native/plugin API implementation changes were
needed. The example is a Material app with light/dark themes, supported
language selection, quality/speed strategies, pack availability/refresh,
single-text translation and streaming per-line batches. Controls explain
unsupported OS versions and missing packs; every translation operation
disposes its session in `finally`.

Verification on macOS 27 / Xcode 27:

* 36 API unit tests pass.
* Four new widget tests pass, including missing-pack refresh and disabled
  translation on unsupported platforms/pairs, with a 390-pixel viewport.
* All 23 framework integration tests pass with no skips. The system-selected
  target test now checks availability using `to: null`, matching its session.
* One new app integration test passes: real greeting translation, streamed
  Spanish phrases, line identifiers, and zero leaked sessions. Missed taps
  are fatal.
* iOS device debug build succeeds. Runtime verification on an iPhone remains
  pending; no phone test was attempted in this continuation.
* Formatting and workspace static analysis are clean.

Changed files in this continuation:

* `packages/apple_translation/example/lib/main.dart`: replaced TODO app.
* `packages/apple_translation/example/integration_test/app_test.dart`: new.
* `packages/apple_translation/example/test/app_test.dart`: new.
* `packages/apple_translation/example/test_driver/integration_test.dart`: new.
* `packages/apple_translation/example/integration_test/apple_translation_test.dart`:
  formatting and system-selected-target availability correction.
* Package README, CHANGELOG, HANDOFF_NOTES and example README: actual feature
  coverage, usage, requirements, limitations and verified results.
* Root README: Translation now marked done; this handoff updated.

No dependencies or global configuration changed, and nothing was committed.
The package was idle before editing. No other package's source was edited.
Ordinary generated Flutter/Xcode artifacts were refreshed by the builds.

Logs: `/tmp/core_ai_codex_translation_{unit_final,widgets,macos_final,app_macos,ios_build,workspace_analysis}.log`.
Source backups are at the Translation path near the top of this file.

SwiftUI sessions/download UI, automatic source selection for sessions, and
general attributed-string styling remain explicitly unbridged. Source and
target packs must be installed; low latency may need different packs. See
the package README and HANDOFF_NOTES for details.

This checkpoint's next task was SoundAnalysis, now completed above. Speech
is next; ImagePlayground/MediaIntelligence remain scaffolds. Device reruns
can be handled when the iPhone is unlocked.

## Earlier continuation

The sections below record the previous pass; the Translation section above
supersedes their earlier Translation inventory and changed-file statements.

### apple_natural_language

The named-entity integration test now calls `Tagger.requestAssets` for English
`nameType` before tagging. Empty output still fails. Only the documented iOS
case where every returned token is `Other` is skipped, with an explicit
reason and the asset request result. Other incorrect tags still fail; macOS
retains its strict named-entity assertions. README and CHANGELOG document the
behavior and accurately distinguish the old phone run from this rerun.

Fresh verification: 14 unit tests, 15 macOS integration tests (no skips), and
the macOS example app test pass. The iPhone test build succeeded in 16.9 s,
but Flutter never discovered the Dart VM service over wireless. A read-only
`devicectl device info lockState` query reported `passcodeRequired: true`.
Stopped only this continuation's Flutter drive process with SIGINT (PID
71397); it has exited. Its exit code was 0 despite being interrupted, so it
is **not a passing device test**. No phone test result was received.

When the phone is unlocked, rerun from `packages/apple_natural_language/example`:

```sh
flutter drive --no-pub --driver=test_driver/integration_test.dart \
  --target=integration_test/apple_natural_language_test.dart \
  -d 00008150-001229241AF8401C --publish-port
```

If the suite skips named entities, report that separately from passing tests.
Do not claim iOS tagging was verified merely because the runner exits 0.

### apple_vision_native

The README already existed beyond the original handoff's stated progress.
Reviewed it, replaced `print` in the quick start with `dart:developer` logging,
and corrected the Core ML/Core AI explanation: `core_ml` runs Core ML models
directly but does not bridge them into Vision requests; `core_ai` runs
`.aimodel`. Expanded the initial CHANGELOG and recorded fresh verification.
Formatted the Pigeon schema only; the wire API and generated code are unchanged.

All 18 unit tests and 16 macOS integration tests pass. First accurate OCR took
about 70 s; the suite took 1:47 after launch. The iOS device debug build passes.
Formatting and static analysis are clean. Updated the package handoff and
root status to done for the implemented still-image API. iOS runtime tests
were not run. The documented unbridged requests remain unimplemented.

### core_ml

Verified the existing implementation: 29 unit tests, 30 macOS integration
tests, and the iOS device debug build pass. Formatting is clean.

Found a false pass in the example integration test: scrolling a Card into
view left its Run button below the window, so a tap missed and the test still
passed. The test now scrolls to the button, requires it to be hit-testable,
makes missed taps fatal (restoring the global test setting afterward), and
requires each demo to finish with nonempty SelectableText output without an
error. The corrected macOS app test passes in 4 s without the missed-tap
warning. No runtime implementation changed. Updated the root status to done.

### Workspace inventory

`dart analyze --fatal-infos packages` passes for the entire workspace,
including after the Core ML test correction. Translation's 36 unit tests
also pass; its integration test file exists, but the example app still says
TODO. Its integration suite was not run here. Root README now labels Speech,
SoundAnalysis and Translation as in progress instead of not started, and
removes the inaccurate claim that all unfinished packages are empty scaffolds.

## Files edited

* `README.md`: verified statuses and accurate partial-package descriptions.
* `docs/HANDOFF.md`: added a pointer to this continuation, preserving old notes.
* `docs/CODEX_HANDOFF.md`: this new record.
* `packages/apple_natural_language/example/integration_test/apple_natural_language_test.dart`
* `packages/apple_natural_language/README.md`
* `packages/apple_natural_language/CHANGELOG.md`
* `packages/apple_vision_native/README.md`
* `packages/apple_vision_native/CHANGELOG.md`
* `packages/apple_vision_native/HANDOFF_NOTES.md`
* `packages/apple_vision_native/pigeons/apple_vision_native_api.dart`: formatting only.
* `packages/core_ml/example/integration_test/app_test.dart`

Builds also refreshed ordinary generated Flutter/Xcode artifacts. No source
in Speech, SoundAnalysis, Translation, ImagePlayground, MediaIntelligence,
Foundation Models, or Core AI was edited.

## Logs and next work

Local logs are in `/tmp/core_ai_codex_*.log`: `vision_macos`,
`vision_ios_build`, `natural_language_macos`, `natural_language_app_macos`,
`natural_language_ios`, `core_ml_unit`, `core_ml_macos`, `core_ml_ios_build`,
`core_ml_app_macos` (original false pass), `core_ml_app_macos_fixed`,
`translation_unit`, and `workspace_analysis_final`.

Builds emitted an existing missing Metal toolchain search-path warning but
succeeded. macOS runners reported inability to foreground their windows but
completed the tests. Free disk space was about 4.3 GiB during verification;
no files were deleted to make space.

Next: finish SoundAnalysis using the detailed checklist in the original
handoff, or finish Translation's example/docs and verify its integration
suite. Speech still needs the rest of its Dart API and tests. ImagePlayground
and MediaIntelligence remain scaffolds. Recheck for active edits before
claiming a package. License/author/homepage decisions remain with the user.
