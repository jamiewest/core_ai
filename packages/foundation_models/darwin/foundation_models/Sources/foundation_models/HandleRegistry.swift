#if canImport(FoundationModels)
  import FoundationModels
  import Foundation

  /// Owns the native objects handed to Dart, keyed by opaque handles.
  @available(iOS 26.0, macOS 26.0, *)
  final class HandleRegistry: @unchecked Sendable {
    enum Entry {
      case session(SessionBox)
      case adapter(SystemLanguageModel.Adapter)
    }

    private let lock = NSLock()
    private var nextHandle: Int64 = 1
    private var entries: [Int64: Entry] = [:]

    func insert(_ entry: Entry) -> Int64 {
      lock.withLock {
        let handle = nextHandle
        nextHandle += 1
        entries[handle] = entry
        return handle
      }
    }

    func session(_ handle: Int64) throws -> SessionBox {
      guard case .session(let box) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "LanguageModelSession")
      }
      return box
    }

    func adapter(_ handle: Int64) throws -> SystemLanguageModel.Adapter {
      guard case .adapter(let adapter) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "SystemLanguageModel.Adapter")
      }
      return adapter
    }

    func remove(_ handle: Int64) {
      _ = lock.withLock { entries.removeValue(forKey: handle) }
    }

    func removeAll() -> Int {
      lock.withLock {
        let count = entries.count
        entries.removeAll()
        return count
      }
    }

    var count: Int { lock.withLock { entries.count } }
  }

  /// A `LanguageModelSession` plus the tools Dart defined for it.
  @available(iOS 26.0, macOS 26.0, *)
  final class SessionBox: @unchecked Sendable {
    let session: LanguageModelSession
    /// Names of the tools implemented in Dart, for validation.
    let dartToolNames: Set<String>

    init(session: LanguageModelSession, dartToolNames: Set<String>) {
      self.session = session
      self.dartToolNames = dartToolNames
    }
  }

  /// Tracks in-flight requests so Dart can cancel them.
  final class RequestRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [Int64: Task<Void, Never>] = [:]

    func register(_ requestId: Int64, task: Task<Void, Never>) {
      lock.withLock { tasks[requestId] = task }
    }

    func finish(_ requestId: Int64) {
      _ = lock.withLock { tasks.removeValue(forKey: requestId) }
    }

    func cancel(_ requestId: Int64) {
      let task = lock.withLock { tasks.removeValue(forKey: requestId) }
      task?.cancel()
    }

    func cancelAll() {
      let all = lock.withLock { () -> [Task<Void, Never>] in
        let values = Array(tasks.values)
        tasks.removeAll()
        return values
      }
      all.forEach { $0.cancel() }
    }
  }
#endif
