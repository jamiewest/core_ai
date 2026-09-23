#if canImport(ImagePlayground)
  import Foundation
  import ImagePlayground
  #if os(iOS)
    import UIKit
    typealias PlaygroundPresenter = UIViewController
  #else
    import AppKit
    typealias PlaygroundPresenter = NSViewController
  #endif

  @available(iOS 18.1, macOS 15.1, *)
  @MainActor
  final class PlaygroundSession: NSObject, ImagePlaygroundViewController.Delegate {
    let controller = ImagePlaygroundViewController()
    private weak var presenter: PlaygroundPresenter?
    private var continuation: CheckedContinuation<ResultMessage?, Error>?
    private var closed = false
    private var started = false
    private var readingResult = false
    private var observers: [NSObjectProtocol] = []
    var isPresenting: Bool { continuation != nil }

    init(configuration: PreparedConfiguration) throws {
      super.init()
      try configuration.apply(to: controller)
      controller.delegate = self
    }

    func present(from presenter: PlaygroundPresenter) async throws -> ResultMessage? {
      guard !started && !closed else {
        throw ImagePlaygroundPigeonError("invalid_state", "Each session can be presented once. Create another session.")
      }
      self.presenter = presenter
      started = true
      return try await withCheckedThrowingContinuation { continuation in
        self.continuation = continuation
        #if os(iOS)
          controller.modalPresentationStyle = .formSheet
          presenter.present(controller, animated: false)
          controller.presentationController?.delegate = self
        #else
          if let window = presenter.view.window {
            for name in [NSWindow.didEndSheetNotification, NSWindow.willCloseNotification] {
              observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.finish(.success(nil)) }
              })
            }
          }
          presenter.presentAsSheet(controller)
        #endif
      }
    }

    func cancel() { finish(.success(nil)) }

    private func finish(_ result: Result<ResultMessage?, Error>) {
      guard !closed else { return }
      closed = true
      observers.forEach(NotificationCenter.default.removeObserver)
      observers.removeAll()
      let completion = continuation
      continuation = nil
      controller.delegate = nil
      #if os(iOS)
        if controller.presentingViewController != nil {
          controller.dismiss(animated: false) { completion?.resume(with: result) }
        } else { completion?.resume(with: result) }
      #else
        if presenter?.presentedViewControllers?.contains(controller) == true {
          presenter?.dismiss(controller)
        }
        completion?.resume(with: result)
      #endif
      presenter = nil
    }

    func imagePlaygroundViewControllerDidCancel(_ imagePlaygroundViewController: ImagePlaygroundViewController) {
      finish(.success(nil))
    }

    func imagePlaygroundViewController(_ imagePlaygroundViewController: ImagePlaygroundViewController, didCreateImageAt imageURL: URL) {
      guard !closed && !readingResult else { return }
      readingResult = true
      Task { [weak self] in
        do { self?.finish(.success(try await ImageBridge.result(url: imageURL))) }
        catch { self?.finish(.failure(Errors.translate(error))) }
      }
    }

    func imagePlaygroundViewController(_ imagePlaygroundViewController: ImagePlaygroundViewController, didCreate adaptiveImageGlyph: NSAdaptiveImageGlyph) {
      guard !closed && !readingResult else { return }
      readingResult = true
      let data = adaptiveImageGlyph.imageContent
      let identifier = adaptiveImageGlyph.contentIdentifier
      let description = adaptiveImageGlyph.contentDescription
      Task { [weak self] in
        do { self?.finish(.success(try await ImageBridge.glyph(data: data, identifier: identifier, description: description))) }
        catch { self?.finish(.failure(Errors.translate(error))) }
      }
    }

    func info() -> SessionInfoMessage {
      var styles: [StyleMessage] = []
      var selected: StyleMessage?
      if #available(iOS 18.4, macOS 15.4, *) {
        styles = controller.allowedGenerationStyles.compactMap(PreparedConfiguration.message)
        selected = PreparedConfiguration.message(controller.selectedGenerationStyle)
      }
      return SessionInfoMessage(conceptCount: Int64(controller.concepts.count),
        hasSourceImage: controller.sourceImage != nil, allowedStyles: styles, selectedStyle: selected,
        isPresenting: isPresenting)
    }
  }

  #if os(iOS)
    @available(iOS 18.1, *)
    extension PlaygroundSession: UIAdaptivePresentationControllerDelegate {
      func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(.success(nil))
      }
    }
  #endif
#endif
