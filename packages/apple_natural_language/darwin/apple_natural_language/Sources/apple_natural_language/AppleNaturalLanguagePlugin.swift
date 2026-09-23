import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Registers the apple_natural_language Pigeon APIs with a Flutter engine.
public final class AppleNaturalLanguagePlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
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
    let plugin = AppleNaturalLanguagePlugin(messenger: messenger)
    AppleNaturalLanguagePlatformApiSetup.setUp(binaryMessenger: messenger, api: PlatformApi())
    #if canImport(NaturalLanguage)
      let hostApi = AppleNaturalLanguageHostApiImpl()
      AppleNaturalLanguageHostApiSetup.setUp(binaryMessenger: messenger, api: hostApi)
      plugin.hostApi = hostApi
    #endif
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    AppleNaturalLanguagePlatformApiSetup.setUp(binaryMessenger: messenger, api: nil)
    AppleNaturalLanguageHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    #if canImport(NaturalLanguage)
      (hostApi as? AppleNaturalLanguageHostApiImpl)?.shutdown()
    #endif
    hostApi = nil
  }
}

/// `AppleNaturalLanguagePlatformApi`: works on every OS version.
private final class PlatformApi: AppleNaturalLanguagePlatformApi {
  func isSupported() throws -> Bool {
    #if canImport(NaturalLanguage)
      return true
    #else
      return false
    #endif
  }
}
