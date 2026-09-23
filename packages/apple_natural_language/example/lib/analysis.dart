import 'package:apple_natural_language/apple_natural_language.dart';

/// Everything the example shows about a text.
class TextAnalysis {
  /// Creates an analysis.
  const TextAnalysis({
    required this.languages,
    required this.sentiment,
    required this.entities,
    required this.partsOfSpeech,
    required this.lemmas,
  });

  /// Likely languages, most likely first.
  final List<Hypothesis> languages;

  /// Overall sentiment from -1 to 1, if it could be scored.
  final double? sentiment;

  /// People, places and organizations.
  final List<Tag> entities;

  /// Each word with its lexical class.
  final List<Tag> partsOfSpeech;

  /// Words whose dictionary form differs, as (word, lemma).
  final List<(String, String)> lemmas;

  /// Runs every analysis on [text].
  static Future<TextAnalysis> of(String text) async {
    const words = {TaggerOption.omitWhitespace, TaggerOption.omitPunctuation};
    final (languages, sentiment, names, classes, lemmas) = await (
      LanguageRecognizer.hypotheses(text, maximumCount: 3),
      Tagger.sentiment(text),
      Tagger.tags(
        text,
        scheme: TagScheme.nameType,
        options: {...words, TaggerOption.joinNames},
      ),
      Tagger.tags(text, scheme: TagScheme.lexicalClass, options: words),
      Tagger.tags(text, scheme: TagScheme.lemma, options: words),
    ).wait;
    return TextAnalysis(
      languages: languages,
      sentiment: sentiment,
      entities: [
        for (final tag in names)
          if (_entityTags.contains(tag.tag)) tag,
      ],
      partsOfSpeech: classes,
      lemmas: [
        for (final tag in lemmas)
          if (tag.tag case final lemma?
              when lemma.toLowerCase() != tag.text.toLowerCase())
            (tag.text, lemma),
      ],
    );
  }

  static const _entityTags = {
    TagValue.personalName,
    TagValue.placeName,
    TagValue.organizationName,
  };
}
