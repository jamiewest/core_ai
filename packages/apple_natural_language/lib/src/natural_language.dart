import 'bindings.dart';
import 'errors.dart';

/// Framework-level queries and housekeeping.
abstract final class NaturalLanguage {
  /// Whether the Natural Language framework is available.
  static Future<bool> isSupported() async {
    try {
      return await NaturalLanguageBindings.instance.platform.isSupported();
    } on Object {
      return false;
    }
  }

  /// Releases every native object this engine created. Useful after a hot
  /// restart. Returns how many were released.
  static Future<int> releaseAll() {
    final host = NaturalLanguageBindings.instance.host;
    return guardPlatformCall(host.releaseAll);
  }

  /// How many native objects are alive, for leak checks.
  static Future<int> liveHandleCount() {
    final host = NaturalLanguageBindings.instance.host;
    return guardPlatformCall(host.liveHandleCount);
  }
}
