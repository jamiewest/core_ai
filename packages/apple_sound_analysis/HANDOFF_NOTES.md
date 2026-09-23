# apple_sound_analysis handoff (2026-09-23)

Status: implementation complete; all automated checks pass. Live microphone
capture and iPhone runtime verification remain pending. No commits, new
dependencies, or global configuration changes were made.

## Implementation

The original Pigeon schema and generated messages are unchanged. Completed
the Swift host API and plugin registration around Claude's `Analyses.swift`
and `Errors.swift`. The Dart public API is now:

* `SoundClassifier.builtIn` / `.model` and `info()`.
* `SoundAnalyzer.isSupported`, `classifyFile`, `classifyMicrophone`, `cancelAll`.
* `SoundStreamClassifier.create`, `results`, `add`, `close`, `cancel`.
* `MicrophonePermission.status` / `.request`.
* Immutable classifier info, classification windows and labels; typed errors.
* `testing.dart` exposes bindings, callback routes and generated wire types.

All three inputs produce single-subscription result streams. Routes are
registered before native startup; results arriving before startup returns
are buffered. Subscription cancellation waits for pending startup before
cancelling native work. `cancelAll` prevents new starts during cancellation,
waits for starts, cancels native requests, and closes Dart streams. PCM adds
copy the supplied view, serialize writes, and encode little-endian float32.
`close()` flushes input; consume results until stream completion afterward.

Native setup/model-cache work runs on a serial queue. Window constraints,
overlap, result limits, PCM sample rates/channels, whole frames and finite
samples are validated before entering the framework. Event delivery is
serialized on the main actor, so completion cannot overtake earlier results.
Stopped requests drop queued callbacks. Duplicate request IDs are rejected
without stopping existing work.

Microphone setup checks permission without prompting and permits one capture
per engine. Tap buffers are copied before asynchronous analysis. On iOS the
recording session's previous category/mode/options are restored after stop
or setup failure; the previous active state cannot be queried, so callers
that also play audio must manage their own reactivation.

Custom models compile/cache by standardized path for the engine lifetime.
Compiled temporary models are retained until plugin detachment. `cancelAll`
does not clear that cache. Use a different path or recreate the engine to
reload changed model contents.

## Verified

* 16 Dart unit tests with hand-written fakes: early callbacks, delayed-start
  cancellation, stream errors, cancellation isolation, PCM view copying,
  serialized writes/flush, rejected-write recovery and cleanup.
* 14 real-framework macOS integration tests: 303 built-in labels, speech
  confidence above 0.7, 3 s windows starting at 0 / 1.5 s, custom speech/tone
  confidence above 0.95, mono and stereo PCM classification, validation,
  cancellation, duplicate IDs, and no leftover native analyses.
* One macOS app test drives speech, custom tone, and PCM tone classification.
  Missed taps are fatal; results and zero leaked analyzers are asserted.
* `dart analyze --fatal-infos packages`: clean across the workspace.
* Dart formatting check: zero changes. Modified Swift files formatted with
  the installed `swift-format`.
* `flutter build ios --no-codesign --debug`: succeeds, last Xcode build 8.2 s.
  The native code also compiled at the macOS 12 deployment target.

Tests never request microphone permission or record the microphone. They
query authorization and verify `permissionDenied` when unauthorized. An
iOS build is not an iPhone runtime result.

## Example and configuration

The Material app provides file/PCM/microphone buttons, a custom-model toggle,
Stop, light/dark themes, capability notices, errors and the latest 40 windows.
It extracts only bundled fixtures into a private temp directory and removes
them on disposal. Added microphone usage text to both Info.plists and the
audio-input entitlement to both macOS entitlement files. No framework linker
entries or podspec changes were needed.

The test driver supports `flutter drive` on a physical device. Run macOS
integration files individually. See the README for commands and API samples.

## Corrections to original handoff assumptions

* Swift exposes the error enumeration as `SNError.Code`, not `SNErrorCode`.
* The built-in window range ends at 15.0000625 seconds on this SDK, not
  exactly 15. The end is exclusive; validation uses `CMTimeRangeContainsTime`.
* The custom model's default is 0.975 seconds, but that is not its only valid
  duration. Query `info()` instead of treating it as a fixed-window model.

Logs: `/tmp/core_ai_codex_sound_{unit_final,macos_final,app_macos,ios_build_final,workspace_analysis}.log`.
The root `docs/CODEX_HANDOFF.md` records the durable snapshot location.
