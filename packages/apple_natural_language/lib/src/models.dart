import 'package:flutter/foundation.dart';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'native_resource.dart';
import 'text.dart';

/// How embedding distance is measured (Apple's `NLDistanceType`).
enum DistanceType {
  /// Cosine distance: 0 for identical directions, up to 2 for opposite.
  cosine;

  /// The Pigeon representation.
  DistanceTypeMessage toMessage() => DistanceTypeMessage.values[index];
}

/// A nearby entry in an embedding.
@immutable
final class Neighbor {
  /// Creates a neighbor.
  const Neighbor(this.text, this.distance);

  /// The neighbor's text.
  final String text;

  /// How far it is.
  final double distance;

  @override
  String toString() => '$text (${distance.toStringAsFixed(3)})';
}

/// A static word or sentence embedding (Apple's `NLEmbedding`): maps text
/// to vectors whose distances reflect meaning.
final class Embedding extends NativeResource {
  Embedding._(EmbeddingInfoMessage info)
    : dimension = info.dimension,
      vocabularySize = info.vocabularySize,
      language = info.language,
      revision = info.revision,
      super(info.handle);

  /// Apple's word embedding for [language].
  ///
  /// Throws [NaturalLanguageErrorCode.assetsUnavailable] when this device has
  /// none for the language.
  static Future<Embedding> wordEmbedding(String language, {int? revision}) =>
      _load((host) => host.loadWordEmbedding(language, revision));

  /// Apple's sentence embedding for [language].
  static Future<Embedding> sentenceEmbedding(
    String language, {
    int? revision,
  }) => _load((host) => host.loadSentenceEmbedding(language, revision));

  /// A custom embedding built with Create ML.
  static Future<Embedding> fromFile(String path) =>
      _load((host) => host.loadEmbeddingFromFile(path));

  static Future<Embedding> _load(
    Future<EmbeddingInfoMessage> Function(AppleNaturalLanguageHostApi host)
    load,
  ) async {
    final host = NaturalLanguageBindings.instance.host;
    return Embedding._(await guardPlatformCall(() => load(host)));
  }

  /// The length of each vector.
  final int dimension;

  /// How many entries the embedding has.
  final int vocabularySize;

  /// The embedding's language.
  final String? language;

  /// The embedding's revision.
  final int revision;

  /// The vector for [text], or null if the embedding does not know it.
  Future<Float64List?> vector(String text) =>
      guardPlatformCall(() => bindings.host.embeddingVector(handle, text));

  /// Whether the embedding has an entry for [text].
  Future<bool> contains(String text) =>
      guardPlatformCall(() => bindings.host.embeddingContains(handle, text));

  /// The distance between [first] and [second].
  Future<double> distance(
    String first,
    String second, {
    DistanceType type = DistanceType.cosine,
  }) => guardPlatformCall(
    () => bindings.host.embeddingDistance(
      handle,
      first,
      second,
      type.toMessage(),
    ),
  );

  /// The nearest entries to [text], closest first, excluding [text] itself.
  Future<List<Neighbor>> neighbors(
    String text, {
    int maximumCount = 10,
    double? maximumDistance,
    DistanceType type = DistanceType.cosine,
  }) async => _neighbors(
    await guardPlatformCall(
      () => bindings.host.embeddingNeighbors(
        handle,
        text,
        maximumCount,
        maximumDistance,
        type.toMessage(),
      ),
    ),
  );

  /// The nearest entries to [vector], closest first.
  ///
  /// Like [neighbors], this excludes an entry whose vector is exactly
  /// [vector].
  Future<List<Neighbor>> neighborsOfVector(
    Float64List vector, {
    int maximumCount = 10,
    double? maximumDistance,
    DistanceType type = DistanceType.cosine,
  }) async => _neighbors(
    await guardPlatformCall(
      () => bindings.host.embeddingNeighborsForVector(
        handle,
        vector,
        maximumCount,
        maximumDistance,
        type.toMessage(),
      ),
    ),
  );

  static List<Neighbor> _neighbors(List<NeighborMessage> list) => [
    for (final item in list) Neighbor(item.text, item.distance),
  ];

  @override
  String toString() => 'Embedding($language, dimension: $dimension)';
}

/// A token's vector from a [ContextualEmbedding].
@immutable
final class TokenVector {
  /// Creates a token vector.
  const TokenVector(this.range, this.text, this.vector);

  /// Where the token is.
  final TextRange range;

  /// The token's text.
  final String text;

  /// The token's embedding.
  final Float64List vector;
}

/// The per-token vectors for a text.
@immutable
final class ContextualEmbeddingResult {
  /// Creates a result.
  const ContextualEmbeddingResult({
    required this.language,
    required this.sequenceLength,
    required this.tokens,
  });

  /// The language the text was embedded as.
  final String language;

  /// How many model tokens the text used.
  final int sequenceLength;

  /// One vector per token.
  final List<TokenVector> tokens;

  /// The mean of the token vectors: a simple embedding of the whole text.
  Float64List meanVector() {
    if (tokens.isEmpty) return Float64List(0);
    final result = Float64List(tokens.first.vector.length);
    for (final token in tokens) {
      for (var i = 0; i < result.length; i++) {
        result[i] += token.vector[i];
      }
    }
    for (var i = 0; i < result.length; i++) {
      result[i] /= tokens.length;
    }
    return result;
  }
}

/// A transformer that embeds each token in context (Apple's
/// `NLContextualEmbedding`, iOS 17+ / macOS 14+).
///
/// Its assets may need downloading first; see [hasAvailableAssets] and
/// [requestAssets].
final class ContextualEmbedding extends NativeResource {
  ContextualEmbedding._(ContextualEmbeddingInfoMessage info)
    : modelIdentifier = info.modelIdentifier,
      languages = List.unmodifiable(info.languages),
      scripts = List.unmodifiable(info.scripts),
      revision = info.revision,
      dimension = info.dimension,
      maximumSequenceLength = info.maximumSequenceLength,
      hasAvailableAssets = info.hasAvailableAssets,
      super(info.handle);

  /// The embedding for [language].
  static Future<ContextualEmbedding> forLanguage(String language) =>
      _load(language: language);

  /// The embedding for [script], such as `Latn`.
  static Future<ContextualEmbedding> forScript(String script) =>
      _load(script: script);

  /// The embedding with [identifier].
  static Future<ContextualEmbedding> withModelIdentifier(String identifier) =>
      _load(modelIdentifier: identifier);

  static Future<ContextualEmbedding> _load({
    String? modelIdentifier,
    String? language,
    String? script,
  }) async {
    final host = NaturalLanguageBindings.instance.host;
    final info = await guardPlatformCall(
      () => host.loadContextualEmbedding(modelIdentifier, language, script),
    );
    return ContextualEmbedding._(info);
  }

  /// The model's identifier.
  final String modelIdentifier;

  /// The languages it supports.
  final List<String> languages;

  /// The scripts it supports.
  final List<String> scripts;

  /// The model's revision.
  final int revision;

  /// The length of each token vector.
  final int dimension;

  /// The most tokens it embeds at once.
  final int maximumSequenceLength;

  /// Whether its assets were on the device when it was loaded.
  final bool hasAvailableAssets;

  /// Downloads the model's assets, if needed.
  Future<AssetsResult> requestAssets() async => AssetsResult.fromMessage(
    await guardPlatformCall(
      () => bindings.host.requestContextualEmbeddingAssets(handle),
    ),
  );

  /// Embeds each token of [text].
  Future<ContextualEmbeddingResult> embed(
    String text, {
    String? language,
  }) async {
    final result = await guardPlatformCall(
      () => bindings.host.contextualEmbeddingResult(handle, text, language),
    );
    return ContextualEmbeddingResult(
      language: result.language,
      sequenceLength: result.sequenceLength,
      tokens: [
        for (final token in result.tokens)
          TokenVector(
            TextRange(token.start, token.length),
            text.substring(token.start, token.start + token.length),
            token.vector,
          ),
      ],
    );
  }

  @override
  String toString() => 'ContextualEmbedding($modelIdentifier)';
}

/// The kind of a [TextModel] (Apple's `NLModel.ModelType`).
enum TextModelType {
  /// Labels a whole text.
  classifier,

  /// Labels each token.
  sequence,
}

/// A custom text classifier or word tagger trained with Create ML (Apple's
/// `NLModel`).
final class TextModel extends NativeResource {
  TextModel._(ModelInfoMessage info)
    : type = TextModelType.values[info.type.index],
      language = info.language,
      revision = info.revision,
      super(info.handle);

  /// Loads a compiled model (`.mlmodelc`).
  static Future<TextModel> load(String path) async {
    final host = NaturalLanguageBindings.instance.host;
    return TextModel._(await guardPlatformCall(() => host.loadModel(path)));
  }

  /// Whether the model labels texts or tokens.
  final TextModelType type;

  /// The model's language.
  final String? language;

  /// The model's revision.
  final int revision;

  /// The label for [text], for classifiers.
  Future<String?> predictedLabel(String text) =>
      guardPlatformCall(() => bindings.host.predictedLabel(handle, text));

  /// The likely labels for [text], most likely first.
  Future<List<Hypothesis>> labelHypotheses(
    String text, {
    int maximumCount = 5,
  }) async {
    final result = await guardPlatformCall(
      () => bindings.host.predictedLabelHypotheses(handle, text, maximumCount),
    );
    return [for (final item in result) Hypothesis(item.label, item.confidence)];
  }

  /// One label per token, for sequence models.
  Future<List<String>> labelsForTokens(List<String> tokens) =>
      guardPlatformCall(
        () => bindings.host.predictedLabelsForTokens(handle, tokens),
      );

  @override
  String toString() => 'TextModel(${type.name}, $language)';
}

/// A list of terms and their labels (Apple's `NLGazetteer`), used to tag
/// known names with [Tagger.tags].
final class Gazetteer extends NativeResource {
  Gazetteer._(super.handle);

  /// Loads a compiled gazetteer file.
  static Future<Gazetteer> load(String path) async {
    final host = NaturalLanguageBindings.instance.host;
    return Gazetteer._(await guardPlatformCall(() => host.loadGazetteer(path)));
  }

  /// Builds a gazetteer from label → terms, for example
  /// `{'Fruit': ['apple', 'pear']}`.
  static Future<Gazetteer> create(
    Map<String, List<String>> entries, {
    String? language,
  }) async {
    final host = NaturalLanguageBindings.instance.host;
    return Gazetteer._(
      await guardPlatformCall(() => host.createGazetteer(entries, language)),
    );
  }

  /// The label for [text], or null if it is not listed.
  Future<String?> label(String text) =>
      guardPlatformCall(() => bindings.host.gazetteerLabel(handle, text));
}
