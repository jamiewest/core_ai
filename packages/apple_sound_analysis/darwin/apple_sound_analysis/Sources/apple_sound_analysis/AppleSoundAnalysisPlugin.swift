import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Registers the apple_sound_analysis Pigeon APIs with a Flutter engine.
public final class AppleSoundAnalysisPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  private var host: AnyObject?

  private init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let plugin = AppleSoundAnalysisPlugin(messenger: messenger)
    AppleSoundAnalysisPlatformApiSetup.setUp(binaryMessenger: messenger, api: PlatformApi())
    #if canImport(SoundAnalysis)
      let host = AppleSoundAnalysisHostApiImpl(
        callback: AppleSoundAnalysisCallbackApi(binaryMessenger: messenger))
      AppleSoundAnalysisHostApiSetup.setUp(binaryMessenger: messenger, api: host)
      plugin.host = host
    #endif
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    AppleSoundAnalysisPlatformApiSetup.setUp(binaryMessenger: messenger, api: nil)
    AppleSoundAnalysisHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    #if canImport(SoundAnalysis)
      (host as? AppleSoundAnalysisHostApiImpl)?.shutdown()
    #endif
    host = nil
  }
}

private final class PlatformApi: AppleSoundAnalysisPlatformApi {
  func isSupported() throws -> Bool {
    #if canImport(SoundAnalysis)
      return true
    #else
      return false
    #endif
  }
}
