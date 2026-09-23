# foundation_models

Flutter bindings for Apple's **Foundation Models** framework: the Apple
Intelligence language models, built on
[Pigeon](https://pub.dev/packages/pigeon) platform channels.

Hold a conversation with the on-device model, stream tokens as they arrive,
get structured output that matches a schema you define, and let the model call
functions you write in Dart.

```dart
import 'package:foundation_models/foundation_models.dart';

if ((await SystemLanguageModel.defaultModel.availability()).isAvailable) {
  final session = await LanguageModelSession.create(
    instructions: 'Answer in one short sentence.',
  );
  final response = await session.respond('Why is the sky blue?');
  print(response.content);
  await session.dispose();
}
```

## Requirements

| | |
|---|---|
| On-device model | iOS 26+ / macOS 26+ with Apple Intelligence enabled |
| Private Cloud Compute, usage, image prompts, reasoning, built-in tools | iOS 27+ / macOS 27+ |
| Token counting | iOS 26.4+ / macOS 26.4+ |
| Builds for | iOS 15+ and macOS 12+ |
| Toolchain | Xcode 27, Flutter 3.38+ |

Apps still build and launch on older systems: `FoundationModels.isSupported()`
returns false there, and calls throw `FoundationModelsErrorCode.unsupported`.
Always check [availability] before showing AI features, because the user may
have Apple Intelligence turned off or the model may still be downloading.

**Tested:** the full integration suite (18 tests) passes against the real
models on macOS 27 and on an iPhone running iOS 27.0, with Apple Intelligence
enabled.

## The two models

| | `SystemLanguageModel` | `PrivateCloudComputeLanguageModel` |
|---|---|---|
| Runs | On the device | On Apple's servers |
| Data | Never leaves the device | Leaves the device (Apple states it is not stored) |
| Size | ~3B parameters, 4096-token context | Larger, bigger context |
| Reasoning | No | Yes |
| Quota | None | Yes, see `quotaUsage()` |
| Needs | iOS 26 / macOS 26 | iOS 27 / macOS 27 |

Pass either to `LanguageModelSession.create(model: ...)`.

## Sessions

A session holds the transcript and feeds it back on each turn, so the model
remembers the conversation. One request at a time: a second concurrent request
throws `concurrent_requests`.

```dart
final session = await LanguageModelSession.create(
  model: SystemLanguageModel.defaultModel,
  instructions: 'You are a terse assistant.',
);
await session.prewarm();                       // optional, reduces latency
final answer = await session.respond('Hello'); // or streamResponse
final saved = (await session.transcript).json; // persist and resume later
await session.dispose();
```

`instructions` outrank prompts, so never build them from untrusted input.

## Streaming

Snapshots are **cumulative**: each one carries everything generated so far.
Use `content` to replace your UI text, or `delta` for just the new part.
Cancelling the subscription cancels generation.

```dart
await for (final snapshot in session.streamResponse('Tell me a story')) {
  setState(() => text = snapshot.content);
}
```

## Guided generation

Build a schema and the model's output is constrained to it, then parsed as
JSON.

```dart
final schema = GenerationSchema(
  DynamicGenerationSchema.object(
    name: 'Movie',
    properties: [
      SchemaProperty('title', DynamicGenerationSchema.string()),
      SchemaProperty(
        'year',
        DynamicGenerationSchema.integer(minimum: 1980, maximum: 2000),
      ),
      SchemaProperty(
        'mood',
        DynamicGenerationSchema.string(anyOf: ['happy', 'sad', 'tense']),
      ),
    ],
  ),
);
final response = await session.respondWithSchema('A 90s film?', schema);
print(response.content['title']);
```

`DynamicGenerationSchema` covers objects, arrays with length limits, string
enums and patterns, bounded numbers, `anyOf`, null and `reference` for
recursive types. `GenerationSchema.fromJsonSchema` accepts a hand-written JSON
Schema and fills in the keys Apple's decoder needs.
`FoundationModels.validateSchema` checks one against the framework.

## Tools

The model can call functions you write. It decides when, with arguments
matching your schema, and continues once you return a result.

```dart
final weather = FunctionTool(
  name: 'get_weather',
  description: 'Gets the current weather for a city.',
  parameters: GenerationSchema(
    DynamicGenerationSchema.object(
      name: 'WeatherArguments',
      properties: [SchemaProperty('city', DynamicGenerationSchema.string())],
    ),
  ),
  handler: (arguments) async =>
      ToolOutput.text(await forecast(arguments['city']! as String)),
);
final session = await LanguageModelSession.create(tools: [weather]);
```

A tool runs while the response is in flight, so its handler must not start
another request on the same session. If it throws, the request fails with
`tool_call_failed`. `BuiltInTool.ocr` and `BuiltInTool.barcodeReader` are
Apple's own Vision-backed tools (iOS 27+), which read images attached to the
prompt.

## Images

With a vision-capable model on iOS 27+, attach images to a prompt:

```dart
await session.respond(
  Prompt('What is in this photo?', images: [
    ImageAttachment(ImageInput.file(path), label: 'photo'),
  ]),
);
```

## Swift → Dart

| Foundation Models (Swift) | foundation_models (Dart) |
|---|---|
| `SystemLanguageModel`, `.availability`, `.supportedLanguages`, `.contextSize`, `.variant`, `.capabilities` | `SystemLanguageModel`, `availability()`, `info()` |
| `SystemLanguageModel(useCase:guardrails:)` | `SystemLanguageModel(useCase:, guardrails:)` |
| `PrivateCloudComputeLanguageModel`, `quotaUsage` | `PrivateCloudComputeLanguageModel`, `quotaUsage()` |
| `SystemLanguageModel.Adapter` | `ModelAdapter` |
| `tokenCount(for:)` | `SystemLanguageModel.tokenCount(...)` |
| `LanguageModelSession(model:tools:instructions:)` | `LanguageModelSession.create(...)` |
| `respond(to:)`, `respond(to:schema:)` | `respond`, `respondWithSchema` |
| `streamResponse(to:)` | `streamResponse`, `streamResponseWithSchema` |
| `prewarm`, `isResponding`, `transcript`, `usage` | same names |
| `GenerationOptions`, `SamplingMode`, `ToolCallingMode` | `GenerationOptions`, `SamplingMode`, `ToolCallingMode` |
| `ContextOptions`, `ReasoningLevel` | `ContextOptions`, `ReasoningLevel` |
| `DynamicGenerationSchema`, `GenerationSchema` | `DynamicGenerationSchema`, `GenerationSchema` |
| `GeneratedContent` | `GeneratedContent` |
| `Tool`, `Transcript.ToolCall` | `Tool`, `FunctionTool`, `TranscriptToolCall` |
| `Transcript` and its entries | `Transcript`, `InstructionsEntry`, `PromptEntry`, `ToolCallsEntry`, `ToolOutputEntry`, `ResponseEntry`, `ReasoningEntry` |
| `logFeedbackAttachment` | `LanguageModelSession.logFeedback` |
| `TranscriptErrorHandlingPolicy` | `TranscriptErrorHandlingPolicy` |

## Not bridged

* `@Generable` and `@Guide` macros: they are compile-time Swift macros. Use
  `DynamicGenerationSchema`, which is what they produce at runtime.
* `DynamicProfile`, `DynamicInstructions`, `SessionProperty`: Swift
  result-builder DSLs with no Dart counterpart. Their effects are available
  through `instructions`, `GenerationOptions` and `ContextOptions`.
* `LanguageModelExecutor`: plugging a custom model into a session requires
  implementing a Swift protocol.
* `Attachment(_ cgImage:)` variants beyond file, encoded bytes and raw
  pixels.

## Known platform behavior

* A second request on a session that is still responding **traps inside
  Foundation Models on an iOS device** rather than throwing. This package
  therefore rejects it in Dart, and again in Swift, with
  `concurrentRequests`. Await the previous response, cancel its stream, or
  use a second session.
* `maximumResponseTokens` is approximate: the model may overshoot slightly.

## Errors

Every failure is a `FoundationModelsException` with a
`FoundationModelsErrorCode`: `unsupported`, `modelUnavailable`,
`assetsUnavailable`, `contextWindowExceeded` (with `contextSize` and
`tokenCount`), `guardrailViolation`, `refusal`, `unsupportedGuide`,
`unsupportedLanguage`, `decodingFailure`, `rateLimited` (with `resetDate`),
`quotaLimitReached`, `networkFailure`, `serviceUnavailable`, `timeout`,
`concurrentRequests`, `toolCallFailed` (with `toolName`), `schemaError`,
`adapterError`, `cancelled` and `invalidHandle`.

## Resources

Sessions and adapters own native objects: call `dispose()`. A `Finalizer`
releases forgotten ones eventually. After a hot restart call
`FoundationModels.releaseAll()`; `FoundationModels.liveHandleCount()` helps
check for leaks.

## Development

```sh
dart run pigeon --input pigeons/foundation_models_api.dart
flutter test                                              # Dart unit tests
cd example
flutter test integration_test/foundation_models_test.dart -d macos
flutter test integration_test/app_test.dart -d macos

# On a physical device (wireless debugging needs flutter drive):
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/foundation_models_test.dart -d <device id> \
  --publish-port
```

Run integration test files one at a time on macOS. For tests of your own app,
`package:foundation_models/testing.dart` lets you swap in fake host APIs with
`FoundationModelsBindings.instance`.
