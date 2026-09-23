import Foundation

/// An in-flight recognition, analysis or asset download that Dart can end.
protocol ActiveRequest: AnyObject {
  /// Ends live input (the microphone) so the results can be finalized.
  func finishInput()

  /// Stops the request. No further events are sent for it.
  func cancel()
}

/// A tiny lock helper that works on every deployment target.
final class Mutex<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Value

  init(_ value: Value) { self.value = value }

  func withLock<R>(_ body: (inout Value) throws -> R) rethrows -> R {
    lock.lock()
    defer { lock.unlock() }
    return try body(&value)
  }

  var current: Value { withLock { $0 } }
}

/// Reserves an ID before asynchronous preparation; forwards early cancellation.
final class PendingRequest: ActiveRequest, @unchecked Sendable {
  private let state = Mutex<(run: ActiveRequest?, cancelled: Bool, finished: Bool)>(
    (nil, false, false))

  func attach(_ run: ActiveRequest) throws {
    let flags = state.withLock { state -> (Bool, Bool) in
      state.run = run
      return (state.cancelled, state.finished)
    }
    if flags.0 {
      run.cancel()
      throw CancellationError()
    }
    if flags.1 { run.finishInput() }
  }

  func finishInput() {
    let run = state.withLock { state -> ActiveRequest? in
      state.finished = true
      return state.run
    }
    run?.finishInput()
  }

  func cancel() {
    let run = state.withLock { state -> ActiveRequest? in
      state.cancelled = true
      return state.run
    }
    run?.cancel()
  }
}

/// Tracks in-flight requests by their Dart-chosen id.
final class RequestRegistry: @unchecked Sendable {
  private let requests = Mutex<[Int64: ActiveRequest]>([:])

  func register(_ requestId: Int64, _ request: ActiveRequest) throws {
    try requests.withLock { requests in
      guard requests[requestId] == nil else {
        throw Errors.invalidArgument("Request \(requestId) is already running.")
      }
      requests[requestId] = request
    }
  }

  /// Removes [requestId] if it still maps to [request].
  func remove(_ requestId: Int64, ifSame request: ActiveRequest) {
    requests.withLock { requests in
      if requests[requestId] === request { requests.removeValue(forKey: requestId) }
    }
  }

  func finishInput(_ requestId: Int64) {
    requests.withLock { $0[requestId] }?.finishInput()
  }

  func cancel(_ requestId: Int64) {
    requests.withLock { $0.removeValue(forKey: requestId) }?.cancel()
  }

  func cancelAll() -> Int {
    let all = requests.withLock { requests -> [ActiveRequest] in
      let values = Array(requests.values)
      requests.removeAll()
      return values
    }
    all.forEach { $0.cancel() }
    return all.count
  }

  var count: Int { requests.withLock { $0.count } }
}

/// Sends callback events to Dart one at a time, in the order they were
/// queued, from any thread.
final class EventPump: @unchecked Sendable {
  typealias Job = @Sendable (AppleSpeechCallbackApiProtocol) async -> Void

  private let continuation: AsyncStream<Job>.Continuation

  init(api: AppleSpeechCallbackApiProtocol) {
    var captured: AsyncStream<Job>.Continuation!
    let stream = AsyncStream<Job> { captured = $0 }
    continuation = captured
    let box = CallbackBox(api)
    Task {
      for await job in stream { await job(box.api) }
    }
  }

  deinit { continuation.finish() }

  func send(_ job: @escaping Job) { continuation.yield(job) }
}

/// Makes the callback API sendable across tasks.
final class CallbackBox: @unchecked Sendable {
  let api: AppleSpeechCallbackApiProtocol

  init(_ api: AppleSpeechCallbackApiProtocol) { self.api = api }
}
