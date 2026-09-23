// Pigeon schema for the foundation_models plugin.
//
// Regenerate with:
//   dart run pigeon --input pigeons/foundation_models_api.dart
//   dart format lib/src/messages.g.dart
//
// Conventions:
// * Sessions and adapters are native objects referenced by `int` handles.
// * Generation schemas travel as JSON Schema text in the format of
//   `GenerationSchema`'s Codable representation (with `x-order`, `$defs`).
// * Generated content travels as JSON text (`GeneratedContent.jsonString`).
// * Transcripts travel both as structured entries (read-only view) and as the
//   Codable JSON of `Transcript` (for persistence and restoring sessions).
// * Streaming and tool calls use the FlutterApi (native -> Dart), routed by
//   request id and session handle.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'darwin/foundation_models/Sources/foundation_models/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'FoundationModelsPigeonError'),
    dartPackageName: 'foundation_models',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------
enum ModelKindMessage { system, privateCloudCompute }

enum UseCaseMessage { general, contentTagging }

enum GuardrailsMessage { defaults, permissiveContentTransformations }

enum AvailabilityStatusMessage {
  available,
  deviceNotEligible,
  appleIntelligenceNotEnabled,
  modelNotReady,
  systemNotReady,
  unknown,
}

enum CapabilityMessage { vision, guidedGeneration, reasoning, toolCalling }

enum SamplingKindMessage { greedy, topK, probabilityThreshold }

enum ToolCallingModeMessage { allowed, required, disallowed }

enum ReasoningLevelMessage { light, moderate, deep, custom }

enum TranscriptPolicyMessage { revertTranscript, preserveTranscript }

enum FeedbackSentimentMessage { positive, negative, neutral }

enum FeedbackIssueCategoryMessage {
  unhelpful,
  tooVerbose,
  didNotFollowInstructions,
  incorrect,
  stereotypeOrBias,
  suggestiveOrSexual,
  vulgarOrOffensive,
  triggeredGuardrailUnexpectedly,
}

enum TranscriptEntryKindMessage {
  instructions,
  prompt,
  toolCalls,
  toolOutput,
  response,
  reasoning,
}

enum SegmentKindMessage { text, structure, attachment }

enum BuiltInToolMessage { ocr, barcodeReader }

enum ImageInputKindMessage { file, encoded, pixels }

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------
class ModelConfigMessage {
  ModelConfigMessage({
    required this.kind,
    required this.useCase,
    required this.guardrails,
    this.adapterHandle,
  });

  ModelKindMessage kind;
  UseCaseMessage useCase;
  GuardrailsMessage guardrails;

  /// A loaded `SystemLanguageModel.Adapter` handle (system models only).
  int? adapterHandle;
}

class AvailabilityMessage {
  AvailabilityMessage({required this.status});

  AvailabilityStatusMessage status;
}

class ModelInfoMessage {
  ModelInfoMessage({
    required this.contextSize,
    this.variantName,
    required this.capabilities,
    required this.supportedLanguages,
  });

  int contextSize;

  /// `SystemLanguageModel.variant.displayName` (system models only).
  String? variantName;
  List<CapabilityMessage> capabilities;

  /// BCP 47 identifiers of `Locale.Language`s.
  List<String> supportedLanguages;
}

class QuotaUsageMessage {
  QuotaUsageMessage({
    required this.isLimitReached,
    required this.isApproachingLimit,
    this.resetDateMillis,
    required this.hasLimitIncreaseSuggestion,
  });

  bool isLimitReached;
  bool isApproachingLimit;
  int? resetDateMillis;
  bool hasLimitIncreaseSuggestion;
}

class AdapterInfoMessage {
  AdapterInfoMessage({
    required this.handle,
    required this.creatorDefinedMetadataJson,
  });

  int handle;
  String creatorDefinedMetadataJson;
}

// ---------------------------------------------------------------------------
// Prompts, options, tools
// ---------------------------------------------------------------------------
class ImageInputMessage {
  ImageInputMessage({
    required this.kind,
    this.path,
    this.bytes,
    this.width,
    this.height,
    this.bytesPerRow,
  });

  ImageInputKindMessage kind;

  /// For `file`.
  String? path;

  /// Encoded image bytes (`encoded`) or BGRA8 pixels (`pixels`).
  Uint8List? bytes;
  int? width;
  int? height;
  int? bytesPerRow;
}

class ImageAttachmentMessage {
  ImageAttachmentMessage({required this.image, this.label});

  ImageInputMessage image;
  String? label;
}

class PromptMessage {
  PromptMessage({required this.text, required this.images});

  String text;

  /// Attached after the text, in order.
  List<ImageAttachmentMessage> images;
}

class GenerationOptionsMessage {
  GenerationOptionsMessage({
    this.samplingKind,
    this.topK,
    this.probabilityThreshold,
    this.seed,
    this.temperature,
    this.maximumResponseTokens,
    this.toolCallingMode,
  });

  SamplingKindMessage? samplingKind;
  int? topK;
  double? probabilityThreshold;
  int? seed;
  double? temperature;
  int? maximumResponseTokens;
  ToolCallingModeMessage? toolCallingMode;
}

class ContextOptionsMessage {
  ContextOptionsMessage({
    this.includeSchemaInPrompt,
    this.reasoningLevel,
    this.customReasoningLevel,
  });

  bool? includeSchemaInPrompt;
  ReasoningLevelMessage? reasoningLevel;
  String? customReasoningLevel;
}

class ToolDefinitionMessage {
  ToolDefinitionMessage({
    required this.name,
    required this.toolDescription,
    required this.parametersJson,
    required this.includesSchemaInInstructions,
  });

  String name;
  String toolDescription;

  /// JSON Schema (GenerationSchema Codable format).
  String parametersJson;
  bool includesSchemaInInstructions;
}

class SessionConfigMessage {
  SessionConfigMessage({
    required this.model,
    this.instructions,
    required this.tools,
    required this.builtInTools,
    this.transcriptJson,
    this.transcriptPolicy,
  });

  ModelConfigMessage model;
  String? instructions;

  /// Tools implemented in Dart (called back through the FlutterApi).
  List<ToolDefinitionMessage> tools;
  List<BuiltInToolMessage> builtInTools;

  /// Restores a session from `Transcript` Codable JSON (instead of
  /// [instructions]).
  String? transcriptJson;
  TranscriptPolicyMessage? transcriptPolicy;
}

class RespondRequestMessage {
  RespondRequestMessage({
    required this.sessionHandle,
    required this.requestId,
    required this.prompt,
    required this.options,
    required this.contextOptions,
    this.schemaJson,
  });

  int sessionHandle;

  /// Chosen by Dart; identifies stream events and cancellation.
  int requestId;
  PromptMessage prompt;
  GenerationOptionsMessage options;
  ContextOptionsMessage contextOptions;

  /// When set, generate structured content matching this JSON Schema.
  String? schemaJson;
}

class TokenCountRequestMessage {
  TokenCountRequestMessage({
    this.prompt,
    this.instructions,
    required this.tools,
    this.schemaJson,
    this.transcriptJson,
  });

  PromptMessage? prompt;
  String? instructions;
  List<ToolDefinitionMessage> tools;
  String? schemaJson;
  String? transcriptJson;
}

class FeedbackIssueMessage {
  FeedbackIssueMessage({required this.category, this.explanation});

  FeedbackIssueCategoryMessage category;
  String? explanation;
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------
class UsageMessage {
  UsageMessage({
    required this.inputTokens,
    required this.cachedInputTokens,
    required this.outputTokens,
    required this.reasoningTokens,
  });

  int inputTokens;
  int cachedInputTokens;
  int outputTokens;
  int reasoningTokens;
}

class SegmentMessage {
  SegmentMessage({
    required this.id,
    required this.kind,
    this.text,
    this.contentJson,
    this.schemaName,
    this.attachmentLabel,
  });

  String id;
  SegmentKindMessage kind;
  String? text;
  String? contentJson;
  String? schemaName;
  String? attachmentLabel;
}

class ToolCallMessage {
  ToolCallMessage({
    required this.id,
    required this.toolName,
    required this.argumentsJson,
  });

  String id;
  String toolName;
  String argumentsJson;
}

class TranscriptEntryMessage {
  TranscriptEntryMessage({
    required this.id,
    required this.kind,
    required this.segments,
    required this.toolCalls,
    required this.toolDefinitions,
    this.toolName,
    this.responseFormatName,
  });

  String id;
  TranscriptEntryKindMessage kind;
  List<SegmentMessage> segments;
  List<ToolCallMessage> toolCalls;
  List<ToolDefinitionMessage> toolDefinitions;
  String? toolName;
  String? responseFormatName;
}

class TranscriptMessage {
  TranscriptMessage({required this.entries, required this.json});

  List<TranscriptEntryMessage> entries;
  String json;
}

class ResponseMessage {
  ResponseMessage({
    this.text,
    this.contentJson,
    required this.isComplete,
    required this.entries,
    required this.usage,
  });

  /// For text responses.
  String? text;

  /// For structured responses (`GeneratedContent.jsonString`).
  String? contentJson;
  bool isComplete;
  List<TranscriptEntryMessage> entries;
  UsageMessage usage;
}

class StreamSnapshotMessage {
  StreamSnapshotMessage({
    required this.requestId,
    this.text,
    this.contentJson,
    required this.isComplete,
    required this.usage,
  });

  int requestId;

  /// Cumulative content so far (not a delta).
  String? text;
  String? contentJson;
  bool isComplete;
  UsageMessage usage;
}

class ToolCallRequestMessage {
  ToolCallRequestMessage({
    required this.sessionHandle,
    required this.toolName,
    required this.argumentsJson,
  });

  int sessionHandle;
  String toolName;
  String argumentsJson;
}

class ToolResultMessage {
  ToolResultMessage({this.text, this.contentJson});

  /// Plain-text output.
  String? text;

  /// Structured output as JSON (used when [text] is null).
  String? contentJson;
}

class ErrorMessage {
  ErrorMessage({required this.code, required this.message, this.details});

  String code;
  String message;
  String? details;
}

// ---------------------------------------------------------------------------
// APIs
// ---------------------------------------------------------------------------

/// Always available.
@HostApi()
abstract class FoundationModelsPlatformApi {
  /// Whether the Foundation Models framework is available (iOS/macOS 26+).
  bool isSupported();

  /// Whether iOS/macOS 27 features are available (Private Cloud Compute,
  /// capabilities, reasoning).
  bool isVersion27Supported();
}

/// Registered only when Foundation Models is available.
@HostApi()
abstract class FoundationModelsHostApi {
  // -- Models -----------------------------------------------------------------
  @async
  AvailabilityMessage availability(ModelConfigMessage model);

  @async
  ModelInfoMessage modelInfo(ModelConfigMessage model);

  @async
  bool supportsLocale(ModelConfigMessage model, String? localeIdentifier);

  @async
  int tokenCount(ModelConfigMessage model, TokenCountRequestMessage request);

  @async
  QuotaUsageMessage privateCloudComputeQuota();

  void showQuotaLimitIncreaseSuggestion();

  // -- Adapters ---------------------------------------------------------------
  @async
  AdapterInfoMessage loadAdapter(String? path, String? name);

  @async
  void compileAdapter(int adapterHandle);

  List<String> compatibleAdapterIdentifiers(String name);

  @async
  void removeObsoleteAdapters();

  // -- Schemas ----------------------------------------------------------------
  /// Decodes and re-encodes a schema, returning Apple's canonical JSON.
  @async
  String validateSchema(String schemaJson);

  /// Decodes `Transcript` Codable JSON into structured entries.
  @async
  TranscriptMessage decodeTranscript(String json);

  // -- Sessions ---------------------------------------------------------------
  @async
  int createSession(SessionConfigMessage config);

  @async
  ResponseMessage respond(RespondRequestMessage request);

  /// Starts streaming; snapshots arrive through the callback API.
  @async
  void startStream(RespondRequestMessage request);

  /// Cancels an in-flight `respond` or stream with this request id.
  void cancelRequest(int requestId);

  void prewarm(int sessionHandle, PromptMessage? promptPrefix);

  @async
  TranscriptMessage transcript(int sessionHandle);

  bool isResponding(int sessionHandle);

  UsageMessage sessionUsage(int sessionHandle);

  void setTranscriptPolicy(int sessionHandle, TranscriptPolicyMessage? policy);

  @async
  Uint8List logFeedbackAttachment(
    int sessionHandle,
    FeedbackSentimentMessage? sentiment,
    List<FeedbackIssueMessage> issues,
    String? desiredResponseText,
  );

  // -- Handles ----------------------------------------------------------------
  @async
  void release(int handle);

  @async
  int releaseAll();

  int liveHandleCount();
}

/// Native -> Dart.
@FlutterApi()
abstract class FoundationModelsCallbackApi {
  /// Runs a Dart-implemented tool.
  @async
  ToolResultMessage callTool(ToolCallRequestMessage request);

  void onStreamSnapshot(StreamSnapshotMessage snapshot);

  void onStreamDone(int requestId, ResponseMessage response);

  void onStreamError(int requestId, ErrorMessage error);
}
