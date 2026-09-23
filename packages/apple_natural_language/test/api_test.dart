import 'dart:typed_data';

import 'package:apple_natural_language/apple_natural_language.dart';
import 'package:apple_natural_language/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake Natural Language host that records requests.
class FakeHost implements AppleNaturalLanguageHostApi {
  final List<TagRequestMessage> tagRequests = [];
  final List<int> released = [];
  final List<Object?> lastArguments = [];
  List<TagMessage> tagResult = [];
  PlatformException? nextError;
  int _nextHandle = 100;

  void _record(List<Object?> arguments) {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    lastArguments
      ..clear()
      ..addAll(arguments);
  }

  @override
  Future<String?> dominantLanguage(String text) async {
    _record([text]);
    return 'en';
  }

  @override
  Future<List<LanguageHypothesisMessage>> languageHypotheses(
    String text,
    int maximumCount,
    Map<String, double> hints,
    List<String> constraints,
  ) async {
    _record([text, maximumCount, hints, constraints]);
    return [
      LanguageHypothesisMessage(language: 'es', confidence: 0.9),
      LanguageHypothesisMessage(language: 'pt', confidence: 0.1),
    ];
  }

  @override
  Future<List<TokenMessage>> tokenize(
    String text,
    TokenUnitMessage unit,
    String? language,
  ) async {
    _record([text, unit, language]);
    // "I 🍕 love": the emoji is two UTF-16 code units.
    return [
      TokenMessage(start: 0, length: 1, attributes: []),
      TokenMessage(
        start: 2,
        length: 2,
        attributes: [TokenAttributeMessage.emoji],
      ),
      TokenMessage(start: 5, length: 4, attributes: []),
    ];
  }

  @override
  Future<List<TagMessage>> tags(TagRequestMessage request) async {
    _record([request]);
    tagRequests.add(request);
    return tagResult;
  }

  @override
  Future<List<TagHypothesisMessage>> tagHypotheses(
    String text,
    int index,
    TagSchemeMessage scheme,
    TokenUnitMessage unit,
    int maximumCount,
  ) async {
    _record([text, index, scheme, unit, maximumCount]);
    return [TagHypothesisMessage(tag: 'Noun', confidence: 0.8)];
  }

  @override
  Future<AssetsResultMessage> requestTaggerAssets(
    String language,
    TagSchemeMessage scheme,
  ) async {
    _record([language, scheme]);
    return AssetsResultMessage.notAvailable;
  }

  @override
  Future<EmbeddingInfoMessage> loadWordEmbedding(
    String language,
    int? revision,
  ) async {
    _record([language, revision]);
    return EmbeddingInfoMessage(
      handle: _nextHandle++,
      dimension: 3,
      vocabularySize: 1000,
      language: language,
      revision: revision ?? 1,
    );
  }

  @override
  Future<Float64List?> embeddingVector(int handle, String text) async {
    _record([handle, text]);
    return text == 'dog' ? Float64List.fromList([1, 2, 3]) : null;
  }

  @override
  Future<List<NeighborMessage>> embeddingNeighbors(
    int handle,
    String text,
    int maximumCount,
    double? maximumDistance,
    DistanceTypeMessage distanceType,
  ) async {
    _record([handle, text, maximumCount, maximumDistance, distanceType]);
    return [NeighborMessage(text: 'cat', distance: 0.7)];
  }

  @override
  Future<ContextualEmbeddingInfoMessage> loadContextualEmbedding(
    String? modelIdentifier,
    String? language,
    String? script,
  ) async {
    _record([modelIdentifier, language, script]);
    return ContextualEmbeddingInfoMessage(
      handle: _nextHandle++,
      modelIdentifier: 'fake-model',
      languages: ['en'],
      scripts: ['Latn'],
      revision: 1,
      dimension: 2,
      maximumSequenceLength: 256,
      hasAvailableAssets: true,
    );
  }

  @override
  Future<ContextualEmbeddingResultMessage> contextualEmbeddingResult(
    int handle,
    String text,
    String? language,
  ) async {
    _record([handle, text, language]);
    return ContextualEmbeddingResultMessage(
      language: 'en',
      sequenceLength: 4,
      tokens: [
        TokenVectorMessage(
          start: 0,
          length: 2,
          vector: Float64List.fromList([1, 4]),
        ),
        TokenVectorMessage(
          start: 3,
          length: 5,
          vector: Float64List.fromList([3, 0]),
        ),
      ],
    );
  }

  @override
  Future<ModelInfoMessage> loadModel(String path) async {
    _record([path]);
    return ModelInfoMessage(
      handle: _nextHandle++,
      type: ModelTypeMessage.sequence,
      language: 'en',
      revision: 2,
    );
  }

  @override
  Future<int> createGazetteer(
    Map<String, List<String>> entries,
    String? language,
  ) async {
    _record([entries, language]);
    return _nextHandle++;
  }

  @override
  Future<void> release(int handle) async => released.add(handle);

  @override
  Future<int> releaseAll() async => 0;

  @override
  Future<int> liveHandleCount() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeHost: ${invocation.memberName}');
}

class FakePlatform implements AppleNaturalLanguagePlatformApi {
  FakePlatform({this.error});

  final PlatformException? error;

  @override
  Future<bool> isSupported() async {
    if (error case final error?) throw error;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakePlatform: ${invocation.memberName}');
}

Matcher throwsNaturalLanguage(NaturalLanguageErrorCode code) => throwsA(
  isA<NaturalLanguageException>().having((e) => e.code, 'code', code),
);

void main() {
  late FakeHost host;

  setUp(() {
    host = FakeHost();
    NaturalLanguageBindings.instance = NaturalLanguageBindings(
      host: host,
      platform: FakePlatform(),
    );
  });

  group('enum parity', () {
    // The Dart layer maps enums to Pigeon messages by index.
    void expectSameNames(List<Enum> dart, List<Enum> message) =>
        expect(dart.map((e) => e.name), message.map((e) => e.name));

    test('matches the Pigeon enums name for name', () {
      expectSameNames(TokenUnit.values, TokenUnitMessage.values);
      expectSameNames(TagScheme.values, TagSchemeMessage.values);
      expectSameNames(TaggerOption.values, TagOptionMessage.values);
      expectSameNames(TokenAttribute.values, TokenAttributeMessage.values);
      expectSameNames(DistanceType.values, DistanceTypeMessage.values);
      expectSameNames(AssetsResult.values, AssetsResultMessage.values);
      expectSameNames(TextModelType.values, ModelTypeMessage.values);
    });
  });

  group('text', () {
    test('TextRange extracts and compares', () {
      const range = TextRange(2, 3);
      expect(range.end, 5);
      expect(range.of('a bcd e'), 'bcd');
      expect(range, const TextRange(2, 3));
      expect(range, isNot(const TextRange(2, 4)));
    });

    test('recognizes languages', () async {
      expect(await LanguageRecognizer.dominantLanguage('hi'), 'en');
      final hypotheses = await LanguageRecognizer.hypotheses(
        'hola',
        maximumCount: 2,
        hints: {'es': 0.5},
        constraints: ['es', 'pt'],
      );
      expect(host.lastArguments, [
        'hola',
        2,
        {'es': 0.5},
        ['es', 'pt'],
      ]);
      expect(hypotheses.map((h) => h.value), ['es', 'pt']);
      expect(hypotheses.first.confidence, 0.9);
    });

    test('tokenizes with UTF-16 offsets and attributes', () async {
      const text = 'I 🍕 love';
      final tokens = await Tokenizer.tokenize(
        text,
        unit: TokenUnit.sentence,
        language: 'en',
      );
      expect(host.lastArguments, [text, TokenUnitMessage.sentence, 'en']);
      expect(tokens.map((t) => t.text), ['I', '🍕', 'love']);
      expect(tokens[1].attributes, {TokenAttribute.emoji});
      expect(tokens[2].range, const TextRange(5, 4));
    });

    test('builds a tag request', () async {
      final gazetteer = await Gazetteer.create({
        'Fruit': ['apple'],
      });
      final model = await TextModel.load('/m.mlmodelc');
      host.tagResult = [
        TagMessage(start: 0, length: 3, tag: 'Noun'),
        TagMessage(start: 4, length: 2),
      ];

      final tags = await Tagger.tags(
        'Tim is',
        scheme: TagScheme.nameType,
        options: {TaggerOption.joinNames, TaggerOption.omitWhitespace},
        language: 'en',
        models: [model],
        gazetteers: [gazetteer],
      );

      final request = host.tagRequests.single;
      expect(request.text, 'Tim is');
      expect(request.scheme, TagSchemeMessage.nameType);
      expect(request.unit, TokenUnitMessage.word);
      expect(request.options, [
        TagOptionMessage.joinNames,
        TagOptionMessage.omitWhitespace,
      ]);
      expect(request.language, 'en');
      expect(request.modelHandles, [model.handle]);
      expect(request.gazetteerHandles, [gazetteer.handle]);
      expect(tags.map((t) => (t.text, t.tag)), [('Tim', 'Noun'), ('is', null)]);
    });

    test('averages paragraph sentiment', () async {
      host.tagResult = [
        TagMessage(start: 0, length: 2, tag: '0.5'),
        TagMessage(start: 3, length: 2, tag: '-0.1'),
      ];
      expect(await Tagger.sentiment('ab cd'), closeTo(0.2, 1e-9));
      final request = host.tagRequests.single;
      expect(request.scheme, TagSchemeMessage.sentimentScore);
      expect(request.unit, TokenUnitMessage.paragraph);

      host.tagResult = [TagMessage(start: 0, length: 2)];
      expect(await Tagger.sentiment('ab'), isNull);
    });

    test('maps tag hypotheses and asset results', () async {
      final hypotheses = await Tagger.tagHypotheses(
        'a book',
        index: 2,
        scheme: TagScheme.lexicalClass,
        maximumCount: 3,
      );
      expect(host.lastArguments, [
        'a book',
        2,
        TagSchemeMessage.lexicalClass,
        TokenUnitMessage.word,
        3,
      ]);
      expect(hypotheses.single.value, 'Noun');
      expect(
        await Tagger.requestAssets(language: 'fr', scheme: TagScheme.lemma),
        AssetsResult.notAvailable,
      );
    });
  });

  group('resources', () {
    test('an embedding exposes its info and forwards calls', () async {
      final embedding = await Embedding.wordEmbedding('en', revision: 2);
      expect(embedding.dimension, 3);
      expect(embedding.vocabularySize, 1000);
      expect(embedding.language, 'en');
      expect(embedding.revision, 2);

      expect(await embedding.vector('dog'), [1, 2, 3]);
      expect(await embedding.vector('zzz'), isNull);

      final neighbors = await embedding.neighbors(
        'dog',
        maximumCount: 4,
        maximumDistance: 0.9,
      );
      expect(host.lastArguments, [
        embedding.handle,
        'dog',
        4,
        0.9,
        DistanceTypeMessage.cosine,
      ]);
      expect(neighbors.single.text, 'cat');
      expect(neighbors.single.distance, 0.7);
    });

    test('dispose releases once and blocks further use', () async {
      final embedding = await Embedding.wordEmbedding('en');
      final handle = embedding.handle;
      await embedding.dispose();
      await embedding.dispose();
      expect(host.released, [handle]);
      expect(embedding.isDisposed, isTrue);
      expect(() => embedding.vector('dog'), throwsStateError);
    });

    test('a contextual embedding maps tokens and averages them', () async {
      final embedding = await ContextualEmbedding.forScript('Latn');
      expect(host.lastArguments, [null, null, 'Latn']);
      expect(embedding.modelIdentifier, 'fake-model');
      expect(embedding.maximumSequenceLength, 256);

      final result = await embedding.embed('hi there');
      expect(result.tokens.map((t) => t.text), ['hi', 'there']);
      expect(result.meanVector(), [2, 2]);
      expect(
        const ContextualEmbeddingResult(
          language: 'en',
          sequenceLength: 0,
          tokens: [],
        ).meanVector(),
        isEmpty,
      );
    });

    test('a text model reports its type', () async {
      final model = await TextModel.load('/m.mlmodelc');
      expect(model.type, TextModelType.sequence);
      expect(model.language, 'en');
      expect(model.revision, 2);
    });
  });

  group('errors', () {
    test('translates wire codes', () async {
      host.nextError = PlatformException(
        code: 'assets_unavailable',
        message: 'No embedding',
      );
      await expectLater(
        Embedding.wordEmbedding('xx'),
        throwsNaturalLanguage(NaturalLanguageErrorCode.assetsUnavailable),
      );

      host.nextError = PlatformException(code: 'something_new');
      await expectLater(
        LanguageRecognizer.dominantLanguage('x'),
        throwsNaturalLanguage(NaturalLanguageErrorCode.unknown),
      );
    });

    test('treats a missing channel as unsupported', () async {
      host.nextError = PlatformException(code: 'channel-error');
      await expectLater(
        Tokenizer.tokenize('x'),
        throwsNaturalLanguage(NaturalLanguageErrorCode.unsupported),
      );
    });

    test('isSupported is false when the platform call fails', () async {
      expect(await NaturalLanguage.isSupported(), isTrue);
      NaturalLanguageBindings.instance = NaturalLanguageBindings(
        host: host,
        platform: FakePlatform(error: PlatformException(code: 'channel-error')),
      );
      expect(await NaturalLanguage.isSupported(), isFalse);
    });
  });
}
