# image_playground

Flutter bindings for Apple's **Image Playground**, the Apple Intelligence
image creator, built on [Pigeon](https://pub.dev/packages/pigeon) platform
channels.

Open Apple's Image Playground sheet from Flutter, seeded with text, extracted
concepts, images or PencilKit drawings. Pick the allowed styles and creation
options, and get back the image the user created.

```dart
import 'package:image_playground/image_playground.dart';

final capabilities = await ImagePlayground.capabilities();
if (capabilities.isAvailable) {
  final result = await ImagePlayground.present(
    concepts: [ImagePlaygroundConcept.text('A lighthouse at sunset')],
  );
  if (result != null) {
    // result.bytes is a PNG; show it with Image.memory(result.bytes).
  }
}
```

## Requirements

| | |
|---|---|
| The sheet, text, image and drawing concepts | iOS 18.1+ / macOS 15.1+ with Apple Intelligence |
| Styles, personalization | iOS 18.4+ / macOS 15.4+ |
| `externalProvider` style | iOS 26+ / macOS 26+ |
| `CreationVariety` | iOS 26.4+ / macOS 26.4+ |
| `any` style, `CreationStrategy`, requested size | iOS 27+ / macOS 27+ |
| Builds for | iOS 15+ and macOS 12+ |
| Toolchain | Xcode 27, Flutter 3.38+ |

`isSupported()` says whether the framework exists on this OS.
`capabilities().isAvailable` says whether the sheet can be shown right now:
Apple Intelligence may be off, or its models may still be downloading.

An option the OS doesn't support throws `ImagePlaygroundErrorCode.unsupported`
rather than being silently ignored. Check `capabilities()` first.

**Tested:** 17 unit tests, 11 integration tests and the example app test pass
against the real framework on macOS 27. The integration tests configure real
controllers and open and cancel a real sheet. All 11 integration tests also
pass on the iOS 27 iPhone. The user confirmed manual image creation and return
to the Flutter app on 2026-09-23; image creation is not automated.

## Sessions

`ImagePlayground.present(...)` prepares a sheet, shows it and cleans up.
It returns null if the user cancels. To cancel the sheet from your own UI,
use a session:

```dart
final session = await ImagePlayground.prepare(
  concepts: [ImagePlaygroundConcept.extracted(articleText, title: 'Trip')],
  sourceImage: ImageInput.file(photoPath),
  allowedStyles: [ImagePlaygroundStyle.illustration],
  options: const ImagePlaygroundOptions(
    variety: CreationVariety.high,
    strategy: CreationStrategy.generateNew,
    size: ImageSize(1024, 1024),
  ),
);
final pending = session.present();
// Later, for example when the screen closes:
await session.cancel(); // pending completes with null
await session.dispose();
```

`prepare` validates and decodes every input but shows nothing. A session can
be presented once. Only one sheet can be open at a time; a second throws
`busy`.

## Results

`ImagePlaygroundResult.bytes` is a PNG (`typeIdentifier` `public.png`),
copied out of Apple's temporary file before the sheet closes. An `emoji`
style result is an adaptive image glyph instead: `isAdaptiveImageGlyph` is
true, `bytes` holds Apple's glyph data, and `contentIdentifier` and
`contentDescription` are set.

## Inputs

`ImageInput.file`, `ImageInput.encoded` (PNG, JPEG, HEIC, …) and
`ImageInput.pixels` (BGRA, premultiplied alpha) are accepted as a source
image or an image concept. Images are limited to 64 MiB, 16384 pixels per
edge and 64 megapixels. `ImagePlaygroundConcept.drawing` takes serialized
`PKDrawing` data.

## Swift → Dart

| Image Playground (Swift) | image_playground (Dart) |
|---|---|
| `ImagePlaygroundViewController`, `.isAvailable` | `ImagePlaygroundSession`, `ImagePlayground.capabilities()` |
| `concepts`, `sourceImage` | `prepare(concepts:, sourceImage:)` |
| `ImagePlaygroundConcept.text/extracted/image/drawing` | `ImagePlaygroundConcept.text/extracted/image/drawing` |
| `allowedGenerationStyles`, `selectedGenerationStyle` | `allowedStyles`, `selectedStyle` |
| `ImagePlaygroundStyle` | `ImagePlaygroundStyle` |
| `ImagePlaygroundOptions` (personalization, variety, strategy, size) | `ImagePlaygroundOptions` |
| `personalizationPolicy` (before 26.4) | `ImagePlaygroundOptions.personalization` |
| `Delegate` `didCreateImageAt` / adaptive glyph / `DidCancel` | `session.present()` result or null |

## Not bridged

* `ImageCreator`, the programmatic generator. It is deprecated in iOS 27 /
  macOS 27, and on macOS 27 `ImageCreator()` throws `notSupported`, even
  from a foreground app where the sheet is available. Image creation goes
  through Apple's interface.
* The SwiftUI `imagePlaygroundSheet` modifier. It does the same as
  `ImagePlaygroundViewController`, which this package presents.

## Errors

Every failure is an `ImagePlaygroundException` with an
`ImagePlaygroundErrorCode`:
- `unsupported`: the OS is too old for the feature.
- `unavailable`: Apple Intelligence is not ready.
- `invalidArgument`, `invalidHandle`, `notFound`, `imageError`.
- `invalidState`: a session was presented twice.
- `busy`: a sheet is already open.
- `noPresenter`: no Flutter view to present from.
- `unknown`.

## Resources

Call `dispose()` on sessions. A `Finalizer` releases forgotten ones
eventually. After a hot restart, `ImagePlayground.releaseAll()` closes any
open sheet. `ImagePlayground.liveHandleCount()` helps check for leaks.

## Development

```sh
dart run pigeon --input pigeons/image_playground_api.dart
flutter test
cd example
flutter test integration_test/image_playground_test.dart -d macos
flutter test integration_test/app_test.dart -d macos

# On a physical device (wireless debugging needs flutter drive):
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/image_playground_test.dart -d <device id> \
  --publish-port
```

Run integration test files one at a time on macOS. The integration tests
open a real sheet briefly, and need Image Playground to be available.
`package:image_playground/testing.dart` lets you replace
`ImagePlaygroundBindings.instance` with fakes.
