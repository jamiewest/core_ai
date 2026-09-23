import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Registers the apple_speech Pigeon APIs with a Flutter engine.
///
/// `AppleSpeechPlatformApi` is always available. `AppleSpeechHostApi` is
/// registered when the Speech framework can be imported; its
/// `SpeechAnalyzer` methods need iOS 26 / macOS 26 at run time.
public final class AppleSpeechPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  /// An `AppleSpeechHostApiImpl` when the framework is available.
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
    let plugin = AppleSpeechPlugin(messenger: messenger)
    AppleSpeechPlatformApiSetup.setUp(binaryMessenger: messenger, api: PlatformApi())
    #if canImport(Speech)
      let callback = AppleSpeechCallbackApi(binaryMessenger: messenger)
      let hostApi = AppleSpeechHostApiImpl(callback: callback)
      AppleSpeechHostApiSetup.setUp(binaryMessenger: messenger, api: hostApi)
      plugin.hostApi = hostApi
    #endif
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    AppleSpeechPlatformApiSetup.setUp(binaryMessenger: messenger, api: nil)
    AppleSpeechHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    #if canImport(Speech)
      (hostApi as? AppleSpeechHostApiImpl)?.shutdown()
    #endif
    hostApi = nil
  }
}

/// `AppleSpeechPlatformApi`: works on every OS version.
private final class PlatformApi: AppleSpeechPlatformApi {
  func isSupported() throws -> Bool {
    #if canImport(Speech)
      return true
    #else
      return false
    #endif
  }

  func isAnalyzerSupported() throws -> Bool {
    #if canImport(Speech)
      if #available(iOS 26.0, macOS 26.0, *) { return true }
    #endif
    return false
  }

  func isVersion27Supported() throws -> Bool {
    #if canImport(Speech)
      if #available(iOS 27.0, macOS 27.0, *) { return true }
    #endif
    return false
  }
}
