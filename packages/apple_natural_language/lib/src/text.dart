import 'package:flutter/foundation.dart';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'models.dart';

/// A span of text, in UTF-16 code units: the same indexing Dart uses for
/// `String`, so `text.substring(range.start, range.end)` extracts it.
@immutable
final class TextRange {
  /// Creates a range.
  const TextRange(this.start, this.length);

  /// The first code unit.
  final int start;

  /// How many code units the range spans.
  final int length;

  /// One past the last code unit.
  int get end => start + length;

  /// The substring of [text] this range covers.
  String of(String text) => text.substring(start, end);

  @override
  bool operator ==(Object other) =>
      other is TextRange && other.start == start && other.length == length;

  @override
  int get hashCode => Object.hash(start, length);

  @override
  String toString() => '[$start, $end)';
}

/// The size of the pieces text is split into (Apple's `NLTokenUnit`).
enum TokenUnit {
  /// Words.
  word,

  /// Sentences.
  sentence,

  /// Paragraphs.
  paragraph,

  /// The whole text.
  document;

  /// The Pigeon representation.
  TokenUnitMessage toMessage() => TokenUnitMessage.values[index];
}

/// Properties of a token (Apple's `NLTokenizer.Attributes`).
enum TokenAttribute {
  /// Contains digits.
  numeric,

  /// Contains symbols.
  symbolic,

  /// Contains emoji.
  emoji,
}

/// One token of a text.
@immutable
final class Token {
  /// Creates a token.
  const Token(this.range, this.text, this.attributes);

  /// Where the token is.
  final TextRange range;

  /// The token's text.
  final String text;

  /// The token's properties.
  final Set<TokenAttribute> attributes;

  @override
  String toString() => 'Token("$text" $range)';
}

/// What a tagger labels (Apple's `NLTagScheme`).
enum TagScheme {
  /// Word, punctuation, whitespace or other.
  tokenType,

  /// Part of speech. See [TagValue] for the values.
  lexicalClass,

  /// Named entities: people, places, organizations.
  nameType,

  /// [nameType] for names, [lexicalClass] for everything else.
  nameTypeOrLexicalClass,

  /// The dictionary form of each word ("running" → "run").
  lemma,

  /// The language of each token.
  language,

  /// The script of each token.
  script,

  /// Sentiment from -1.0 (negative) to 1.0 (positive), per sentence or
  /// paragraph.
  sentimentScore;

  /// The Pigeon representation.
  TagSchemeMessage toMessage() => TagSchemeMessage.values[index];
}

/// Which tokens a tagger skips or merges (Apple's `NLTagger.Options`).
enum TaggerOption {
  /// Skip words.
  omitWords,

  /// Skip punctuation.
  omitPunctuation,

  /// Skip whitespace.
  omitWhitespace,

  /// Skip everything else.
  omitOther,

  /// Treat multi-word names ("New York") as one token.
  joinNames,

  /// Treat contractions ("don't") as one token.
  joinContractions;

  /// The Pigeon representation.
  TagOptionMessage toMessage() => TagOptionMessage.values[index];
}

/// Common tag values (Apple's `NLTag` constants).
abstract final class TagValue {
  /// A noun.
  static const noun = 'Noun';

  /// A verb.
  static const verb = 'Verb';

  /// An adjective.
  static const adjective = 'Adjective';

  /// An adverb.
  static const adverb = 'Adverb';

  /// A pronoun.
  static const pronoun = 'Pronoun';

  /// A determiner.
  static const determiner = 'Determiner';

  /// A preposition.
  static const preposition = 'Preposition';

  /// A number.
  static const number = 'Number';

  /// A person's name.
  static const personalName = 'PersonalName';

  /// A place's name.
  static const placeName = 'PlaceName';

  /// An organization's name.
  static const organizationName = 'OrganizationName';

  /// A word, in [TagScheme.tokenType].
  static const word = 'Word';

  /// Punctuation, in [TagScheme.tokenType].
  static const punctuation = 'Punctuation';

  /// Whitespace, in [TagScheme.tokenType].
  static const whitespace = 'Whitespace';
}

/// A tagged token.
@immutable
final class Tag {
  /// Creates a tag.
  const Tag(this.range, this.text, this.tag);

  /// Where the token is.
  final TextRange range;

  /// The token's text.
  final String text;

  /// The tag, or null if the tagger had none for this token.
  final String? tag;

  @override
  String toString() => '"$text": $tag';
}

/// A candidate with a confidence, such as a language or a tag.
@immutable
final class Hypothesis {
  /// Creates a hypothesis.
  const Hypothesis(this.value, this.confidence);

  /// The candidate.
  final String value;

  /// How likely it is, from 0 to 1.
  final double confidence;

  @override
  String toString() => '$value (${confidence.toStringAsFixed(2)})';
}

/// Whether on-demand language assets are present (Apple's `AssetsResult`).
enum AssetsResult {
  /// The assets are on the device.
  available,

  /// The assets cannot be downloaded.
  notAvailable,

  /// The request failed.
  error;

  /// Converts from the Pigeon representation.
  static AssetsResult fromMessage(AssetsResultMessage message) =>
      values[message.index];
}

/// Identifies the language of text (Apple's `NLLanguageRecognizer`).
///
/// Languages are BCP 47 codes such as `en`, `fr` or `zh-Hans`.
abstract final class LanguageRecognizer {
  /// The most likely language of [text], or null if it is undetermined.
  static Future<String?> dominantLanguage(String text) {
    final host = NaturalLanguageBindings.instance.host;
    return guardPlatformCall(() => host.dominantLanguage(text));
  }

  /// The most likely languages of [text], most likely first.
  ///
  /// [hints] bias the result towards languages you expect, with prior
  /// probabilities. [constraints] limit the result to those languages.
  static Future<List<Hypothesis>> hypotheses(
    String text, {
    int maximumCount = 5,
    Map<String, double> hints = const {},
    List<String> constraints = const [],
  }) async {
    final host = NaturalLanguageBindings.instance.host;
    final result = await guardPlatformCall(
      () => host.languageHypotheses(text, maximumCount, hints, constraints),
    );
    return [
      for (final item in result) Hypothesis(item.language, item.confidence),
    ];
  }
}

/// Splits text into words, sentences or paragraphs (Apple's `NLTokenizer`).
abstract final class Tokenizer {
  /// The tokens of [text] at [unit] granularity.
  ///
  /// Pass [language] to skip language detection.
  static Future<List<Token>> tokenize(
    String text, {
    TokenUnit unit = TokenUnit.word,
    String? language,
  }) async {
    final host = NaturalLanguageBindings.instance.host;
    final result = await guardPlatformCall(
      () => host.tokenize(text, unit.toMessage(), language),
    );
    return [
      for (final token in result)
        Token(
          TextRange(token.start, token.length),
          text.substring(token.start, token.start + token.length),
          {
            for (final attribute in token.attributes)
              TokenAttribute.values[attribute.index],
          },
        ),
    ];
  }
}

/// Labels tokens with parts of speech, names, lemmas, languages or
/// sentiment (Apple's `NLTagger`).
abstract final class Tagger {
  /// Tags every token of [text] with [scheme].
  ///
  /// [models] (custom Core ML taggers) and [gazetteers] (term lists) refine
  /// the result for [scheme].
  static Future<List<Tag>> tags(
    String text, {
    required TagScheme scheme,
    TokenUnit unit = TokenUnit.word,
    Set<TaggerOption> options = const {},
    String? language,
    List<TextModel> models = const [],
    List<Gazetteer> gazetteers = const [],
  }) async {
    final host = NaturalLanguageBindings.instance.host;
    final result = await guardPlatformCall(
      () => host.tags(
        TagRequestMessage(
          text: text,
          scheme: scheme.toMessage(),
          unit: unit.toMessage(),
          options: [for (final option in options) option.toMessage()],
          language: language,
          modelHandles: [for (final model in models) model.handle],
          gazetteerHandles: [
            for (final gazetteer in gazetteers) gazetteer.handle,
          ],
        ),
      ),
    );
    return [
      for (final tag in result)
        Tag(
          TextRange(tag.start, tag.length),
          text.substring(tag.start, tag.start + tag.length),
          tag.tag,
        ),
    ];
  }

  /// The likely tags of the token at [index], most likely first.
  static Future<List<Hypothesis>> tagHypotheses(
    String text, {
    required int index,
    required TagScheme scheme,
    TokenUnit unit = TokenUnit.word,
    int maximumCount = 5,
  }) async {
    final host = NaturalLanguageBindings.instance.host;
    final result = await guardPlatformCall(
      () => host.tagHypotheses(
        text,
        index,
        scheme.toMessage(),
        unit.toMessage(),
        maximumCount,
      ),
    );
    return [for (final item in result) Hypothesis(item.tag, item.confidence)];
  }

  /// The overall sentiment of [text], from -1.0 (negative) to 1.0
  /// (positive), or null if it could not be scored.
  static Future<double?> sentiment(String text) async {
    final tags = await Tagger.tags(
      text,
      scheme: TagScheme.sentimentScore,
      unit: TokenUnit.paragraph,
    );
    final scores = [
      for (final tag in tags)
        if (double.tryParse(tag.tag ?? '') case final double score) score,
    ];
    if (scores.isEmpty) return null;
    return scores.reduce((a, b) => a + b) / scores.length;
  }

  /// The tag schemes available for [unit] in [language].
  static Future<List<String>> availableTagSchemes({
    TokenUnit unit = TokenUnit.word,
    required String language,
  }) {
    final host = NaturalLanguageBindings.instance.host;
    return guardPlatformCall(
      () => host.availableTagSchemes(unit.toMessage(), language),
    );
  }

  /// Downloads the assets [scheme] needs for [language], if possible.
  static Future<AssetsResult> requestAssets({
    required String language,
    required TagScheme scheme,
  }) async {
    final host = NaturalLanguageBindings.instance.host;
    final result = await guardPlatformCall(
      () => host.requestTaggerAssets(language, scheme.toMessage()),
    );
    return AssetsResult.fromMessage(result);
  }
}
