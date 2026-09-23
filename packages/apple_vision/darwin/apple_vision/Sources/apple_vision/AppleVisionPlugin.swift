import Foundation

#if os(iOS)
  import Flutter
  import UIKit
#elseif os(macOS)
  import FlutterMacOS
#endif

/// Registers the apple_vision Pigeon APIs with a Flutter engine.
///
/// `AppleVisionPlatformApi` is always available. `AppleVisionHostApi` is only
/// registered when Vision's still-image requests are (iOS 27+ / macOS 27+);
/// on older systems Dart sees `isSupported() == false`.
public final class AppleVisionPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger

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
    let plugin = AppleVisionPlugin(messenger: messenger)
    AppleVisionPlatformApiSetup.setUp(binaryMessenger: messenger, api: PlatformApi())
    #if canImport(Vision)
      if #available(iOS 27.0, macOS 27.0, *) {
        AppleVisionHostApiSetup.setUp(
          binaryMessenger: messenger, api: AppleVisionHostApiImpl())
      }
    #endif
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    AppleVisionPlatformApiSetup.setUp(binaryMessenger: messenger, api: nil)
    AppleVisionHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
  }
}

/// `AppleVisionPlatformApi`: works on every OS version.
private final class PlatformApi: AppleVisionPlatformApi {
  func isSupported() throws -> Bool {
    #if canImport(Vision)
      if #available(iOS 27.0, macOS 27.0, *) { return true }
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
