import 'package:flutter/services.dart';

import 'bindings.dart';
import 'errors.dart';

/// Framework-level queries and housekeeping.
abstract final class MediaIntelligence {
  /// Whether MediaIntelligence is available: iOS 27 / macOS 27 and later.
  static Future<bool> isSupported() async {
    try {
      return await MediaIntelligenceBindings.instance.platform.isSupported();
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Releases every face analyzer this engine opened. Useful after a hot
  /// restart. Returns how many were released.
  static Future<int> releaseAll() => guardPlatformCall(
    () => MediaIntelligenceBindings.instance.host.releaseAll(),
  );

  /// How many face analyzers are open, for leak checks.
  static Future<int> liveHandleCount() => guardPlatformCall(
    () => MediaIntelligenceBindings.instance.host.liveHandleCount(),
  );
}
