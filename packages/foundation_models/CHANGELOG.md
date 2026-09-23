## 0.1.0

* Initial release: Foundation Models bindings for iOS 26+ / macOS 26+ over
  Pigeon platform channels.
* `SystemLanguageModel` (use cases, guardrails, adapters) and
  `PrivateCloudComputeLanguageModel` (availability, quota), with availability
  reasons, capabilities, context size, variants and supported languages.
* `LanguageModelSession`: text and structured responses, streaming with
  cumulative snapshots and cancellation, prewarming, transcripts that can be
  persisted and resumed, usage, and feedback attachments.
* Guided generation with a `DynamicGenerationSchema` builder,
  `GenerationSchema.fromJsonSchema` and schema validation.
* Tools implemented in Dart, plus Apple's built-in OCR and barcode tools.
* Image attachments in prompts on iOS 27 / macOS 27.
* Typed errors with structured details.
