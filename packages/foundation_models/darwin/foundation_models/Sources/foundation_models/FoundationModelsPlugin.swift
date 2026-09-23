import Foundation

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Registers the foundation_models Pigeon APIs with a Flutter engine.
///
/// `FoundationModelsPlatformApi` is always available. `FoundationModelsHostApi`
/// is only registered when the Foundation Models framework is (iOS 26+ /
/// macOS 26+); on older systems Dart sees `isSupported() == false`.
public final class FoundationModelsPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  /// A `FoundationModelsHostApiImpl` when the framework is available.
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
    let plugin = FoundationModelsPlugin(messenger: messenger)
    FoundationModelsPlatformApiSetup.setUp(binaryMessenger: messenger, api: PlatformApi())
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) {
        let callback = FoundationModelsCallbackApi(binaryMessenger: messenger)
        let hostApi = FoundationModelsHostApiImpl(callback: callback)
        FoundationModelsHostApiSetup.setUp(binaryMessenger: messenger, api: hostApi)
        plugin.hostApi = hostApi
      }
    #endif
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    FoundationModelsPlatformApiSetup.setUp(binaryMessenger: messenger, api: nil)
    FoundationModelsHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *),
        let hostApi = hostApi as? FoundationModelsHostApiImpl
      {
        hostApi.shutdown()
      }
    #endif
    hostApi = nil
  }
}

/// `FoundationModelsPlatformApi`: works on every OS version.
private final class PlatformApi: FoundationModelsPlatformApi {
  func isSupported() throws -> Bool {
    #if canImport(FoundationModels)
      if #available(iOS 26.0, macOS 26.0, *) { return true }
    #endif
    return false
  }

  func isVersion27Supported() throws -> Bool {
    #if canImport(FoundationModels)
      if #available(iOS 27.0, macOS 27.0, *) { return true }
    #endif
    return false
  }
}
