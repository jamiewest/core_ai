import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'native_resource.dart';
import 'prompt.dart';
import 'schema.dart';
import 'tools.dart';
import 'transcript.dart';

/// What the on-device model is tuned for (Apple's
/// `SystemLanguageModel.UseCase`).
enum ModelUseCase {
  /// General text generation.
  general,

  /// Tagging content with topics, actions and emotions.
  contentTagging;

  UseCaseMessage _toMessage() => UseCaseMessage.values[index];
}

/// Safety guardrails applied to prompts and responses (Apple's
/// `SystemLanguageModel.Guardrails`).
enum Guardrails {
  /// Apple's default guardrails.
  defaults,

  /// Looser guardrails for transforming content the user already has, such
  /// as summarizing or rewriting their own text.
  permissiveContentTransformations;

  GuardrailsMessage _toMessage() => GuardrailsMessage.values[index];
}

/// Why a model is unavailable.
enum ModelUnavailableReason {
  /// The device does not support Apple Intelligence.
  deviceNotEligible,

  /// The user has not turned Apple Intelligence on.
  appleIntelligenceNotEnabled,

  /// The model's assets are still downloading.
  modelNotReady,

  /// The system is not ready for Private Cloud Compute requests.
  systemNotReady,

  /// The OS is too old, or the framework is missing.
  frameworkUnavailable,

  /// The reason is not known to this version of the plugin.
  unknown,
}

/// Whether a model can be used right now (Apple's `Availability`).
@immutable
final class ModelAvailability {
  /// Creates an availability result.
  const ModelAvailability({required this.isAvailable, this.reason});

  /// Whether the model is ready.
  final bool isAvailable;

  /// Why it is not, when [isAvailable] is false.
  final ModelUnavailableReason? reason;

  @override
  String toString() =>
      isAvailable ? 'available' : 'unavailable(${reason?.name})';
}

/// What a model can do (Apple's `LanguageModelCapabilities`).
enum ModelCapability {
  /// Accepts images in prompts.
  vision,

  /// Supports schema-guided generation.
  guidedGeneration,

  /// Supports reasoning levels.
  reasoning,

  /// Supports tool calling.
  toolCalling,
}

/// Facts about a model (context size, capabilities, languages).
@immutable
final class LanguageModelInfo {
  /// Creates an info object.
  const LanguageModelInfo({
    required this.contextSize,
    required this.variantName,
    required this.capabilities,
    required this.supportedLanguages,
  });

  /// Converts from the Pigeon representation.
  factory LanguageModelInfo.fromMessage(ModelInfoMessage message) =>
      LanguageModelInfo(
        contextSize: message.contextSize,
        variantName: message.variantName,
        capabilities: {
          for (final capability in message.capabilities)
            ModelCapability.values[capability.index],
        },
        supportedLanguages: List.unmodifiable(message.supportedLanguages),
      );

  /// How many tokens fit in the model's context window.
  final int contextSize;

  /// The model variant's display name, such as "AFM 3 Core".
  final String? variantName;

  /// What the model supports. Empty before iOS 27 / macOS 27.
  final Set<ModelCapability> capabilities;

  /// BCP 47 language identifiers the model supports.
  final List<String> supportedLanguages;

  @override
  String toString() =>
      'LanguageModelInfo(${variantName ?? 'model'}, context: $contextSize, '
      'capabilities: ${capabilities.map((c) => c.name).toList()})';
}

/// A language model that sessions can run on.
@immutable
sealed class LanguageModel {
  const LanguageModel();

  /// The Pigeon representation.
  ModelConfigMessage toMessage();

  /// Whether the model can be used right now, and why not if it cannot.
  Future<ModelAvailability> availability() async {
    if (!await FoundationModels.isSupported()) {
      return const ModelAvailability(
        isAvailable: false,
        reason: ModelUnavailableReason.frameworkUnavailable,
      );
    }
    final host = FoundationModelsBindings.instance.host;
    final message = await guardPlatformCall(
      () => host.availability(toMessage()),
    );
    return switch (message.status) {
      AvailabilityStatusMessage.available => const ModelAvailability(
        isAvailable: true,
      ),
      AvailabilityStatusMessage.deviceNotEligible => const ModelAvailability(
        isAvailable: false,
        reason: ModelUnavailableReason.deviceNotEligible,
      ),
      AvailabilityStatusMessage.appleIntelligenceNotEnabled =>
        const ModelAvailability(
          isAvailable: false,
          reason: ModelUnavailableReason.appleIntelligenceNotEnabled,
        ),
      AvailabilityStatusMessage.modelNotReady => const ModelAvailability(
        isAvailable: false,
        reason: ModelUnavailableReason.modelNotReady,
      ),
      AvailabilityStatusMessage.systemNotReady => const ModelAvailability(
        isAvailable: false,
        reason: ModelUnavailableReason.systemNotReady,
      ),
      AvailabilityStatusMessage.unknown => const ModelAvailability(
        isAvailable: false,
        reason: ModelUnavailableReason.unknown,
      ),
    };
  }

  /// Whether the model is ready to use.
  Future<bool> get isAvailable async => (await availability()).isAvailable;

  /// The model's context size, capabilities and languages.
  Future<LanguageModelInfo> info() async {
    final host = FoundationModelsBindings.instance.host;
    final message = await guardPlatformCall(() => host.modelInfo(toMessage()));
    return LanguageModelInfo.fromMessage(message);
  }

  /// Whether the model supports [localeIdentifier] (the current locale when
  /// omitted).
  Future<bool> supportsLocale([String? localeIdentifier]) {
    final host = FoundationModelsBindings.instance.host;
    return guardPlatformCall(
      () => host.supportsLocale(toMessage(), localeIdentifier),
    );
  }
}

/// Apple's on-device model (Apple's `SystemLanguageModel`).
///
/// It runs entirely on device: no data leaves the phone or Mac.
@immutable
final class SystemLanguageModel extends LanguageModel {
  /// A model for [useCase], with [guardrails].
  const SystemLanguageModel({
    this.useCase = ModelUseCase.general,
    this.guardrails = Guardrails.defaults,
  }) : adapter = null;

  /// A model specialized by a trained [adapter].
  const SystemLanguageModel.withAdapter(
    ModelAdapter this.adapter, {
    this.guardrails = Guardrails.defaults,
  }) : useCase = ModelUseCase.general;

  /// The default general-purpose on-device model.
  static const SystemLanguageModel defaultModel = SystemLanguageModel();

  /// What the model is tuned for.
  final ModelUseCase useCase;

  /// The guardrails applied.
  final Guardrails guardrails;

  /// The adapter, when created with [SystemLanguageModel.withAdapter].
  final ModelAdapter? adapter;

  @override
  ModelConfigMessage toMessage() => ModelConfigMessage(
    kind: ModelKindMessage.system,
    useCase: useCase._toMessage(),
    guardrails: guardrails._toMessage(),
    adapterHandle: adapter?.handle,
  );

  /// Counts the tokens the given pieces would use.
  ///
  /// Needs iOS 26.4 / macOS 26.4. Pass any combination; the counts add up.
  Future<int> tokenCount({
    Prompt? prompt,
    String? instructions,
    List<Tool> tools = const [],
    GenerationSchema? schema,
    Transcript? transcript,
  }) {
    final host = FoundationModelsBindings.instance.host;
    return guardPlatformCall(
      () => host.tokenCount(
        toMessage(),
        TokenCountRequestMessage(
          prompt: prompt?.toMessage(),
          instructions: instructions,
          tools: [for (final tool in tools) tool.toMessage()],
          schemaJson: schema?.toJsonString(),
          transcriptJson: transcript?.json,
        ),
      ),
    );
  }

  @override
  String toString() => 'SystemLanguageModel(${useCase.name})';
}

/// Apple's Private Cloud Compute model (Apple's
/// `PrivateCloudComputeLanguageModel`), available from iOS 27 / macOS 27.
///
/// This model runs on Apple's servers, not on the device: prompts and
/// attachments leave the device (Apple states the data is not stored and not
/// accessible to Apple). It is larger than the on-device model, supports
/// reasoning, and is subject to a quota, see [quotaUsage].
@immutable
final class PrivateCloudComputeLanguageModel extends LanguageModel {
  /// The Private Cloud Compute model.
  const PrivateCloudComputeLanguageModel();

  @override
  ModelConfigMessage toMessage() => ModelConfigMessage(
    kind: ModelKindMessage.privateCloudCompute,
    useCase: UseCaseMessage.general,
    guardrails: GuardrailsMessage.defaults,
  );

  /// How much of the app's quota is used.
  Future<QuotaUsage> quotaUsage() async {
    final host = FoundationModelsBindings.instance.host;
    final message = await guardPlatformCall(host.privateCloudComputeQuota);
    return QuotaUsage(
      isLimitReached: message.isLimitReached,
      isApproachingLimit: message.isApproachingLimit,
      resetDate: switch (message.resetDateMillis) {
        final int millis => DateTime.fromMillisecondsSinceEpoch(millis),
        _ => null,
      },
      hasLimitIncreaseSuggestion: message.hasLimitIncreaseSuggestion,
    );
  }

  /// Shows the system's suggestion for increasing the quota, when
  /// [QuotaUsage.hasLimitIncreaseSuggestion] is true.
  Future<void> showLimitIncreaseSuggestion() {
    final host = FoundationModelsBindings.instance.host;
    return guardPlatformCall(host.showQuotaLimitIncreaseSuggestion);
  }

  @override
  String toString() => 'PrivateCloudComputeLanguageModel()';
}

/// Private Cloud Compute quota (Apple's `QuotaUsage`).
@immutable
final class QuotaUsage {
  /// Creates a quota record.
  const QuotaUsage({
    required this.isLimitReached,
    required this.isApproachingLimit,
    required this.resetDate,
    required this.hasLimitIncreaseSuggestion,
  });

  /// Whether the app is out of quota.
  final bool isLimitReached;

  /// Whether the app is close to the limit.
  final bool isApproachingLimit;

  /// When the quota resets, if known.
  final DateTime? resetDate;

  /// Whether the system can offer the user a way to raise the limit.
  final bool hasLimitIncreaseSuggestion;

  @override
  String toString() =>
      'QuotaUsage(limitReached: $isLimitReached, resets: $resetDate)';
}

/// A trained adapter for the on-device model (Apple's
/// `SystemLanguageModel.Adapter`).
final class ModelAdapter extends NativeResource {
  ModelAdapter._(super.handle, this.creatorDefinedMetadata);

  /// Loads an adapter from a `.fmadapter` file.
  static Future<ModelAdapter> fromFile(String path) =>
      _load(path: path, name: null);

  /// Loads an adapter installed as a Background Assets pack.
  static Future<ModelAdapter> named(String name) =>
      _load(path: null, name: name);

  static Future<ModelAdapter> _load({
    required String? path,
    required String? name,
  }) async {
    final host = FoundationModelsBindings.instance.host;
    final info = await guardPlatformCall(() => host.loadAdapter(path, name));
    Map<String, Object?> metadata;
    try {
      metadata = (jsonDecode(info.creatorDefinedMetadataJson) as Map)
          .cast<String, Object?>();
    } on FormatException {
      metadata = const {};
    }
    return ModelAdapter._(info.handle, Map.unmodifiable(metadata));
  }

  /// Identifiers of adapters compatible with the current model version.
  static Future<List<String>> compatibleIdentifiers(String name) {
    final host = FoundationModelsBindings.instance.host;
    return guardPlatformCall(() => host.compatibleAdapterIdentifiers(name));
  }

  /// Deletes adapters that no longer match the installed model.
  static Future<void> removeObsolete() {
    final host = FoundationModelsBindings.instance.host;
    return guardPlatformCall(host.removeObsoleteAdapters);
  }

  /// Metadata the adapter's creator stored in it.
  final Map<String, Object?> creatorDefinedMetadata;

  /// Compiles the adapter ahead of first use.
  Future<void> compile() =>
      guardPlatformCall(() => bindings.host.compileAdapter(handle));

  @override
  String toString() => 'ModelAdapter(${isDisposed ? 'disposed' : handle})';
}

/// Framework-level queries and housekeeping.
abstract final class FoundationModels {
  /// Whether the Foundation Models framework is available (iOS 26+ /
  /// macOS 26+). This does not mean a model is ready; see
  /// [LanguageModel.availability].
  static Future<bool> isSupported() async {
    try {
      return await FoundationModelsBindings.instance.platform.isSupported();
    } on Object {
      return false;
    }
  }

  /// Whether iOS 27 / macOS 27 features are available: Private Cloud
  /// Compute, capabilities, reasoning levels, token usage and image prompts.
  static Future<bool> isVersion27Supported() async {
    try {
      return await FoundationModelsBindings.instance.platform
          .isVersion27Supported();
    } on Object {
      return false;
    }
  }

  /// Checks a schema against the framework and returns Apple's canonical
  /// JSON for it. Useful in tests.
  static Future<String> validateSchema(GenerationSchema schema) {
    final host = FoundationModelsBindings.instance.host;
    return guardPlatformCall(() => host.validateSchema(schema.toJsonString()));
  }

  /// Parses persisted transcript [json] into entries.
  static Future<Transcript> decodeTranscript(String json) async {
    final host = FoundationModelsBindings.instance.host;
    final message = await guardPlatformCall(() => host.decodeTranscript(json));
    return Transcript.fromMessage(message);
  }

  /// Releases every native object this engine created.
  ///
  /// Useful after a hot restart, which drops Dart objects without disposing
  /// them. Returns how many were released.
  static Future<int> releaseAll() {
    final host = FoundationModelsBindings.instance.host;
    return guardPlatformCall(host.releaseAll);
  }

  /// How many native objects are alive, for leak checks.
  static Future<int> liveHandleCount() {
    final host = FoundationModelsBindings.instance.host;
    return guardPlatformCall(host.liveHandleCount);
  }
}
