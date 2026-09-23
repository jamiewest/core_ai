#if canImport(ImagePlayground)
  import Foundation

  /// Actor-owned sessions with a lock-protected registry/count for channel queries.
  @available(iOS 18.1, macOS 15.1, *)
  final class HandleRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var next: Int64 = 1
    private var sessions: [Int64: PlaygroundSession] = [:]

    func insert(_ session: PlaygroundSession) -> Int64 {
      lock.lock(); defer { lock.unlock() }
      let handle = next
      next += 1
      sessions[handle] = session
      return handle
    }
    func session(_ handle: Int64) throws -> PlaygroundSession {
      lock.lock(); defer { lock.unlock() }
      guard let session = sessions[handle] else {
        throw ImagePlaygroundPigeonError("invalid_handle", "No session for handle \(handle).")
      }
      return session
    }
    func remove(_ handle: Int64) -> PlaygroundSession? {
      lock.lock(); defer { lock.unlock() }
      return sessions.removeValue(forKey: handle)
    }
    func removeAll() -> [PlaygroundSession] {
      lock.lock(); defer { lock.unlock() }
      let all = Array(sessions.values)
      sessions.removeAll()
      return all
    }
    var count: Int {
      lock.lock(); defer { lock.unlock() }
      return sessions.count
    }
  }
#endif
