// End-to-end tests against the real Natural Language framework:
//
//   cd example && flutter test integration_test/apple_natural_language_test.dart -d macos

import 'package:apple_natural_language/apple_natural_language.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Matcher throwsNaturalLanguage(NaturalLanguageErrorCode code) => throwsA(
  isA<NaturalLanguageException>().having((e) => e.code, 'code', code),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    expect(await NaturalLanguage.isSupported(), isTrue);
    await NaturalLanguage.releaseAll();
  });

  tearDown(() async {
    final live = await NaturalLanguage.liveHandleCount();
    await NaturalLanguage.releaseAll();
    expect(live, 0, reason: 'a test leaked handles');
  });

  group('language identification', () {
    testWidgets('identifies the dominant language', (_) async {
      expect(
        await LanguageRecognizer.dominantLanguage(
          'The weather is lovely today and I am going for a walk.',
        ),
        'en',
      );
      expect(
        await LanguageRecognizer.dominantLanguage(
          "Il fait très beau aujourd'hui et je vais me promener.",
        ),
        'fr',
      );
      expect(
        await LanguageRecognizer.dominantLanguage(
          'Das Wetter ist heute sehr schön und ich gehe spazieren.',
        ),
        'de',
      );
      expect(await LanguageRecognizer.dominantLanguage('今日はとても良い天気です。'), 'ja');
    });

    testWidgets('ranks hypotheses and honours constraints', (_) async {
      final hypotheses = await LanguageRecognizer.hypotheses(
        'Hola, ¿cómo estás? Espero que todo vaya bien.',
        maximumCount: 3,
      );
      expect(hypotheses.first.value, 'es');
      expect(hypotheses.first.confidence, greaterThan(0.5));

      final constrained = await LanguageRecognizer.hypotheses(
        'Hola, ¿cómo estás?',
        constraints: ['it', 'pt'],
      );
      expect(constrained.map((h) => h.value), everyElement(isIn(['it', 'pt'])));
    });
  });

  group('tokenization', () {
    testWidgets('splits words and sentences', (_) async {
      const text = 'The quick brown fox jumps. It was 42 degrees!';
      final words = await Tokenizer.tokenize(text);
      expect(words.map((t) => t.text), [
        'The',
        'quick',
        'brown',
        'fox',
        'jumps',
        'It',
        'was',
        '42',
        'degrees',
      ]);
      expect(
        words.firstWhere((t) => t.text == '42').attributes,
        contains(TokenAttribute.numeric),
      );

      final sentences = await Tokenizer.tokenize(
        text,
        unit: TokenUnit.sentence,
      );
      expect(sentences, hasLength(2));
      expect(sentences.first.text.trim(), 'The quick brown fox jumps.');
    });

    testWidgets('reports ranges in Dart string offsets', (_) async {
      const text = 'I 🍕 love pizza 東京 now';
      final words = await Tokenizer.tokenize(text);
      for (final word in words) {
        expect(word.range.of(text), word.text);
      }
      expect(words.map((t) => t.text), containsAll(['love', 'pizza', 'now']));
      expect(words.map((t) => t.text), contains('東京'));
    });
  });

  group('tagging', () {
    testWidgets('finds named entities', (_) async {
      final assets = await Tagger.requestAssets(
        language: 'en',
        scheme: TagScheme.nameType,
      );
      final tags = await Tagger.tags(
        'Tim Cook visited Paris with people from Apple.',
        scheme: TagScheme.nameType,
        options: {
          TaggerOption.omitWhitespace,
          TaggerOption.omitPunctuation,
          TaggerOption.joinNames,
        },
      );
      expect(tags, isNotEmpty);
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          tags.every((tag) => tag.tag == 'Other')) {
        markTestSkipped(
          'The iOS named-entity tagger returned only Other after requesting '
          'English assets ($assets); named-entity assets may be unavailable.',
        );
        return;
      }
      final byText = {for (final tag in tags) tag.text: tag.tag};
      expect(byText['Tim Cook'], TagValue.personalName, reason: '$tags');
      expect(byText['Paris'], TagValue.placeName, reason: '$tags');
      expect(byText['Apple'], TagValue.organizationName, reason: '$tags');
    });

    testWidgets('tags parts of speech and lemmas', (_) async {
      final classes = await Tagger.tags(
        'She quickly ate the apple.',
        scheme: TagScheme.lexicalClass,
        options: {TaggerOption.omitWhitespace, TaggerOption.omitPunctuation},
      );
      expect(classes.map((t) => t.tag), [
        TagValue.pronoun,
        TagValue.adverb,
        TagValue.verb,
        TagValue.determiner,
        TagValue.noun,
      ]);

      final lemmas = await Tagger.tags(
        'She was running',
        scheme: TagScheme.lemma,
        options: {TaggerOption.omitWhitespace},
      );
      final byText = {for (final tag in lemmas) tag.text: tag.tag};
      expect(byText['running'], 'run');
      expect(byText['was'], 'be');
    });

    testWidgets('scores sentiment', (_) async {
      final positive = await Tagger.sentiment(
        'I absolutely love this wonderful, delightful product. It is amazing!',
      );
      final negative = await Tagger.sentiment(
        'This is terrible. I hate it and it is the worst thing ever.',
      );
      expect(positive, greaterThan(0));
      expect(negative, lessThan(0));
    });

    testWidgets('lists hypotheses and schemes', (_) async {
      final hypotheses = await Tagger.tagHypotheses(
        'I read a book',
        index: 9,
        scheme: TagScheme.lexicalClass,
      );
      expect(hypotheses.first.value, TagValue.noun);

      final schemes = await Tagger.availableTagSchemes(language: 'en');
      expect(schemes, containsAll(['Lemma', 'LexicalClass', 'NameType']));
    });

    testWidgets('rejects an offset outside the text', (_) async {
      await expectLater(
        Tagger.tagHypotheses(
          'short',
          index: 99,
          scheme: TagScheme.lexicalClass,
        ),
        throwsNaturalLanguage(NaturalLanguageErrorCode.invalidArgument),
      );
    });
  });

  group('embeddings', () {
    testWidgets('measures word similarity', (_) async {
      final embedding = await Embedding.wordEmbedding('en');
      expect(embedding.dimension, greaterThan(0));
      expect(await embedding.contains('dog'), isTrue);

      final close = await embedding.distance('dog', 'puppy');
      final far = await embedding.distance('dog', 'spreadsheet');
      expect(close, lessThan(far));

      final vector = (await embedding.vector('dog'))!;
      expect(vector, hasLength(embedding.dimension));
      expect(await embedding.vector('zzqxv'), isNull);

      final neighbors = await embedding.neighbors('dog', maximumCount: 5);
      expect(neighbors, hasLength(5));
      expect(neighbors.map((n) => n.text), isNot(contains('dog')));
      expect(
        neighbors.first.distance,
        lessThanOrEqualTo(neighbors.last.distance),
      );

      final limited = await embedding.neighbors(
        'dog',
        maximumCount: 50,
        maximumDistance: neighbors[2].distance,
      );
      expect(limited.every((n) => n.distance <= neighbors[2].distance), isTrue);

      final byVector = await embedding.neighborsOfVector(
        vector,
        maximumCount: 3,
      );
      expect(byVector.map((n) => n.text), neighbors.take(3).map((n) => n.text));
      await embedding.dispose();
    });

    testWidgets('embeds sentences', (_) async {
      final embedding = await Embedding.sentenceEmbedding('en');
      final similar = await embedding.distance(
        'The cat sat on the mat.',
        'A cat is sitting on a rug.',
      );
      final different = await embedding.distance(
        'The cat sat on the mat.',
        'Interest rates rose sharply this quarter.',
      );
      expect(similar, lessThan(different));
      await embedding.dispose();
    });

    testWidgets('embeds tokens in context', (_) async {
      final embedding = await ContextualEmbedding.forLanguage('en');
      expect(embedding.dimension, greaterThan(0));
      if (!embedding.hasAvailableAssets) {
        await embedding.dispose();
        markTestSkipped('Contextual embedding assets are not installed.');
        return;
      }
      final result = await embedding.embed('The river bank was muddy.');
      expect(result.tokens, isNotEmpty);
      expect(result.tokens.first.vector, hasLength(embedding.dimension));
      for (final token in result.tokens) {
        expect(token.range.of('The river bank was muddy.'), token.text);
      }
      expect(result.meanVector(), hasLength(embedding.dimension));
      await embedding.dispose();
    });
  });

  group('custom resources', () {
    testWidgets('labels terms with a gazetteer', (_) async {
      final gazetteer = await Gazetteer.create({
        'Fruit': ['apple', 'pear', 'mango'],
        'Vegetable': ['carrot', 'leek'],
      }, language: 'en');
      expect(await gazetteer.label('mango'), 'Fruit');
      expect(await gazetteer.label('leek'), 'Vegetable');
      expect(await gazetteer.label('granite'), isNull);

      final tags = await Tagger.tags(
        'I ate a mango and a carrot.',
        scheme: TagScheme.nameTypeOrLexicalClass,
        options: {TaggerOption.omitWhitespace, TaggerOption.omitPunctuation},
        gazetteers: [gazetteer],
      );
      final byText = {for (final tag in tags) tag.text: tag.tag};
      expect(byText['mango'], 'Fruit');
      expect(byText['carrot'], 'Vegetable');
      await gazetteer.dispose();
    });

    testWidgets('reports a missing model file', (_) async {
      await expectLater(
        TextModel.load('/nonexistent/Classifier.mlmodelc'),
        throwsNaturalLanguage(NaturalLanguageErrorCode.notFound),
      );
    });

    testWidgets('rejects a disposed embedding', (_) async {
      final embedding = await Embedding.wordEmbedding('en');
      await embedding.dispose();
      expect(() => embedding.vector('dog'), throwsStateError);
    });
  });
}
