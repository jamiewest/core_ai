# Package conventions

Every package in this monorepo is a Flutter plugin that wraps one Apple
framework for iOS and macOS through Pigeon platform channels. The packages are
independent (no shared runtime dependency), so they follow the same
conventions instead. **`packages/core_ai` is the reference implementation**:
when in doubt, copy what it does.

## Layout

```
packages/<pkg>/
  pubspec.yaml                  # resolution: workspace; sharedDarwinSource
  pigeons/<pkg>_api.dart        # the Pigeon schema (single source of truth)
  pigeons/copyright.txt
  darwin/<pkg>.podspec          # CocoaPods
  darwin/<pkg>/Package.swift    # Swift Package Manager
  darwin/<pkg>/Sources/<pkg>/
    <Prefix>Plugin.swift        # registration only
    Messages.g.swift            # generated
    Errors.swift                # error codes + translate()
    HandleRegistry.swift        # if the package has native objects
    ...                         # one file per concern
  lib/<pkg>.dart                # public exports only
  lib/testing.dart              # exports bindings + messages for fakes
  lib/src/...                   # implementation, messages.g.dart
  test/                         # Dart unit tests against fakes
  example/lib/                  # small Material 3 demo app
  example/integration_test/     # real-framework tests
```

`<Prefix>` is the framework name, for example `FoundationModels`,
`AppleVision`, `CoreML`.

## Workspace rules

* The root `pubspec.yaml` is a pub workspace. Do not edit it, and do not add
  dependencies. Allowed dependencies are `flutter`, `meta` and, for
  development, `pigeon`, `flutter_test`, `integration_test` and
  `flutter_lints`. Ask before adding anything else.
* Do not edit other packages.
* Do not commit.

## Pigeon

* Use Pigeon 29. Configure `dartOut: lib/src/messages.g.dart`,
  `swiftOut: darwin/<pkg>/Sources/<pkg>/Messages.g.swift`,
  `SwiftOptions(errorClassName: '<Prefix>PigeonError')` and
  `copyrightHeader: 'pigeons/copyright.txt'` (see
  `packages/core_ai/pigeons/core_ai_api.dart`).
* Regenerate with `dart run pigeon --input pigeons/<pkg>_api.dart`, then
  `dart format lib/src/messages.g.dart`.
* Suffix every message type with `Message` so it cannot clash with Apple's
  Swift types. The public Dart API defines its own idiomatic types and
  converts to and from messages.
* A field may not be named `description` (it clashes with Swift's
  `CustomStringConvertible`).
* Sealed classes work for Swift and Dart. Typed data travels as `Uint8List`.

### Three APIs per package

1. **`<Prefix>PlatformApi`** (`@HostApi`). Always registered. At minimum it
   has `bool isSupported()`, plus any availability details that make sense
   without the framework.
2. **`<Prefix>HostApi`** (`@HostApi`). Registered only when the framework is
   available (`#if canImport(...)` plus `if #available(...)`). Dart receives a
   `channel-error` `PlatformException` when it is missing and maps that to the
   `unsupported` error code.
3. **`<Prefix>CallbackApi`** (`@FlutterApi`), only if needed. This is how
   native code calls Dart: streaming events (partial LLM output, live
   transcription, sound classifications) and callbacks that return values
   (LLM tool calls). Every event carries the `requestId` or handle it belongs
   to.
   * Dart registers the handler once, in the bindings constructor
     (`<Prefix>CallbackApi.setUp(handler)`), so nothing is lost to a
     subscription race.
   * Dart exposes a `Stream` backed by a `StreamController` keyed by request
     ID. Cancelling the subscription calls a host `cancel(requestId)`, which
     cancels the Swift `Task`.
   * Swift creates the FlutterApi object at registration with the plugin's
     messenger. Pigeon 29 makes async FlutterApi methods `@MainActor`, so call
     them with `await` from any context.
   * Prefer this over `@EventChannelApi`.

### Threading

Pigeon runs `@async` host methods as `Task { @MainActor in try await
api.method() }`. The implementation's methods are nonisolated `async` in Swift
5 language mode, so their bodies run **off** the main thread. Make any method
that can take more than about a millisecond `@async`: model loading,
inference, image decoding, copying large data, and releasing handles that own
big objects. Keep synchronous methods trivial.

## Availability gating (important)

* Wrap every file that imports the Apple framework in
  `#if canImport(<Framework>) ... #endif`. Mark its types
  `@available(iOS X, macOS Y, *)` using the framework's real availability
  from its swiftinterface.
* **Never** list the framework in the podspec (`weak_frameworks`) or in
  `Package.swift` linker settings. Some frameworks are missing from the iOS
  Simulator SDK, and an explicit link breaks simulator builds. Because every
  use is behind `@available`, the linker weak-links the framework
  automatically.
* The plugin's minimum deployment target stays at iOS 15 / macOS 12. On older
  systems `isSupported()` returns false.

## Native objects (handles)

Native objects such as sessions, models and analyzers live in a thread-safe
`HandleRegistry` keyed by `Int64` handles; copy the one from `core_ai`.
Provide:

* `release(handle)` (`@async`)
* `releaseAll()`
* `liveHandleCount()`

On the Dart side, each owner extends a `NativeResource`-style base (see
`core_ai/lib/src/native_resource.dart`). It has `dispose()` and a `Finalizer`
backstop, and throws `StateError` when used after dispose.

## Errors

* Swift has an `ErrorCode` enum of stable snake_case codes, and a
  `translate(_ error:)` that maps the framework's errors to
  `<Prefix>PigeonError(code:message:details:)`. Put the underlying Swift error
  in `details`.
* Dart has a `<Prefix>Exception implements Exception` with a
  `<Prefix>ErrorCode` enum (including `unsupported` and `unknown`), and a
  `guardPlatformCall` helper that converts `PlatformException`.
* Validate arguments in Swift before calling framework APIs that trap on bad
  input.

## Dart API style

* Mirror Apple's type and method names, with idiomatic Dart shapes: named
  parameters, `Future`s, `Stream`s, sealed classes and immutable value types.
* Put a doc comment on every public member. Keep lines to 80 characters or
  fewer. Run `dart format`, and make sure `flutter analyze` is clean.
* Use `dart:developer` `log()` instead of `print`.
* Bindings are injectable for tests: `<Prefix>Bindings.instance =
  <Prefix>Bindings(host: fake, ...)` (see `core_ai/lib/src/bindings.dart`),
  exported from `lib/testing.dart`.
* Images passed from Dart use a sealed `ImageInput` with `file(path)`,
  `encoded(bytes)` and `pixels(width, height, bgra bytes)` cases unless the
  framework needs something else.

## Tests (required)

* **Unit tests** in `test/`, against hand-written fakes that implement the
  generated host APIs (`noSuchMethod` for the rest). No mocking packages.
* **Integration tests** in `example/integration_test/<pkg>_test.dart`
  against the real framework on this Mac (macOS 27). Run one file at a time:
  `cd packages/<pkg>/example && flutter test integration_test/<file>.dart -d macos`.
  Assert concrete, known outputs. Add a `tearDown` that checks
  `liveHandleCount() == 0` when the package has handles.
* Integration tests must not wait on permission prompts (microphone, speech
  recognition, photos). Use bundled files and APIs that don't need
  authorization, and handle "not authorized" explicitly otherwise.
* Keep example assets small (under a few MB) in `example/assets/`.

## Example app

A small Material 3 app with light and dark themes that demonstrates the main
features against real data. It shows a clear notice when
`isSupported()` is false. Guard `setState` after `await` with `mounted`.

## Definition of done

* `flutter analyze` is clean, `dart format` produces no changes, and unit
  tests pass.
* The integration tests pass on macOS 27 with the real framework.
* `flutter build ios --no-codesign --debug` succeeds in `example/`.
* The README has requirements, a quick start, a Swift→Dart mapping table,
  what isn't bridged and why, and known platform behavior. The CHANGELOG is
  written.

## Hard rules for implementers

* Never add the Apple framework to the podspec (`frameworks` /
  `weak_frameworks`) or to `Package.swift` linker settings. It broke the iOS
  Simulator build once already.
* Remove the "Status: in progress" line from your package's README only when
  the definition of done is met.
