/// Flutter bindings for Apple's Natural Language framework: language
/// identification, tokenization, tagging (parts of speech, names, lemmas,
/// sentiment), word and sentence embeddings, contextual embeddings, and
/// custom Create ML text models.
///
/// ```dart
/// final language = await LanguageRecognizer.dominantLanguage('Bonjour !');
/// final names = await Tagger.tags(
///   'Tim Cook visited Paris.',
///   scheme: TagScheme.nameType,
///   options: {TaggerOption.omitWhitespace, TaggerOption.joinNames},
/// );
/// ```
library;

export 'src/errors.dart'
    show NaturalLanguageErrorCode, NaturalLanguageException;
export 'src/models.dart';
export 'src/native_resource.dart' show NativeResource;
export 'src/natural_language.dart';
export 'src/text.dart';
