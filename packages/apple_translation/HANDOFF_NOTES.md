# apple_translation handoff notes

Status: COMPLETE for the installed-language API. Codex finished the example,
docs, tests and build verification on 2026-09-22. Runtime testing on an iPhone
is still pending. No commits or dependency changes were made.

## Done so far
- Pigeon schema `pigeons/apple_translation_api.dart` (PlatformApi, HostApi,
  CallbackApi for streaming batches); generated Dart and Swift.
- Swift: `AppleTranslationPlugin.swift`, `Errors.swift`, `HandleRegistry.swift`
  (sessions plus a RequestRegistry for batch tasks), `Conversions.swift`,
  `AppleTranslationHostApiImpl.swift`. Typecheck is clean with
  `swiftc -typecheck` against arm64-apple-macos12.0 and arm64-apple-ios15.0.
- Dart: `lib/src/{errors,bindings,native_resource,models,
  language_availability,session,translation}.dart`, `lib/testing.dart`.
- Unit tests: `test/api_test.dart`, 36 tests passing. `flutter analyze` is
  clean.

## Completed by Codex
- Existing framework integration suite: 23 tests pass, no skips. Corrected
  the system-selected-target test to check availability with a null target
  instead of checking English to Spanish, which might be a different pair.
- Material example with light/dark themes, source/target language selection,
  model strategy selection, installed-pack status and refresh, text input,
  single translation and streamed per-line translation. Every operation
  disposes its native session in `finally` and guards post-await UI updates.
- Four widget tests cover unsupported platforms, older OS session limits,
  unsupported pairs, missing packs and refresh at a narrow viewport.
- App integration test drives single and batch translation against the real
  framework, asserts Spanish results and line identifiers, and checks zero
  live handles. Missed taps are fatal. Passes on macOS in about 7 seconds.
- Added `example/test_driver/integration_test.dart` for physical devices.
- README, CHANGELOG and example README now cover actual API behavior and
  limitations, especially preinstalled packs and no system download UI.
- 36 API unit tests pass; package/example static analysis and formatting are
  clean. `flutter build ios --no-codesign --debug` succeeds (15.1 s Xcode build).

## Remaining / intentionally unbridged
- Optional iPhone runtime verification with installed language packs.
- SwiftUI-hosted sessions, download/presentation UI, automatic session source
  detection, and arbitrary attributed-string styling are not bridged. These
  limitations are documented; the example does not request downloads.
- License and package author/homepage metadata remain user decisions.

See `../../docs/CODEX_HANDOFF.md` for backup location and verification logs.

## Probe findings (macOS 27, Swift probes in the scratch dir)
- 47 supported languages. Every non-English language is installed for en to X
  and X to en on this Mac.
- `TranslationSession(installedSource:target:)` works headless. Its
  `canRequestDownloads` is false.
- en→es "Hello, how are you?" gives "Hola, ¿cómo estás?". en→fr gives
  "Bonjour, comment allez-vous ?". en→de gives "Hallo, wie geht es dir?".
- "" gives nothingToTranslate. Whitespace-only text comes back unchanged. An
  empty string inside a batch returns "".
- en→en gives unsupportedLanguagePairing, a tlh source gives
  unsupportedSourceLanguage, and a tlh target gives unsupportedTargetLanguage.
- Any call after `cancel()` fails with alreadyCancelled; cancel is permanent.
- `status(for: "")` and `status(for: "1234 5678")` give
  unableToIdentifyLanguage.
- Low latency: status en→es is `supported` (not installed), and translate
  throws notInstalled.
- The skipsTranslation attribute survives a round trip in attributed runs.
- Source is required for direct sessions, so there is no auto-detection.
  French text sent to an en→es session came back unchanged.
- In the SwiftUI `.translationTask` hosted in a CLI NSWindow probe, the task
  fired, but `prepareTranslation` (with source nil and with source fr) never
  completed within 30s. Not bridged; documented instead.
- No 27-only APIs are present in the Translation or _Translation_SwiftUI
  interfaces.
