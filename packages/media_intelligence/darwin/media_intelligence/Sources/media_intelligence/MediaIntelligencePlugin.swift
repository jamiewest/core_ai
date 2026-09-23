import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Registers the media_intelligence Pigeon APIs with a Flutter engine.
///
/// `MediaIntelligencePlatformApi` is always available.
/// `MediaIntelligenceHostApi` is only registered on iOS 27 / macOS 27 and
/// later; on older systems Dart sees `isSupported() == false`.
public final class MediaIntelligencePlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  /// A `MediaIntelligenceHostApiImpl` when the framework is available.
  private var hostApi: AnyObject?

  private init(messenger: FlutterBinaryMessenger) {
    self.messenger = messenger
  }

  public static func register(with registrar: FlutterPluginRegistrar) {
    // Workaround for https://github.com/flutter/flutter/issues/118103.
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let plugin = MediaIntelligencePlugin(messenger: messenger)
    MediaIntelligencePlatformApiSetup.setUp(binaryMessenger: messenger, api: PlatformApi())
    #if canImport(MediaIntelligence)
      if #available(iOS 27.0, macOS 27.0, *) {
        let callback = MediaIntelligenceCallbackApi(binaryMessenger: messenger)
        let hostApi = MediaIntelligenceHostApiImpl(callback: callback)
        MediaIntelligenceHostApiSetup.setUp(binaryMessenger: messenger, api: hostApi)
        plugin.hostApi = hostApi
      }
    #endif
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    MediaIntelligencePlatformApiSetup.setUp(binaryMessenger: messenger, api: nil)
    MediaIntelligenceHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    #if canImport(MediaIntelligence)
      if #available(iOS 27.0, macOS 27.0, *),
        let hostApi = hostApi as? MediaIntelligenceHostApiImpl
      {
        hostApi.shutdown()
      }
    #endif
    hostApi = nil
  }
}

/// `MediaIntelligencePlatformApi`: works on every OS version.
private final class PlatformApi: MediaIntelligencePlatformApi {
  func isSupported() throws -> Bool {
    #if canImport(MediaIntelligence)
      if #available(iOS 27.0, macOS 27.0, *) { return true }
    #endif
    return false
  }
}
