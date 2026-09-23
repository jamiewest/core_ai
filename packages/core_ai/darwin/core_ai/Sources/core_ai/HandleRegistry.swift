#if canImport(CoreAI)
  import CoreAI
  import CoreVideo
  import Foundation

  /// Owns every native object handed to Dart, keyed by an opaque handle.
  @available(iOS 27.0, macOS 27.0, *)
  final class HandleRegistry: @unchecked Sendable {
    enum Entry {
      case model(AIModel)
      case function(InferenceFunction)
      case value(NativeValue)
      case stream(ComputeStream)
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

    func insert(_ value: NativeValue) -> Int64 { insert(.value(value)) }

    func model(_ handle: Int64) throws -> AIModel {
      guard case .model(let model) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "AIModel")
      }
      return model
    }

    func function(_ handle: Int64) throws -> InferenceFunction {
      guard case .function(let function) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "InferenceFunction")
      }
      return function
    }

    func value(_ handle: Int64) throws -> NativeValue {
      guard case .value(let value) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "native value")
      }
      return value
    }

    func stream(_ handle: Int64) throws -> ComputeStream {
      guard case .stream(let stream) = lock.withLock({ entries[handle] }) else {
        throw Errors.invalidHandle(handle, expected: "ComputeStream")
      }
      return stream
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

  /// A value that lives on the native side: an NDArray, a pixel buffer, or an
  /// in-flight compute-stream value.
  ///
  /// Access is leased: any number of concurrent readers, or one writer. The
  /// storage properties may only be touched while holding a lease; resolving
  /// or converting the storage requires the writer lease.
  @available(iOS 27.0, macOS 27.0, *)
  final class NativeValue: @unchecked Sendable {
    enum Content {
      case ndArray
      case pixelBuffer
      case asyncValue
      case asyncMutable

      var isConcrete: Bool { self == .ndArray || self == .pixelBuffer }
    }

    private(set) var content: Content
    var ndArray: NDArray?
    var pixelBuffer: CVPixelBuffer?
    var asyncValue: InferenceFunction.AsyncValue?
    var asyncMutable: InferenceFunction.AsyncMutableValue?
    /// Whether `asyncMutable` wraps a pixel buffer rather than an NDArray.
    private var asyncMutableIsImage = false

    private let lock = NSLock()
    private var readers = 0
    private var writer = false

    init(_ array: consuming NDArray) {
      content = .ndArray
      ndArray = array
    }

    init(_ buffer: CVPixelBuffer) {
      content = .pixelBuffer
      pixelBuffer = buffer
    }

    init(_ value: InferenceFunction.AsyncValue) {
      content = .asyncValue
      asyncValue = value
    }

    // MARK: Leasing

    /// Takes the exclusive (writer) lease.
    func acquireWrite(handle: Int64) throws {
      try lock.withLock {
        guard !writer, readers == 0 else { throw Errors.busy(handle) }
        writer = true
      }
    }

    func releaseWrite() {
      lock.withLock { writer = false }
    }

    /// Takes a shared (reader) lease, first resolving any in-flight async
    /// storage so readers always see a concrete NDArray or pixel buffer.
    func acquireRead(handle: Int64) async throws {
      let needsResolve: Bool = try lock.withLock {
        guard !writer else { throw Errors.busy(handle) }
        if content.isConcrete {
          readers += 1
          return false
        }
        guard readers == 0 else { throw Errors.busy(handle) }
        writer = true
        return true
      }
      guard needsResolve else { return }
      do {
        try await resolve()
      } catch {
        releaseWrite()
        throw error
      }
      lock.withLock {
        writer = false
        readers += 1
      }
    }

    func releaseRead() {
      lock.withLock { readers -= 1 }
    }

    /// Runs [body] under a reader lease.
    func withRead<T>(handle: Int64, _ body: () async throws -> T) async throws -> T {
      try await acquireRead(handle: handle)
      defer { releaseRead() }
      return try await body()
    }

    /// Runs [body] under the writer lease.
    func withWrite<T>(handle: Int64, _ body: () async throws -> T) async throws -> T {
      try acquireWrite(handle: handle)
      defer { releaseWrite() }
      return try await body()
    }

    // MARK: Storage transitions (writer lease required)

    /// Awaits any async storage, leaving a concrete NDArray or pixel buffer.
    func resolve() async throws {
      switch content {
      case .ndArray, .pixelBuffer:
        return
      case .asyncValue:
        guard let value = asyncValue else { return }
        switch value.kind {
        case .ndArray:
          guard let array = try await value.ndArray else {
            throw CoreAIPigeonError(.coreAIError, "Async value produced no NDArray.")
          }
          store(array)
        case .image:
          guard let buffer = try await value.pixelBuffer else {
            throw CoreAIPigeonError(.coreAIError, "Async value produced no pixel buffer.")
          }
          store(buffer.withUnsafeBuffer { $0 })
        @unknown default:
          throw CoreAIPigeonError(.coreAIError, "Unsupported async value kind \(value.kind).")
        }
      case .asyncMutable:
        guard let mutable = asyncMutable.take() else { return }
        if asyncMutableIsImage {
          guard let buffer = try await mutable.pixelBuffer else {
            throw CoreAIPigeonError(.coreAIError, "Async state produced no pixel buffer.")
          }
          store(buffer.withUnsafeBuffer { $0 })
        } else {
          guard let array = try await mutable.ndArray else {
            throw CoreAIPigeonError(.coreAIError, "Async state produced no NDArray.")
          }
          store(array)
        }
      }
    }

    /// Converts the storage into an `AsyncMutableValue`, for use as a state or
    /// output view of `InferenceFunction.encode`.
    func makeAsyncMutable() async throws {
      if content == .asyncValue { try await resolve() }
      switch content {
      case .ndArray:
        guard let array = ndArray.take() else { return }
        asyncMutable = InferenceFunction.AsyncMutableValue(array)
        asyncMutableIsImage = false
      case .pixelBuffer:
        guard let buffer = pixelBuffer.take() else { return }
        asyncMutable = InferenceFunction.AsyncMutableValue(
          CVMutablePixelBuffer(unsafeBuffer: buffer))
        asyncMutableIsImage = true
      case .asyncValue, .asyncMutable:
        return
      }
      content = .asyncMutable
    }

    /// An `AsyncValue` for use as an `encode` input.
    ///
    /// This does not wait for in-flight work, which is what lets consecutive
    /// encodes pipeline on a compute stream.
    func asyncInput(handle: Int64) throws -> InferenceFunction.AsyncValue {
      try lock.withLock {
        guard !writer else { throw Errors.busy(handle) }
        if content == .asyncMutable, readers > 0 { throw Errors.busy(handle) }
        return try makeAsyncValue()
      }
    }

    /// Layout metadata, without contents and without waiting for async work.
    func describe(handle: Int64) throws -> NativeValueInfoMessage {
      try lock.withLock {
        guard !writer else { throw Errors.busy(handle) }
        switch content {
        case .ndArray:
          return try NDArrayBridge.info(ndArray!, handle: handle)
        case .pixelBuffer:
          return PixelBufferBridge.info(pixelBuffer!, handle: handle)
        case .asyncValue:
          return NativeValueInfoMessage(handle: handle, kind: .asyncValue)
        case .asyncMutable:
          return NativeValueInfoMessage(handle: handle, kind: .asyncMutableValue)
        }
      }
    }

    /// An `AsyncValue` view of the storage.
    ///
    /// An async mutable value is converted in place into an immutable async
    /// value (it still completes when the pending write does).
    private func makeAsyncValue() throws -> InferenceFunction.AsyncValue {
      switch content {
      case .ndArray:
        return InferenceFunction.AsyncValue(ndArray!)
      case .pixelBuffer:
        return InferenceFunction.AsyncValue(CVReadOnlyPixelBuffer(unsafeBuffer: pixelBuffer!))
      case .asyncValue:
        return asyncValue!
      case .asyncMutable:
        guard let mutable = asyncMutable.take() else {
          throw CoreAIPigeonError(.coreAIError, "Async state is empty.")
        }
        let value = InferenceFunction.AsyncValue(mutable)
        asyncValue = value
        content = .asyncValue
        return value
      }
    }

    /// Replaces the storage with a concrete NDArray.
    func store(_ array: consuming NDArray) {
      asyncValue = nil
      pixelBuffer = nil
      ndArray = array
      content = .ndArray
    }

    /// Replaces the storage with a concrete pixel buffer.
    func store(_ buffer: CVPixelBuffer) {
      asyncValue = nil
      ndArray = nil
      pixelBuffer = buffer
      content = .pixelBuffer
    }
  }
#endif
