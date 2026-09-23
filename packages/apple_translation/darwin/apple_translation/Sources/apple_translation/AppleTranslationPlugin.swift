import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Registers the apple_translation Pigeon APIs with a Flutter engine.
///
/// `AppleTranslationPlatformApi` is always available. `AppleTranslationHostApi`
/// is only registered when the Translation framework is (iOS 18+ /
/// macOS 15+); on older systems Dart sees `isSupported() == false`.
public final class AppleTranslationPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  /// An `AppleTranslationHostApiImpl` when the framework is available.
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
    let plugin = AppleTranslationPlugin(messenger: messenger)
    AppleTranslationPlatformApiSetup.setUp(binaryMessenger: messenger, api: PlatformApi())
    #if canImport(Translation)
      if #available(iOS 18.0, macOS 15.0, *) {
        let callback = AppleTranslationCallbackApi(binaryMessenger: messenger)
        let hostApi = AppleTranslationHostApiImpl(callback: callback)
        AppleTranslationHostApiSetup.setUp(binaryMessenger: messenger, api: hostApi)
        plugin.hostApi = hostApi
      }
    #endif
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    AppleTranslationPlatformApiSetup.setUp(binaryMessenger: messenger, api: nil)
    AppleTranslationHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    #if canImport(Translation)
      if #available(iOS 18.0, macOS 15.0, *),
        let hostApi = hostApi as? AppleTranslationHostApiImpl
      {
        hostApi.shutdown()
      }
    #endif
    hostApi = nil
  }
}

/// `AppleTranslationPlatformApi`: works on every OS version.
private final class PlatformApi: AppleTranslationPlatformApi {
  func isSupported() throws -> Bool {
    #if canImport(Translation)
      if #available(iOS 18.0, macOS 15.0, *) { return true }
    #endif
    return false
  }

  func isInstalledSessionSupported() throws -> Bool {
    #if canImport(Translation)
      if #available(iOS 26.0, macOS 26.0, *) { return true }
    #endif
    return false
  }

  func isStrategySupported() throws -> Bool {
    #if canImport(Translation)
      if #available(iOS 26.4, macOS 26.4, *) { return true }
    #endif
    return false
  }
}
