#if canImport(Translation)
  import Foundation
  import Translation

  /// Owns the native objects handed to Dart, keyed by opaque handles.
  @available(iOS 18.0, macOS 15.0, *)
  final class HandleRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var nextHandle: Int64 = 1
    private var sessions: [Int64: TranslationSession] = [:]

    func insert(_ session: TranslationSession) -> Int64 {
      lock.lock()
      defer { lock.unlock() }
      let handle = nextHandle
      nextHandle += 1
      sessions[handle] = session
      return handle
    }

    func session(_ handle: Int64) throws -> TranslationSession {
      lock.lock()
      let session = sessions[handle]
      lock.unlock()
      guard let session else {
        throw Errors.invalidHandle(handle, expected: "TranslationSession")
      }
      return session
    }

    func remove(_ handle: Int64) {
      lock.lock()
      defer { lock.unlock() }
      sessions.removeValue(forKey: handle)
    }

    func removeAll() -> Int {
      lock.lock()
      defer { lock.unlock() }
      let count = sessions.count
      sessions.removeAll()
      return count
    }

    var count: Int {
      lock.lock()
      defer { lock.unlock() }
      return sessions.count
    }
  }

  /// Tracks in-flight streaming requests so Dart can cancel them.
  final class RequestRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Int64: Task<Void, Never>] = [:]

    /// Creates and records a task under the lock, so a task that finishes
    /// immediately cannot call `finish` before it is recorded.
    func start(_ requestId: Int64, _ makeTask: () -> Task<Void, Never>) {
      lock.lock()
      defer { lock.unlock() }
      tasks[requestId] = makeTask()
    }

    func finish(_ requestId: Int64) {
      lock.lock()
      defer { lock.unlock() }
      tasks.removeValue(forKey: requestId)
    }

    func cancel(_ requestId: Int64) {
      lock.lock()
      let task = tasks.removeValue(forKey: requestId)
      lock.unlock()
      task?.cancel()
    }

    func cancelAll() {
      lock.lock()
      let all = Array(tasks.values)
      tasks.removeAll()
      lock.unlock()
      all.forEach { $0.cancel() }
    }
  }
#endif
