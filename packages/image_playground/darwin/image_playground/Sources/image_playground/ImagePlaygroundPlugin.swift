import Foundation
#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif
#if canImport(ImagePlayground)
  import ImagePlayground
#endif

/// Registers the availability API on every supported deployment target.
public final class ImagePlaygroundPlugin: NSObject, FlutterPlugin {
  private let messenger: FlutterBinaryMessenger
  private var host: AnyObject?
  private init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }

  public static func register(with registrar: FlutterPluginRegistrar) {
    #if os(iOS)
      let messenger = registrar.messenger()
    #else
      let messenger = registrar.messenger
    #endif
    let plugin = ImagePlaygroundPlugin(messenger: messenger)
    ImagePlaygroundPlatformApiSetup.setUp(binaryMessenger: messenger, api: PlatformApi())
    #if canImport(ImagePlayground)
      if #available(iOS 18.1, macOS 15.1, *) {
        // Flutter registration is on the main thread, as are all UI operations.
        MainActor.assumeIsolated {
          let host = ImagePlaygroundHostApiImpl { [weak registrar] in registrar?.viewController }
          plugin.host = host
          ImagePlaygroundHostApiSetup.setUp(binaryMessenger: messenger, api: host)
        }
      }
    #endif
    registrar.publish(plugin)
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    ImagePlaygroundPlatformApiSetup.setUp(binaryMessenger: messenger, api: nil)
    ImagePlaygroundHostApiSetup.setUp(binaryMessenger: messenger, api: nil)
    #if canImport(ImagePlayground)
      if #available(iOS 18.1, macOS 15.1, *), let host = host as? ImagePlaygroundHostApiImpl {
        Task { @MainActor in host.shutdown() }
      }
    #endif
    host = nil
  }
}

private final class PlatformApi: ImagePlaygroundPlatformApi {
  func isSupported() throws -> Bool {
    #if canImport(ImagePlayground)
      if #available(iOS 18.1, macOS 15.1, *) { return true }
    #endif
    return false
  }
  func capabilities() throws -> CapabilitiesMessage {
    let value = CapabilitiesMessage(isSupported: false, isAvailable: false,
      supportsStyles: false, supportsOptions: false, supportsVersion27Options: false, styles: [])
    #if canImport(ImagePlayground)
      if #available(iOS 18.1, macOS 15.1, *) {
        var result = value
        result.isSupported = true
        result.isAvailable = ImagePlaygroundViewController.isAvailable
        if #available(iOS 18.4, macOS 15.4, *) {
          result.supportsStyles = true
          result.styles = ImagePlaygroundStyle.all.compactMap(PreparedConfiguration.message)
        }
        if #available(iOS 26.4, macOS 26.4, *) { result.supportsOptions = true }
        if #available(iOS 27.0, macOS 27.0, *) { result.supportsVersion27Options = true }
        return result
      }
    #endif
    return value
  }
}
