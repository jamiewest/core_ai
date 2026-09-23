import 'bindings.dart';
import 'errors.dart';

/// Framework-level queries and housekeeping.
abstract final class Translation {
  /// Whether the Translation framework is available (iOS 18 / macOS 15):
  /// [LanguageAvailability] works.
  static Future<bool> isSupported() =>
      _platformFlag(() => TranslationBindings.instance.platform.isSupported());

  /// Whether sessions can be created without SwiftUI (iOS 26 / macOS 26):
  /// `TranslationSession.create` works.
  static Future<bool> isInstalledSessionSupported() => _platformFlag(
    () => TranslationBindings.instance.platform.isInstalledSessionSupported(),
  );

  /// Whether strategies and attributed text work (iOS 26.4 / macOS 26.4):
  /// `TranslationStrategy`, `TextSegment` and
  /// `TranslationSession.translateSegments`.
  static Future<bool> isStrategySupported() => _platformFlag(
    () => TranslationBindings.instance.platform.isStrategySupported(),
  );

  static Future<bool> _platformFlag(Future<bool> Function() body) async {
    try {
      return await body();
    } on Object {
      return false;
    }
  }

  /// Releases every native session this engine created. Useful after a hot
  /// restart. Returns how many were released.
  static Future<int> releaseAll() {
    final host = TranslationBindings.instance.host;
    return guardPlatformCall(host.releaseAll);
  }

  /// How many native sessions are alive, for leak checks.
  static Future<int> liveHandleCount() {
    final host = TranslationBindings.instance.host;
    return guardPlatformCall(host.liveHandleCount);
  }
}
