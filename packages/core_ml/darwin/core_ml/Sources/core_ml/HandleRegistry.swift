#if canImport(CoreML)
  import CoreML
  import Foundation

  /// Owns every native object handed to Dart, keyed by an opaque handle.
  ///
  /// core_ml only keeps two kinds of native object alive: `MLModel`, which
  /// Core ML documents as safe to predict with from several threads, and
  /// `MLState`, which is not. Feature values always travel by value.
  @available(iOS 18.0, macOS 15.0, *)
  final class HandleRegistry: @unchecked Sendable {
    enum Entry {
      case model(MLModel)
      case state(StateBox)
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

    func model(_ handle: Int64) throws -> MLModel {
      guard case .model(let model) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "MLModel")
      }
      return model
    }

    func state(_ handle: Int64) throws -> StateBox {
      guard case .state(let state) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "MLState")
      }
      return state
    }

    func remove(_ handle: Int64) {
      _ = lock.withLock { entries.removeValue(forKey: handle) }
    }

    /// Removes every entry and returns how many there were.
    func removeAll() -> Int {
      lock.withLock {
        let count = entries.count
        entries.removeAll()
        return count
      }
    }

    var count: Int { lock.withLock { entries.count } }
  }

  /// An `MLState` plus the exclusion Core ML requires around it.
  ///
  /// `MLState`'s documentation is explicit: predictions that share a state
  /// must be serialized, and the state buffers must not be read or written
  /// while a prediction is in flight. Rather than block a cooperative thread
  /// across an `await`, overlapping use is rejected with `busy`.
  @available(iOS 18.0, macOS 15.0, *)
  final class StateBox: @unchecked Sendable {
    init(_ state: MLState, model: MLModel) {
      self.state = state
      self.model = model
    }

    let state: MLState

    /// Kept so a state handle stays valid even if the model handle is
    /// released first.
    let model: MLModel

    private let lock = NSLock()
    private var inUse = false

    /// Runs [body] with exclusive use of the state.
    func exclusively<T>(handle: Int64, _ body: (MLState) async throws -> T) async throws -> T {
      try lock.withLock {
        guard !inUse else { throw Errors.busy(handle) }
        inUse = true
      }
      defer { lock.withLock { inUse = false } }
      return try await body(state)
    }
  }
#endif
