/// Flutter bindings for Apple's Translation framework: on-device translation
/// between installed languages, language availability checks, batch
/// translation and text that skips translation.
///
/// ```dart
/// final status = await const LanguageAvailability().status(
///   from: 'en',
///   to: 'es',
/// );
/// if (status == LanguageStatus.installed) {
///   final session = await TranslationSession.create(
///     installedSource: 'en',
///     target: 'es',
///   );
///   final response = await session.translate('Hello, how are you?');
///   print(response.targetText); // Hola, ¿cómo estás?
///   await session.dispose();
/// }
/// ```
library;

export 'src/errors.dart' show TranslationErrorCode, TranslationException;
export 'src/language_availability.dart';
export 'src/models.dart';
export 'src/native_resource.dart' show NativeResource;
export 'src/session.dart';
export 'src/translation.dart';
