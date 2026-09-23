import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Registers the media_intelligence Pigeon APIs with a Flutter engine.
public final class MediaIntelligencePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    // TODO: register the Pigeon APIs.
  }
}
