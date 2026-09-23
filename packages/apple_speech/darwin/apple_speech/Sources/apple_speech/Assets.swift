#if canImport(Speech)
  import Foundation
  import Speech

  /// `AssetInventory` downloads, cancellable by request id.
  @available(iOS 26.0, macOS 26.0, *)
  final class AssetInstallRun: ActiveRequest, @unchecked Sendable {
    private let state = Mutex<(task: Task<Void, Error>?, progress: Progress?, cancelled: Bool)>(
      (nil, nil, false))

    func finishInput() {}

    func cancel() {
      let (task, progress) = state.withLock { state -> (Task<Void, Error>?, Progress?) in
        state.cancelled = true
        return (state.task, state.progress)
      }
      task?.cancel()
      progress?.cancel()
    }

    /// Downloads the assets for [modules]. Returns false when nothing was
    /// needed.
    func install(
      requestId: Int64, modules: [any SpeechModule], callback: CallbackBox
    ) async throws -> Bool {
      if state.withLock({ $0.cancelled }) { throw CancellationError() }
      guard let request = try await AssetInventory.assetInstallationRequest(supporting: modules)
      else { return false }
      let box = UncheckedBox(request)
      let progress = request.progress
      let task = Task<Void, Error> {
        let poller = Task {
          var last = -1.0
          while !Task.isCancelled {
            let fraction = progress.fractionCompleted
            if fraction != last {
              last = fraction
              try? await callback.api.onInstallProgress(
                requestId: requestId, fractionCompleted: fraction)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
          }
        }
        defer { poller.cancel() }
        try await box.value.downloadAndInstall()
      }
      let cancelledEarly = state.withLock { state -> Bool in
        state.task = task
        state.progress = progress
        return state.cancelled
      }
      if cancelledEarly { cancel() }
      try await task.value
      if state.withLock({ $0.cancelled }) { throw CancellationError() }
      try? await callback.api.onInstallProgress(requestId: requestId, fractionCompleted: 1)
      return true
    }
  }
#endif
