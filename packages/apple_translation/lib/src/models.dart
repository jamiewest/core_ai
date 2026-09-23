import 'package:meta/meta.dart';

import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';

/// A language, resolved by Apple's `Locale.Language`.
///
/// Languages are identified by BCP 47 codes such as `en`, `es`, `pt-PT` or
/// `zh-Hant`. Two languages are equal when they resolve to the same
/// [maximalIdentifier], so `zh` equals `zh-Hans` and `en` equals `en-US`.
@immutable
final class Language {
  /// Creates a language from already-resolved parts. Use [resolve] to parse
  /// an identifier.
  const Language({
    required this.identifier,
    required this.maximalIdentifier,
    this.languageCode,
    this.script,
    this.region,
    this.localizedName,
  });

  /// Converts a platform message.
  factory Language.fromMessage(LanguageMessage message) => Language(
    identifier: message.minimalIdentifier,
    maximalIdentifier: message.maximalIdentifier,
    languageCode: message.languageCode,
    script: message.script,
    region: message.region,
    localizedName: message.localizedName,
  );

  /// Parses and normalizes a BCP 47 identifier with `Locale.Language`.
  ///
  /// `Language.resolve('EN_us')` gives `en` (maximal `en-Latn-US`), and
  /// `Language.resolve('zh-Hant')` gives `zh-TW`. Throws
  /// [TranslationErrorCode.invalidArgument] for a blank identifier.
  static Future<Language> resolve(String identifier) async {
    final host = TranslationBindings.instance.host;
    return Language.fromMessage(
      await guardPlatformCall(() => host.language(identifier)),
    );
  }

  /// The shortest identifier for this language (`minimalIdentifier`), such as
  /// `en`, `es-MX` or `zh-TW`. Pass it to any API that takes a language.
  final String identifier;

  /// The identifier with every subtag filled in (`maximalIdentifier`), such
  /// as `en-Latn-US` or `zh-Hans-CN`.
  final String maximalIdentifier;

  /// The ISO 639 language code, such as `en` or `zh`.
  final String? languageCode;

  /// The ISO 15924 script code, such as `Latn` or `Hans`.
  final String? script;

  /// The region code, such as `US`, `TW` or `419`.
  final String? region;

  /// The language's name in the user's current locale, such as
  /// "Spanish (Mexico)".
  final String? localizedName;

  @override
  bool operator ==(Object other) =>
      other is Language && other.maximalIdentifier == maximalIdentifier;

  @override
  int get hashCode => maximalIdentifier.hashCode;

  @override
  String toString() => identifier;
}

/// Whether a language pair can be translated on this device
/// (`LanguageAvailability.Status`).
enum LanguageStatus {
  /// The languages are downloaded and ready to use.
  installed,

  /// The pair is supported, but its languages must be downloaded first.
  supported,

  /// The pair cannot be translated.
  unsupported;

  /// Converts a platform message.
  static LanguageStatus fromMessage(LanguageStatusMessage message) =>
      switch (message) {
        LanguageStatusMessage.installed => installed,
        LanguageStatusMessage.supported => supported,
        LanguageStatusMessage.unsupported => unsupported,
      };
}

/// How the framework trades quality for speed
/// (`TranslationSession.Strategy`, iOS 26.4 / macOS 26.4).
enum TranslationStrategy {
  /// The best translation quality. The system default.
  highFidelity,

  /// Faster translation with a smaller model, which may need its own
  /// download.
  lowLatency;

  /// Converts a platform message.
  static TranslationStrategy fromMessage(StrategyMessage message) =>
      switch (message) {
        StrategyMessage.highFidelity => highFidelity,
        StrategyMessage.lowLatency => lowLatency,
      };

  /// Converts to a platform message.
  StrategyMessage toMessage() => switch (this) {
    highFidelity => StrategyMessage.highFidelity,
    lowLatency => StrategyMessage.lowLatency,
  };
}

/// A run of text that is translated or, with [skipsTranslation], left as is.
///
/// Mirrors an `AttributedString` run with the `skipsTranslation` attribute
/// (iOS 26.4 / macOS 26.4). Use it to keep product names, code or
/// placeholders untouched.
@immutable
final class TextSegment {
  /// A run of text to translate.
  const TextSegment(this.text) : skipsTranslation = false;

  /// A run of text to keep as is.
  const TextSegment.skip(this.text) : skipsTranslation = true;

  /// Converts a platform message.
  TextSegment.fromMessage(TextSegmentMessage message)
    : text = message.text,
      skipsTranslation = message.skipsTranslation;

  /// The text of this run.
  final String text;

  /// Whether the framework leaves this run untranslated.
  final bool skipsTranslation;

  /// Converts to a platform message.
  TextSegmentMessage toMessage() =>
      TextSegmentMessage(text: text, skipsTranslation: skipsTranslation);

  @override
  bool operator ==(Object other) =>
      other is TextSegment &&
      other.text == text &&
      other.skipsTranslation == skipsTranslation;

  @override
  int get hashCode => Object.hash(text, skipsTranslation);

  @override
  String toString() => skipsTranslation ? 'TextSegment.skip($text)' : text;
}

/// One entry of a batch translation (`TranslationSession.Request`).
@immutable
final class TranslationRequest {
  /// Plain text to translate.
  const TranslationRequest(this.sourceText, {this.clientIdentifier})
    : segments = null;

  /// Text made of [segments], some of which may skip translation
  /// (iOS 26.4 / macOS 26.4).
  TranslationRequest.segments(
    List<TextSegment> segments, {
    this.clientIdentifier,
  }) : segments = List.unmodifiable(segments),
       sourceText = segments.map((segment) => segment.text).join();

  /// The text to translate.
  final String sourceText;

  /// The runs of attributed text, or null for plain text.
  final List<TextSegment>? segments;

  /// An identifier of your choice, returned on the matching
  /// [TranslationResponse] so batch results can be matched to requests.
  final String? clientIdentifier;

  /// Converts to a platform message.
  TranslationRequestMessage toMessage() => TranslationRequestMessage(
    sourceText: sourceText,
    segments: segments?.map((segment) => segment.toMessage()).toList(),
    clientIdentifier: clientIdentifier,
  );
}

/// The result of translating one piece of text
/// (`TranslationSession.Response`).
@immutable
final class TranslationResponse {
  /// Creates a response.
  const TranslationResponse({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.sourceText,
    required this.targetText,
    this.targetSegments,
    this.clientIdentifier,
  });

  /// Converts a platform message.
  factory TranslationResponse.fromMessage(TranslationResponseMessage message) =>
      TranslationResponse(
        sourceLanguage: Language.fromMessage(message.sourceLanguage),
        targetLanguage: Language.fromMessage(message.targetLanguage),
        sourceText: message.sourceText,
        targetText: message.targetText,
        targetSegments: message.targetSegments
            ?.map(TextSegment.fromMessage)
            .toList(growable: false),
        clientIdentifier: message.clientIdentifier,
      );

  /// The language the text was translated from.
  final Language sourceLanguage;

  /// The language the text was translated into.
  final Language targetLanguage;

  /// The original text.
  final String sourceText;

  /// The translation.
  final String targetText;

  /// The runs of the attributed translation, when the request was made of
  /// [TextSegment]s. Skipped runs come back with
  /// [TextSegment.skipsTranslation] set.
  final List<TextSegment>? targetSegments;

  /// The [TranslationRequest.clientIdentifier] of the request.
  final String? clientIdentifier;

  @override
  String toString() =>
      'TranslationResponse($sourceLanguage -> $targetLanguage: $targetText)';
}
