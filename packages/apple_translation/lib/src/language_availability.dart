import 'bindings.dart';
import 'errors.dart';
import 'messages.g.dart';
import 'models.dart';

/// Which languages the device can translate (`LanguageAvailability`).
///
/// ```dart
/// const availability = LanguageAvailability();
/// final languages = await availability.supportedLanguages;
/// final status = await availability.status(from: 'en', to: 'es');
/// ```
final class LanguageAvailability {
  /// Creates an availability checker. [preferredStrategy] needs iOS 26.4 /
  /// macOS 26.4. The low-latency model is downloaded separately, so the same
  /// pair can be installed for one strategy and not the other.
  const LanguageAvailability({this.preferredStrategy});

  /// The strategy to check, or null for the system default.
  final TranslationStrategy? preferredStrategy;

  AppleTranslationHostApi get _host => TranslationBindings.instance.host;

  StrategyMessage? get _strategy => preferredStrategy?.toMessage();

  /// The system's default strategy (`LanguageAvailability().preferredStrategy`),
  /// or null before iOS 26.4 / macOS 26.4.
  static Future<TranslationStrategy?> defaultStrategy() async {
    final host = TranslationBindings.instance.host;
    final message = await guardPlatformCall(host.defaultStrategy);
    return message == null ? null : TranslationStrategy.fromMessage(message);
  }

  /// Every language the framework can translate, sorted by
  /// [Language.identifier]. Regional variants such as `es-MX` are listed
  /// separately.
  Future<List<Language>> get supportedLanguages async {
    final messages = await guardPlatformCall(
      () => _host.supportedLanguages(_strategy),
    );
    return messages.map(Language.fromMessage).toList(growable: false);
  }

  /// Whether text in [from] can be translated into [to] on this device.
  ///
  /// With a null [to], the system picks a target from the user's preferred
  /// languages. Unknown or identical languages give
  /// [LanguageStatus.unsupported].
  Future<LanguageStatus> status({required String from, String? to}) async =>
      LanguageStatus.fromMessage(
        await guardPlatformCall(() => _host.status(from, to, _strategy)),
      );

  /// Detects the language of [text] and reports whether it can be translated
  /// into [to] (`status(for:to:)`).
  ///
  /// Throws [TranslationErrorCode.unableToIdentifyLanguage] when the language
  /// cannot be detected, which includes empty text. The detected language is
  /// not returned by Apple's API.
  Future<LanguageStatus> statusForText(String text, {String? to}) async =>
      LanguageStatus.fromMessage(
        await guardPlatformCall(() => _host.statusForText(text, to, _strategy)),
      );
}
