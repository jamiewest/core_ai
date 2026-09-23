# Apple AI plugins for Flutter

A monorepo of Flutter plugins that bring Apple's on-device AI frameworks to
Dart on iOS and macOS, through [Pigeon](https://pub.dev/packages/pigeon)
platform channels.

> The repository directory is named `core_ai` for historical reasons; the
> workspace package is `apple_ai_workspace` and each plugin lives under
> `packages/`.

## Packages

| Package | Apple framework | What it does | Status |
|---|---|---|---|
| [`core_ai`](packages/core_ai) | Core AI | Run your own `.aimodel` models: tensors, images, stateful models, compute-stream pipelines, the specialization cache | **Done**, tested on macOS 27 and iOS 27 hardware |
| [`foundation_models`](packages/foundation_models) | Foundation Models | Apple Intelligence language models: chat, streaming, guided generation, tools, Private Cloud Compute | **Done**, tested on macOS 27 and iOS 27 hardware |
| [`apple_vision`](packages/apple_vision) | Vision | Image analysis: text, barcodes, faces, poses, classification, saliency, segmentation | **Done**, tested on macOS 27; iOS device build verified |
| [`core_ml`](packages/core_ml) | Core ML | Run `.mlmodel` / `.mlpackage` models | **Done**, tested on macOS 27; iOS device build verified |
| [`apple_speech`](packages/apple_speech) | Speech | On-device speech to text, for files and live audio | In progress: native implementation and partial Dart API |
| [`apple_sound_analysis`](packages/apple_sound_analysis) | SoundAnalysis | Sound classification | In progress: Pigeon API and partial native implementation |
| [`apple_natural_language`](packages/apple_natural_language) | NaturalLanguage | Language ID, tagging, tokenization, embeddings | Done on macOS 27; iOS named-entity test updated, device rerun pending |
| [`apple_translation`](packages/apple_translation) | Translation | On-device translation | **Done**, tested on macOS 27; iOS device build verified |
| [`image_playground`](packages/image_playground) | ImagePlayground | On-device image generation | Not started |
| [`media_intelligence`](packages/media_intelligence) | MediaIntelligence | Face grouping, video highlights and key frames | Not started |

Packages marked "in progress" have partial or unverified implementations;
"not started" packages are scaffolds. See [the handoff](docs/HANDOFF.md) and
[Codex's continuation notes](docs/CODEX_HANDOFF.md) for remaining work and
verification results.

## Which one do I want?

* **Run a model you trained or downloaded**: `core_ai` for `.aimodel`
  (Apple's current runtime), `core_ml` for `.mlmodel` / `.mlpackage` (the
  older format, which most published models still use).
* **Use Apple's built-in LLM**: `foundation_models`. No model to ship, but it
  needs Apple Intelligence.
* **Understand an image, sound or text**: the task-specific frameworks
  (`apple_vision`, `apple_speech`, `apple_natural_language`, ...), which are
  smaller, faster and available more widely than the LLM.

## Requirements

Xcode 27 and Flutter 3.38+. Individual packages state their own minimum OS;
all of them build for iOS 15+ / macOS 12+ and report `isSupported() == false`
on systems that are too old, so an app can ship one binary. Core AI is
**not** in the iOS Simulator SDK, so test on macOS 27 or an iOS 27 device.

## Repository layout

```
pubspec.yaml            # Dart pub workspace
docs/CONVENTIONS.md     # the contract every package follows
packages/<name>/        # one plugin per Apple framework
  pigeons/              # Pigeon schema (the Dart <-> Swift contract)
  darwin/               # shared iOS + macOS Swift sources
  lib/                  # public Dart API
  test/                 # unit tests against fakes
  example/              # demo app and integration tests
```

## Working in this repo

```sh
flutter pub get                      # resolves the whole workspace
flutter analyze packages             # every package
cd packages/<name> && flutter test   # unit tests
cd packages/<name>/example && flutter test integration_test/<file>.dart -d macos
```

Run integration test files one at a time on macOS: passing several to a single
`flutter test` makes the desktop app relaunch between files and fail.

New packages follow [docs/CONVENTIONS.md](docs/CONVENTIONS.md), with
`packages/core_ai` and `packages/foundation_models` as reference
implementations.

## Licensing

Each package has a `LICENSE` placeholder. Choose a license before publishing.
