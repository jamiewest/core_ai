# apple_translation

Flutter bindings for Apple's Translation framework, over Pigeon platform
channels. Translate text between installed languages, translate batches as a
list or stream, preserve selected text, and check language-pack availability.

## Requirements

| Feature | Minimum runtime |
|---|---|
| Language resolution and availability | iOS 18 / macOS 15 |
| Translation sessions without SwiftUI | iOS 26 / macOS 26 |
| Quality/speed strategies and attributed text | iOS 26.4 / macOS 26.4 |

Build with Xcode 27 and Flutter 3.38+. Deployment targets remain iOS 15 and
macOS 12. `Translation.isSupported()` checks language-query support;
**check `Translation.isInstalledSessionSupported()` before translating**.
`Translation.isStrategySupported()` checks the newer strategy and segment APIs.
Unavailable features throw `TranslationErrorCode.unsupported`.

Both languages must already be downloaded on the device. These sessions
cannot display Apple's download UI: `canRequestDownloads` is always false.
No account, API key, Apple Intelligence configuration, or permission prompt
is required by the plugin.

## Quick start

```dart
import 'dart:developer';
import 'package:apple_translation/apple_translation.dart';

Future<void> translateGreeting() async {
  if (!await Translation.isInstalledSessionSupported()) return;
  final status = await const LanguageAvailability().status(from: 'en', to: 'es');
  if (status != LanguageStatus.installed) {
    // Ask the user to install the language packs before trying again.
    return;
  }
  final session = await TranslationSession.create(
    installedSource: 'en',
    target: 'es',
  );
  try {
    final response = await session.translate('Hello, how are you?');
    log(response.targetText); // Hola, ¿cómo estás?
  } finally {
    await session.dispose();
  }
}
```

## Languages and installed packs

```dart
const availability = LanguageAvailability();
final languages = await availability.supportedLanguages;
final status = await availability.status(from: 'en', to: 'fr');
final detectedStatus = await availability.statusForText('Bonjour', to: 'en');
final language = await Language.resolve('zh-Hant');
```

Identifiers are BCP 47 codes, such as `en`, `es`, `pt-PT` and `zh-Hant`.
`Language` exposes minimal and maximal identifiers, language, script, region,
and a localized display name. Equality uses the maximal identifier, so `zh`
and `zh-Hans` compare equal. Supported languages are sorted by identifier.

Status is `installed` (ready), `supported` (needs downloaded packs), or
`unsupported` (cannot translate this pair). `statusForText` detects the source
for its availability check but does not return the detected language.
Session creation still requires an explicit source language.

Omitting `target` lets the system select a target from the user's preferences.
Use the same target, including `null`, when checking availability and creating
the session. The response reports the actual target.

## Batches and cancellation

Given an open `session`:

```dart
const requests = [
  TranslationRequest('Good morning', clientIdentifier: 'greeting'),
  TranslationRequest('Thank you', clientIdentifier: 'thanks'),
];

// Wait for the complete list, in request order.
final responses = await session.translations(requests);

// Or receive results as each finishes. Match them by clientIdentifier.
await for (final response in session.translateBatch(requests)) {
  log('${response.clientIdentifier}: ${response.targetText}');
}
```

A streaming batch starts when listened to. Cancelling its subscription stops
that batch and leaves the session usable. `session.cancel()` permanently
cancels the session: create a new one to resume translation. Finish or cancel
an active stream before disposing its session.

Each session owns a native handle. Always `await session.dispose()` in a
`finally` block. Later use throws `StateError`; a finalizer is only a backstop.
`Translation.liveHandleCount()` supports leak checks, and
`Translation.releaseAll()` releases sessions after a hot restart.

## Strategies and protected text

On iOS/macOS 26.4+, check availability for the same strategy you will use:

```dart
const strategy = TranslationStrategy.lowLatency;
final status = await const LanguageAvailability(
  preferredStrategy: strategy,
).status(from: 'en', to: 'es');
if (status == LanguageStatus.installed) {
  final session = await TranslationSession.create(
    installedSource: 'en', target: 'es', preferredStrategy: strategy,
  );
  try {
    final response = await session.translate('Hello');
    log(response.targetText);
  } finally {
    await session.dispose();
  }
}
```

`highFidelity` favors quality; `lowLatency` favors speed and can require a
separate model download. `LanguageAvailability.defaultStrategy()` reports the
system default, or `null` before strategy support.

With an open session, preserve a name or placeholder with text segments:

```dart
final response = await session.translateSegments(const [
  TextSegment('Hello '),
  TextSegment.skip('Acme Widget'),
  TextSegment(' is great.'),
]);
```

`response.targetSegments` retains the skip flags. Adjacent runs with matching
flags may be merged. Batches accept `TranslationRequest.segments(...)` too.
Dispose the session when finished, as in the quick start.

## Swift → Dart

| Swift | Dart |
|---|---|
| `Locale.Language` | `Language.resolve`, `Language` |
| `LanguageAvailability` | `LanguageAvailability` |
| `supportedLanguages` | `supportedLanguages` |
| `status(from:to:)`, `status(for:to:)` | `status`, `statusForText` |
| `LanguageAvailability.Status` | `LanguageStatus` |
| `TranslationSession(installedSource:target:)` | `TranslationSession.create` |
| `isReady`, `prepareTranslation()` | `isReady`, `prepareTranslation()` |
| `translate(_:)` | `translate`, `translateSegments` |
| `translations(from:)` | `translations` |
| `translate(batch:)` | `translateBatch` stream |
| `TranslationSession.Request`, `.Response` | `TranslationRequest`, `TranslationResponse` |
| `TranslationSession.Strategy` | `TranslationStrategy` |
| `AttributedString` with `translation.skipsTranslation` | `TextSegment`, `TextSegment.skip` |
| `cancel()` | `cancel()` |
| `TranslationError` | `TranslationException`, `TranslationErrorCode` |

## Not bridged

* SwiftUI `.translationTask`, its configuration, and the system translation
  presentation UI. They require a SwiftUI view lifecycle; this plugin exposes
  headless sessions instead. Consequently it cannot start language downloads
  or offer translation sessions on iOS 18–25 / macOS 15–25.
* Automatic source selection for a session. The installed-language initializer
  requires a source. Use a language recognizer first if your app needs this.
* Arbitrary `AttributedString` styling and custom attributes. Only text and
  `skipsTranslation` cross the channel.

## Known platform behavior

* Creating a session does not guarantee that the pair is installed or
  supported. Check availability or `isReady`; `prepareTranslation()` cannot
  download languages for these sessions.
* `translate('')` throws `nothingToTranslate`. An empty entry in a batch
  returns an empty translation. Whitespace-only text passes through.
* Identical source/target languages are unsupported. Unknown languages give
  `unsupportedSourceLanguage` or `unsupportedTargetLanguage`.
* A session does not auto-detect text written in another language. During
  probing, French text sent to an English-source session came back unchanged.
* Installed packs can differ by strategy. On the test Mac, high-fidelity
  English→Spanish worked while low latency reported `notInstalled`.
* Exact wording can vary with Apple's models. Integration tests assert known
  translated phrases, response metadata, cancellation, and resource cleanup.

## Errors

`TranslationException` contains a stable `TranslationErrorCode`, a readable
message and optional native details. Codes cover unavailable OS features,
invalid arguments/handles, unsupported languages/pairs, unidentified language,
empty input, missing packs, cancellation and framework failures. Do not parse
localized messages to choose recovery behavior; use `error.code`.

## Example and development

Verified on macOS 27 with Xcode 27: 36 API unit tests, four example widget
tests, all 23 framework integration tests, and one app integration test pass
with no skips. The iOS device debug build succeeds; runtime testing on an
iPhone remains pending.

The Material example selects languages and translation strategies, checks
installed packs, translates text, and streams one response per nonempty input
line. It displays capability and missing-pack notices without initiating
downloads. See [example/README.md](example/README.md).

```sh
dart run pigeon --input pigeons/apple_translation_api.dart
dart format lib/src/messages.g.dart
flutter analyze
flutter test
cd example
flutter test
flutter test integration_test/apple_translation_test.dart -d macos
flutter test integration_test/app_test.dart -d macos
flutter build ios --no-codesign --debug
```

Run macOS integration files one at a time. Tests requiring an uninstalled pair
report a skip; a skipped translation is not evidence that inference worked.
`package:apple_translation/testing.dart` exposes injectable bindings for fakes.

For an unlocked physical iPhone with developer mode enabled:

```sh
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/apple_translation_test.dart -d <device-id> \
  --publish-port
```
