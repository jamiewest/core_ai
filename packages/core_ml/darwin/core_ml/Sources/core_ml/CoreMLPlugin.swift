import Foundation

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Registers the core_ml Pigeon APIs with a Flutter engine.
///
/// `CoreMLPlatformApi` is always available. `CoreMLHostApi` is only registered
/// on iOS 18+ / macOS 15+, the versions that have `MLState`, multi-function
/// models and strided `MLMultiArray`s; on older systems Dart sees
/// `isSupported() == false`.
public final class CoreMLPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  /// A `CoreMLHostApiImpl` when Core ML's iOS 18 surface is available.
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
    let plugin = CoreMLPlugin(messenger: messenger)
    CoreMLPlatformApiSetup.setUp(binaryMessenger: messenger, api: PlatformApi())
    #if canImport(CoreML)
      if #available(iOS 18.0, macOS 15.0, *) {
        let hostApi = CoreMLHostApiImpl()
        CoreMLHostApiSetup.setUp(binaryMessenger: messenger, api: hostApi)
        plugin.hostApi = hostApi
      }
    #endif
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    CoreMLPlatformApiSetup.setUp(binaryMessenger: messenger, api: nil)
    CoreMLHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    #if canImport(CoreML)
      if #available(iOS 18.0, macOS 15.0, *), let hostApi = hostApi as? CoreMLHostApiImpl {
        _ = hostApi.registry.removeAll()
      }
    #endif
    hostApi = nil
  }
}

/// `CoreMLPlatformApi`: works on every OS version.
private final class PlatformApi: CoreMLPlatformApi {
  func isSupported() throws -> Bool {
    #if canImport(CoreML)
      if #available(iOS 18.0, macOS 15.0, *) { return true }
    #endif
    return false
  }

  func platformVersion() throws -> String {
    #if os(iOS)
      return "\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)"
    #else
      return "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
    #endif
  }

  func assetPath(assetKey: String, package: String?) throws -> String? {
    let key =
      package.map { FlutterDartProject.lookupKey(forAsset: assetKey, fromPackage: $0) }
      ?? FlutterDartProject.lookupKey(forAsset: assetKey)
    // The key is relative to the app bundle on iOS, and to the resources of
    // App.framework on macOS; check each plausible root.
    var roots: [URL] = [Bundle.main.bundleURL]
    if let resources = Bundle.main.resourceURL { roots.append(resources) }
    if let frameworks = Bundle.main.privateFrameworksURL {
      roots.append(frameworks.appendingPathComponent("App.framework"))
      roots.append(frameworks.appendingPathComponent("App.framework/Resources"))
    }
    return roots.map { $0.appendingPathComponent(key).path }
      .first { FileManager.default.fileExists(atPath: $0) }
  }
}
