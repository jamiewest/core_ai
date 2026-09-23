## 0.1.0

* Initial release: Natural Language bindings for iOS 15+ / macOS 12+ over
  Pigeon platform channels.
* `LanguageRecognizer`: dominant language and ranked hypotheses with hints
  and constraints.
* `Tokenizer` and `Tagger`: words, sentences and paragraphs; lexical class,
  named entities, lemmas, language, script and sentiment; tag hypotheses,
  available schemes and asset downloads. Offsets are UTF-16, matching Dart
  strings.
* `Embedding` (word, sentence and custom), `ContextualEmbedding` (iOS 17 /
  macOS 14), custom Create ML `TextModel`s and `Gazetteer`s.
* Typed errors, handle lifecycle with finalizers, and a testing library for
  fakes.
* Request English named-entity assets in integration tests and report the
  iOS all-`Other` result as a skip; document the asset requirement.
