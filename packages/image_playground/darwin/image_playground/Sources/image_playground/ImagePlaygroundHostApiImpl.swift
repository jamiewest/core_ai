#if canImport(ImagePlayground)
  import Foundation
  import ImagePlayground

  @available(iOS 18.1, macOS 15.1, *)
  @MainActor
  final class ImagePlaygroundHostApiImpl: ImagePlaygroundHostApi {
    nonisolated private let registry = HandleRegistry()
    private let presenter: @MainActor () -> PlaygroundPresenter?
    private var activeHandle: Int64?
    private var detached = false

    init(presenter: @escaping @MainActor () -> PlaygroundPresenter?) { self.presenter = presenter }

    func prepare(configuration: ConfigurationMessage) async throws -> Int64 {
      let configuration = try await PreparedConfiguration.decode(configuration)
      guard !detached else { throw Errors.unsupported("The Flutter engine detached.") }
      let session = try PlaygroundSession(configuration: configuration)
      return registry.insert(session)
    }

    func present(handle: Int64) async throws -> ResultMessage? {
      let session = try registry.session(handle)
      guard activeHandle == nil else {
        throw ImagePlaygroundPigeonError("busy", "Another Image Playground sheet is open.")
      }
      guard ImagePlaygroundViewController.isAvailable else {
        throw ImagePlaygroundPigeonError("unavailable", "Image Playground is unavailable on this device. Check Apple Intelligence settings and model availability.")
      }
      guard let presenter = presenter() else {
        throw ImagePlaygroundPigeonError("no_presenter", "The Flutter engine has no view controller.")
      }
      #if os(iOS)
        guard presenter.viewIfLoaded?.window != nil else {
          throw ImagePlaygroundPigeonError("no_presenter", "The Flutter view is not attached to a window.")
        }
        guard presenter.presentedViewController == nil else {
          throw ImagePlaygroundPigeonError("busy", "The Flutter view already presents a controller.")
        }
      #else
        guard presenter.view.window != nil else {
          throw ImagePlaygroundPigeonError("no_presenter", "The Flutter view is not attached to a window.")
        }
        guard presenter.presentedViewControllers?.isEmpty != false else {
          throw ImagePlaygroundPigeonError("busy", "The Flutter view already presents a controller.")
        }
      #endif
      activeHandle = handle
      defer { if activeHandle == handle { activeHandle = nil } }
      return try await session.present(from: presenter)
    }

    func info(handle: Int64) async throws -> SessionInfoMessage { try registry.session(handle).info() }
    func cancel(handle: Int64) async throws { try registry.session(handle).cancel() }
    func release(handle: Int64) async throws { registry.remove(handle)?.cancel() }
    func releaseAll() async throws -> Int64 {
      let sessions = registry.removeAll()
      sessions.forEach { $0.cancel() }
      return Int64(sessions.count)
    }
    nonisolated func liveHandleCount() throws -> Int64 { Int64(registry.count) }
    func shutdown() {
      detached = true
      registry.removeAll().forEach { $0.cancel() }
    }
  }
#endif
