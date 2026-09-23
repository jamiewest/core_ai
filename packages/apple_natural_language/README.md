# apple_natural_language

Flutter bindings for Apple's **Natural Language** framework, built on
[Pigeon](https://pub.dev/packages/pigeon) platform channels.

Identify languages, split text into words and sentences, tag parts of speech,
names, lemmas and sentiment, compare meaning with word, sentence and
transformer embeddings, and run custom Create ML text models. Everything runs
on the device and needs no Apple Intelligence.

```dart
import 'package:apple_natural_language/apple_natural_language.dart';

final language = await LanguageRecognizer.dominantLanguage(text); // 'en'
final names = await Tagger.tags(
  'Tim Cook visited Paris.',
  scheme: TagScheme.nameType,
  options: {TaggerOption.joinNames, TaggerOption.omitWhitespace},
);
// "Tim Cook": PersonalName, "Paris": PlaceName
final mood = await Tagger.sentiment('I love it!'); // > 0
```

## Requirements

| | |
|---|---|
| Everything except below | iOS 15+ / macOS 12+ |
| `ContextualEmbedding` | iOS 17+ / macOS 14+ |
| Toolchain | Xcode 27, Flutter 3.38+ |

On unsupported platforms `NaturalLanguage.isSupported()` returns false and
calls throw `NaturalLanguageErrorCode.unsupported`.

**Tested:** 14 unit tests, the integration suite (15 tests), and the example
app test pass on macOS 27. The iOS example builds. The original iOS 27 device
run passed 14 of 15 integration tests; named-entity tagging returned only
`Other`. The test now requests assets and explicitly skips that iOS case.
Verification of the updated test on the iPhone is pending: the latest
wireless attempt built successfully but could not connect to the Dart
debugger, and the device reported that a passcode was required.

## Text offsets

Every range (`TextRange`, `Token.range`, `Tag.range`) is in UTF-16 code
units, the same indexing Dart uses for `String`, so `range.of(text)` or
`text.substring(range.start, range.end)` extracts the right characters even
around emoji. Each result also carries its `text`.

## Language identification

```dart
await LanguageRecognizer.dominantLanguage('Bonjour tout le monde'); // 'fr'
await LanguageRecognizer.hypotheses(
  text,
  maximumCount: 3,
  hints: {'es': 0.7, 'pt': 0.3},  // prior probabilities
  constraints: ['es', 'pt'],      // only consider these
);
```

Languages are BCP 47 codes such as `en`, `fr` or `zh-Hans`.

## Tokenizing and tagging

```dart
final words = await Tokenizer.tokenize(text);                 // words
final sentences = await Tokenizer.tokenize(text, unit: TokenUnit.sentence);

final classes = await Tagger.tags(
  text,
  scheme: TagScheme.lexicalClass,  // Noun, Verb, Adjective, ...
  options: {TaggerOption.omitWhitespace, TaggerOption.omitPunctuation},
);
final lemmas = await Tagger.tags(text, scheme: TagScheme.lemma);
final alternatives = await Tagger.tagHypotheses(
  text,
  index: 9,
  scheme: TagScheme.lexicalClass,
);
```

`TagValue` has constants for the common tags. `Tagger.sentiment` scores text
from -1.0 to 1.0 by averaging its paragraphs. `Tagger.availableTagSchemes`
lists what a language supports, and `Tagger.requestAssets` downloads missing
assets.

## Embeddings

```dart
final embedding = await Embedding.wordEmbedding('en');
await embedding.distance('dog', 'puppy');        // small
await embedding.neighbors('dog', maximumCount: 5); // cat, canine, ...
final vector = await embedding.vector('dog');      // Float64List
await embedding.dispose();

final sentences = await Embedding.sentenceEmbedding('en');
```

`ContextualEmbedding` (iOS 17 / macOS 14) is Apple's on-device transformer.
It gives each token a vector that depends on its context, so "bank" differs
between "river bank" and "bank account". Check `hasAvailableAssets`, and call
`requestAssets()` if the assets are missing.

```dart
final model = await ContextualEmbedding.forLanguage('en');
final result = await model.embed('The river bank was muddy.');
final sentenceVector = result.meanVector();
```

## Custom models and gazetteers

```dart
final classifier = await TextModel.load('/path/Sentiment.mlmodelc');
await classifier.predictedLabel('Great service'); // 'positive'

final gazetteer = await Gazetteer.create({
  'Fruit': ['apple', 'mango'],
});
await Tagger.tags(
  text,
  scheme: TagScheme.nameTypeOrLexicalClass,
  gazetteers: [gazetteer],
); // "mango" is tagged Fruit
```

`TextModel` loads compiled Create ML text classifiers and word taggers.
`Embedding.fromFile` loads custom Create ML word embeddings. Pass models to
`Tagger.tags(models: ...)` to tag with them.

## Swift → Dart

| Natural Language (Swift) | apple_natural_language (Dart) |
|---|---|
| `NLLanguageRecognizer` | `LanguageRecognizer` |
| `NLTokenizer`, `NLTokenizer.Attributes` | `Tokenizer`, `TokenAttribute` |
| `NLTagger`, `NLTagScheme`, `NLTagger.Options` | `Tagger`, `TagScheme`, `TaggerOption` |
| `NLTag` constants | `TagValue` |
| `NLTagger.requestAssets` | `Tagger.requestAssets` |
| `NLEmbedding` | `Embedding` |
| `NLContextualEmbedding`, `NLContextualEmbeddingResult` | `ContextualEmbedding`, `ContextualEmbeddingResult` |
| `NLModel` | `TextModel` |
| `NLGazetteer` | `Gazetteer` |
| `NLDistanceType` | `DistanceType` |

## Not bridged

* Creating models, embeddings and compiled gazetteers: that is Create ML,
  which runs on macOS at build time. Load the results with `TextModel.load`,
  `Embedding.fromFile` and `Gazetteer.load`.
* Tagging or tokenizing a sub-range: pass the substring instead, and add its
  start to the returned offsets.
* `NLContextualEmbeddingResult`'s raw model token indices: each token gives
  its text range and vector.

## Known platform behavior

* With `constraints`, Apple pads language hypotheses with zero-confidence
  languages outside them. This package removes those.
* `Embedding.neighbors` and `neighborsOfVector` never return the query itself.
* Named-entity tagging on iOS may need downloaded language assets. Call
  `Tagger.requestAssets(language: 'en', scheme: TagScheme.nameType)` before
  tagging English names. On the test iPhone, missing assets resulted in
  every token being tagged `Other`, including known names. The integration
  test requests assets first and reports a skip if that iOS behavior persists.
* Apple's taggers are statistical: "bark" in "Dogs bark loudly" comes back as
  a noun.

## Errors

Every failure is a `NaturalLanguageException` with a
`NaturalLanguageErrorCode`: `unsupported`, `invalidHandle`,
`invalidArgument` (such as an offset outside the text), `notFound`,
`assetsUnavailable`, `naturalLanguageError` and `unknown`.

## Resources

`Embedding`, `ContextualEmbedding`, `TextModel` and `Gazetteer` own native
objects: call `dispose()`. A `Finalizer` releases forgotten ones eventually.
After a hot restart call `NaturalLanguage.releaseAll()`.
`NaturalLanguage.liveHandleCount()` helps check for leaks.

## Development

```sh
dart run pigeon --input pigeons/apple_natural_language_api.dart
flutter test                                              # Dart unit tests
cd example
flutter test integration_test/apple_natural_language_test.dart -d macos
flutter test integration_test/app_test.dart -d macos

# On a physical device (wireless debugging needs flutter drive):
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/apple_natural_language_test.dart -d <device id> \
  --publish-port
```

Run integration test files one at a time on macOS. For tests of your own app,
`package:apple_natural_language/testing.dart` lets you swap in fake host APIs
with `NaturalLanguageBindings.instance`.
