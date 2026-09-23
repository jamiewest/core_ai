// Pigeon schema for the apple_translation plugin.
//
// Regenerate with:
//   dart run pigeon --input pigeons/apple_translation_api.dart
//   dart format lib/src/messages.g.dart
//
// Languages travel as BCP 47 identifiers (`en`, `es`, `zh-Hans`) and are
// parsed with `Locale.Language(identifier:)` in Swift.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut:
        'darwin/apple_translation/Sources/apple_translation/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'AppleTranslationPigeonError'),
    dartPackageName: 'apple_translation',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------
/// Mirrors `LanguageAvailability.Status`.
enum LanguageStatusMessage { installed, supported, unsupported }

/// Mirrors `TranslationSession.Strategy` (iOS 26.4 / macOS 26.4).
enum StrategyMessage { highFidelity, lowLatency }

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

/// A resolved `Locale.Language`.
class LanguageMessage {
  LanguageMessage({
    required this.minimalIdentifier,
    required this.maximalIdentifier,
    this.languageCode,
    this.script,
    this.region,
    this.localizedName,
  });

  String minimalIdentifier;
  String maximalIdentifier;
  String? languageCode;
  String? script;
  String? region;

  /// The language's name in the user's current locale.
  String? localizedName;
}

/// A run of text, optionally marked with the `skipsTranslation` attribute.
class TextSegmentMessage {
  TextSegmentMessage({required this.text, required this.skipsTranslation});

  String text;
  bool skipsTranslation;
}

/// Mirrors `TranslationSession.Request`.
class TranslationRequestMessage {
  TranslationRequestMessage({
    required this.sourceText,
    this.segments,
    this.clientIdentifier,
  });

  /// Plain text. Ignored when [segments] is set.
  String sourceText;

  /// Attributed text (iOS 26.4 / macOS 26.4).
  List<TextSegmentMessage>? segments;

  String? clientIdentifier;
}

/// Mirrors `TranslationSession.Response`.
class TranslationResponseMessage {
  TranslationResponseMessage({
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.sourceText,
    required this.targetText,
    this.targetSegments,
    this.clientIdentifier,
  });

  LanguageMessage sourceLanguage;
  LanguageMessage targetLanguage;
  String sourceText;
  String targetText;

  /// The runs of `attributedTargetText`, when the request was attributed.
  List<TextSegmentMessage>? targetSegments;

  String? clientIdentifier;
}

/// A newly created `TranslationSession`.
class SessionInfoMessage {
  SessionInfoMessage({
    required this.handle,
    this.sourceLanguage,
    this.targetLanguage,
    required this.canRequestDownloads,
    this.preferredStrategy,
  });

  int handle;
  LanguageMessage? sourceLanguage;
  LanguageMessage? targetLanguage;
  bool canRequestDownloads;

  /// Null before iOS 26.4 / macOS 26.4.
  StrategyMessage? preferredStrategy;
}

/// An error delivered through the callback API.
class ErrorMessage {
  ErrorMessage({required this.code, required this.message, this.details});

  String code;
  String message;
  String? details;
}

// ---------------------------------------------------------------------------
// APIs
// ---------------------------------------------------------------------------

/// Always available.
@HostApi()
abstract class AppleTranslationPlatformApi {
  /// Whether the Translation framework is available (iOS 18 / macOS 15).
  bool isSupported();

  /// Whether `TranslationSession(installedSource:target:)` is available
  /// (iOS 26 / macOS 26).
  bool isInstalledSessionSupported();

  /// Whether translation strategies and attributed text are available
  /// (iOS 26.4 / macOS 26.4).
  bool isStrategySupported();
}

/// Registered only when the framework is available (iOS 18 / macOS 15).
@HostApi()
abstract class AppleTranslationHostApi {
  // -- Languages --------------------------------------------------------------

  /// Resolves a BCP 47 identifier to a `Locale.Language`.
  LanguageMessage language(String identifier);

  // -- LanguageAvailability ---------------------------------------------------
  @async
  List<LanguageMessage> supportedLanguages(StrategyMessage? strategy);

  @async
  LanguageStatusMessage status(
    String source,
    String? target,
    StrategyMessage? strategy,
  );

  @async
  LanguageStatusMessage statusForText(
    String text,
    String? target,
    StrategyMessage? strategy,
  );

  /// `LanguageAvailability().preferredStrategy`, or null before 26.4.
  StrategyMessage? defaultStrategy();

  // -- TranslationSession -----------------------------------------------------

  /// `TranslationSession(installedSource:target:preferredStrategy:)`.
  @async
  SessionInfoMessage createSession(
    String source,
    String? target,
    StrategyMessage? strategy,
  );

  @async
  bool isReady(int handle);

  @async
  TranslationResponseMessage translate(
    int handle,
    TranslationRequestMessage request,
  );

  /// `translations(from:)`: every response at once, in request order.
  @async
  List<TranslationResponseMessage> translations(
    int handle,
    List<TranslationRequestMessage> requests,
  );

  /// `translate(batch:)`: responses arrive through the callback API as they
  /// finish.
  @async
  void startBatch(
    int handle,
    int requestId,
    List<TranslationRequestMessage> requests,
  );

  /// Cancels the Swift task behind a `startBatch` request.
  void cancelRequest(int requestId);

  @async
  void prepareTranslation(int handle);

  /// `TranslationSession.cancel()`. The session cannot be used afterwards.
  void cancelSession(int handle);

  // -- Handles ----------------------------------------------------------------
  @async
  void release(int handle);

  @async
  int releaseAll();

  int liveHandleCount();
}

/// Native -> Dart.
@FlutterApi()
abstract class AppleTranslationCallbackApi {
  void onBatchResponse(int requestId, TranslationResponseMessage response);

  void onBatchDone(int requestId);

  void onBatchError(int requestId, ErrorMessage error);
}
