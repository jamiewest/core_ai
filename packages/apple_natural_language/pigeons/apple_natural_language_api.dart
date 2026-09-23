// Pigeon schema for the apple_natural_language plugin.
//
// Regenerate with:
//   dart run pigeon --input pigeons/apple_natural_language_api.dart
//   dart format lib/src/messages.g.dart
//
// Text offsets are UTF-16 code-unit offsets, which is also how Dart indexes
// `String`, so ranges can be used directly with `String.substring`.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'darwin/apple_natural_language/Sources/apple_natural_language/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'AppleNaturalLanguagePigeonError'),
    dartPackageName: 'apple_natural_language',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------
/// Mirrors `NLTokenUnit`.
enum TokenUnitMessage { word, sentence, paragraph, document }

/// Mirrors `NLTagScheme`.
enum TagSchemeMessage {
  tokenType,
  lexicalClass,
  nameType,
  nameTypeOrLexicalClass,
  lemma,
  language,
  script,
  sentimentScore,
}

/// Mirrors `NLTaggerOptions`.
enum TagOptionMessage {
  omitWords,
  omitPunctuation,
  omitWhitespace,
  omitOther,
  joinNames,
  joinContractions,
}

/// Mirrors `NLTokenizerAttributes`.
enum TokenAttributeMessage { numeric, symbolic, emoji }

/// Mirrors `NLDistanceType`.
enum DistanceTypeMessage { cosine }

/// Mirrors `NLModelType`.
enum ModelTypeMessage { classifier, sequence }

/// Mirrors `NLTaggerAssetsResult` / `NLContextualEmbeddingAssetsResult`.
enum AssetsResultMessage { available, notAvailable, error }

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------
class TokenMessage {
  TokenMessage({
    required this.start,
    required this.length,
    required this.attributes,
  });

  int start;
  int length;
  List<TokenAttributeMessage> attributes;
}

class TagMessage {
  TagMessage({required this.start, required this.length, this.tag});

  int start;
  int length;

  /// Null when the tagger had no tag for the token.
  String? tag;
}

class LanguageHypothesisMessage {
  LanguageHypothesisMessage({
    required this.language,
    required this.confidence,
  });

  String language;
  double confidence;
}

class TagHypothesisMessage {
  TagHypothesisMessage({required this.tag, required this.confidence});

  String tag;
  double confidence;
}

class EmbeddingInfoMessage {
  EmbeddingInfoMessage({
    required this.handle,
    required this.dimension,
    required this.vocabularySize,
    this.language,
    required this.revision,
  });

  int handle;
  int dimension;
  int vocabularySize;
  String? language;
  int revision;
}

class NeighborMessage {
  NeighborMessage({required this.text, required this.distance});

  String text;
  double distance;
}

class ContextualEmbeddingInfoMessage {
  ContextualEmbeddingInfoMessage({
    required this.handle,
    required this.modelIdentifier,
    required this.languages,
    required this.scripts,
    required this.revision,
    required this.dimension,
    required this.maximumSequenceLength,
    required this.hasAvailableAssets,
  });

  int handle;
  String modelIdentifier;
  List<String> languages;
  List<String> scripts;
  int revision;
  int dimension;
  int maximumSequenceLength;
  bool hasAvailableAssets;
}

class TokenVectorMessage {
  TokenVectorMessage({
    required this.start,
    required this.length,
    required this.vector,
  });

  int start;
  int length;

  /// The token's embedding, `dimension` values long.
  Float64List vector;
}

class ContextualEmbeddingResultMessage {
  ContextualEmbeddingResultMessage({
    required this.language,
    required this.sequenceLength,
    required this.tokens,
  });

  String language;
  int sequenceLength;
  List<TokenVectorMessage> tokens;
}

class ModelInfoMessage {
  ModelInfoMessage({
    required this.handle,
    required this.type,
    this.language,
    required this.revision,
  });

  int handle;
  ModelTypeMessage type;
  String? language;
  int revision;
}

class LabelHypothesisMessage {
  LabelHypothesisMessage({required this.label, required this.confidence});

  String label;
  double confidence;
}

class TagRequestMessage {
  TagRequestMessage({
    required this.text,
    required this.scheme,
    required this.unit,
    required this.options,
    this.language,
    required this.modelHandles,
    required this.gazetteerHandles,
  });

  String text;
  TagSchemeMessage scheme;
  TokenUnitMessage unit;
  List<TagOptionMessage> options;

  /// Forces the language instead of detecting it.
  String? language;

  /// Custom `NLModel`s to use for this scheme.
  List<int> modelHandles;

  /// Custom `NLGazetteer`s to use for this scheme.
  List<int> gazetteerHandles;
}

// ---------------------------------------------------------------------------
// APIs
// ---------------------------------------------------------------------------

/// Always available.
@HostApi()
abstract class AppleNaturalLanguagePlatformApi {
  /// Whether the Natural Language framework is available.
  bool isSupported();
}

/// Registered only when the framework is available.
@HostApi()
abstract class AppleNaturalLanguageHostApi {
  // -- Language identification ------------------------------------------------
  String? dominantLanguage(String text);

  @async
  List<LanguageHypothesisMessage> languageHypotheses(
    String text,
    int maximumCount,
    Map<String, double> hints,
    List<String> constraints,
  );

  // -- Tokenization -----------------------------------------------------------
  @async
  List<TokenMessage> tokenize(String text, TokenUnitMessage unit, String? language);

  // -- Tagging ----------------------------------------------------------------
  @async
  List<TagMessage> tags(TagRequestMessage request);

  @async
  List<TagHypothesisMessage> tagHypotheses(
    String text,
    int characterIndex,
    TagSchemeMessage scheme,
    TokenUnitMessage unit,
    int maximumCount,
  );

  List<String> availableTagSchemes(TokenUnitMessage unit, String language);

  @async
  AssetsResultMessage requestTaggerAssets(String language, TagSchemeMessage scheme);

  // -- Embeddings -------------------------------------------------------------
  @async
  EmbeddingInfoMessage loadWordEmbedding(String language, int? revision);

  @async
  EmbeddingInfoMessage loadSentenceEmbedding(String language, int? revision);

  @async
  EmbeddingInfoMessage loadEmbeddingFromFile(String path);

  @async
  Float64List? embeddingVector(int handle, String text);

  @async
  double embeddingDistance(
    int handle,
    String first,
    String second,
    DistanceTypeMessage distanceType,
  );

  bool embeddingContains(int handle, String text);

  @async
  List<NeighborMessage> embeddingNeighbors(
    int handle,
    String text,
    int maximumCount,
    double? maximumDistance,
    DistanceTypeMessage distanceType,
  );

  @async
  List<NeighborMessage> embeddingNeighborsForVector(
    int handle,
    Float64List vector,
    int maximumCount,
    double? maximumDistance,
    DistanceTypeMessage distanceType,
  );

  // -- Contextual embeddings --------------------------------------------------
  @async
  ContextualEmbeddingInfoMessage loadContextualEmbedding(
    String? modelIdentifier,
    String? language,
    String? script,
  );

  @async
  AssetsResultMessage requestContextualEmbeddingAssets(int handle);

  @async
  ContextualEmbeddingResultMessage contextualEmbeddingResult(
    int handle,
    String text,
    String? language,
  );

  // -- Custom models and gazetteers -------------------------------------------
  @async
  ModelInfoMessage loadModel(String path);

  @async
  String? predictedLabel(int handle, String text);

  @async
  List<LabelHypothesisMessage> predictedLabelHypotheses(
    int handle,
    String text,
    int maximumCount,
  );

  @async
  List<String> predictedLabelsForTokens(int handle, List<String> tokens);

  @async
  int loadGazetteer(String path);

  @async
  int createGazetteer(Map<String, List<String>> entries, String? language);

  String? gazetteerLabel(int handle, String text);

  // -- Handles ----------------------------------------------------------------
  @async
  void release(int handle);

  @async
  int releaseAll();

  int liveHandleCount();
}
