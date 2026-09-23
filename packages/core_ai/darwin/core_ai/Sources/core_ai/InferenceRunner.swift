#if canImport(CoreAI)
  import CoreAI
  import CoreVideo
  import Foundation

  /// A concrete input for `InferenceFunction.run`.
  @available(iOS 27.0, macOS 27.0, *)
  enum RunInput {
    case ndArray(NDArray)
    case pixelBuffer(CVReadOnlyPixelBuffer)
  }

  /// Bridges a dynamic set of named inputs, states and output views onto Core
  /// AI's `~Escapable` argument collections.
  ///
  /// `Inputs` and `MutableViews` borrow each value for their whole lifetime,
  /// so every value must be a local binding that outlives the call. Each
  /// recursion level binds one value, inserts it, and recurses; the innermost
  /// level makes the call. States and output views are taken out of their
  /// `NativeValue` for the call and written back on every path.
  @available(iOS 27.0, macOS 27.0, *)
  struct InferenceRunner {
    typealias Inputs = InferenceFunction.Inputs
    typealias MutableViews = InferenceFunction.MutableViews
    typealias Outputs = InferenceFunction.Outputs
    typealias AsyncMutableViews = InferenceFunction.AsyncMutableViews
    typealias AsyncValue = InferenceFunction.AsyncValue

    let function: InferenceFunction

    // MARK: run

    /// `InferenceFunction.run(inputs:states:outputViews:)`. Callers must hold
    /// the writer lease of every state and output view, already resolved to
    /// concrete storage.
    func run(
      inputs: [(String, RunInput)],
      states: [(String, NativeValue)],
      outputViews: [(String, NativeValue)]
    ) async throws -> Outputs {
      try await bindInputs(
        ArraySlice(inputs), Inputs(), states: ArraySlice(states),
        outputViews: ArraySlice(outputViews))
    }

    private func bindInputs(
      _ rest: ArraySlice<(String, RunInput)>,
      _ inputs: Inputs,
      states: ArraySlice<(String, NativeValue)>,
      outputViews: ArraySlice<(String, NativeValue)>
    ) async throws -> Outputs {
      guard let (name, value) = rest.first else {
        return try await bindStates(
          states, MutableViews(), inputs: inputs, outputViews: outputViews)
      }
      var next = inputs
      switch value {
      case .ndArray(let array):
        next.insert(array, for: name)
        return try await bindInputs(
          rest.dropFirst(), next, states: states, outputViews: outputViews)
      case .pixelBuffer(let buffer):
        next.insert(buffer, for: name)
        return try await bindInputs(
          rest.dropFirst(), next, states: states, outputViews: outputViews)
      }
    }

    private func bindStates(
      _ rest: ArraySlice<(String, NativeValue)>,
      _ views: consuming MutableViews,
      inputs: Inputs,
      outputViews: ArraySlice<(String, NativeValue)>
    ) async throws -> Outputs {
      guard let (name, value) = rest.first else {
        return try await bindOutputViews(
          outputViews, MutableViews(), inputs: inputs, states: views)
      }
      switch value.content {
      case .ndArray:
        // Take the array out so the view holds the only reference and Core AI
        // writes into this storage rather than a copy.
        guard var array = value.ndArray.take() else { throw emptyValue(name) }
        views.insert(&array, for: name)
        do {
          let outputs = try await bindStates(
            rest.dropFirst(), views, inputs: inputs, outputViews: outputViews)
          value.store(array)
          return outputs
        } catch {
          value.store(array)
          throw error
        }
      case .pixelBuffer:
        guard let buffer = value.pixelBuffer else { throw emptyValue(name) }
        var mutable = CVMutablePixelBuffer(unsafeBuffer: buffer)
        views.insert(&mutable, for: name)
        return try await bindStates(
          rest.dropFirst(), views, inputs: inputs, outputViews: outputViews)
      case .asyncValue, .asyncMutable:
        throw unresolved(name)
      }
    }

    private func bindOutputViews(
      _ rest: ArraySlice<(String, NativeValue)>,
      _ views: consuming MutableViews,
      inputs: Inputs,
      states: consuming MutableViews
    ) async throws -> Outputs {
      guard let (name, value) = rest.first else {
        return try await function.run(inputs: inputs, states: states, outputViews: views)
      }
      switch value.content {
      case .ndArray:
        guard var array = value.ndArray.take() else { throw emptyValue(name) }
        views.insert(&array, for: name)
        do {
          let outputs = try await bindOutputViews(
            rest.dropFirst(), views, inputs: inputs, states: states)
          value.store(array)
          return outputs
        } catch {
          value.store(array)
          throw error
        }
      case .pixelBuffer:
        guard let buffer = value.pixelBuffer else { throw emptyValue(name) }
        var mutable = CVMutablePixelBuffer(unsafeBuffer: buffer)
        views.insert(&mutable, for: name)
        return try await bindOutputViews(
          rest.dropFirst(), views, inputs: inputs, states: states)
      case .asyncValue, .asyncMutable:
        throw unresolved(name)
      }
    }

    // MARK: encode

    /// `InferenceFunction.encode(inputs:states:outputViews:to:)`. Callers must
    /// hold the writer lease of every state and output view, already
    /// converted with `NativeValue.makeAsyncMutable()`.
    func encode(
      inputs: [String: AsyncValue],
      states: [(String, NativeValue)],
      outputViews: [(String, NativeValue)],
      stream: ComputeStream
    ) throws -> [String: AsyncValue] {
      try bindAsyncStates(
        ArraySlice(states), AsyncMutableViews(), inputs: inputs,
        outputViews: ArraySlice(outputViews), stream: stream)
    }

    private func bindAsyncStates(
      _ rest: ArraySlice<(String, NativeValue)>,
      _ views: consuming AsyncMutableViews,
      inputs: [String: AsyncValue],
      outputViews: ArraySlice<(String, NativeValue)>,
      stream: ComputeStream
    ) throws -> [String: AsyncValue] {
      guard let (name, value) = rest.first else {
        return try bindAsyncOutputViews(
          outputViews, AsyncMutableViews(), inputs: inputs, states: views, stream: stream)
      }
      guard var mutable = value.asyncMutable.take() else { throw unresolved(name) }
      views.insert(&mutable, for: name)
      let result: Result<[String: AsyncValue], any Error>
      do {
        result = .success(
          try bindAsyncStates(
            rest.dropFirst(), views, inputs: inputs, outputViews: outputViews, stream: stream))
      } catch {
        result = .failure(error)
      }
      value.asyncMutable = consume mutable
      return try result.get()
    }

    private func bindAsyncOutputViews(
      _ rest: ArraySlice<(String, NativeValue)>,
      _ views: consuming AsyncMutableViews,
      inputs: [String: AsyncValue],
      states: consuming AsyncMutableViews,
      stream: ComputeStream
    ) throws -> [String: AsyncValue] {
      guard let (name, value) = rest.first else {
        return try function.encode(
          inputs: inputs, states: states, outputViews: views, to: stream)
      }
      guard var mutable = value.asyncMutable.take() else { throw unresolved(name) }
      views.insert(&mutable, for: name)
      let result: Result<[String: AsyncValue], any Error>
      do {
        result = .success(
          try bindAsyncOutputViews(
            rest.dropFirst(), views, inputs: inputs, states: states, stream: stream))
      } catch {
        result = .failure(error)
      }
      value.asyncMutable = consume mutable
      return try result.get()
    }

    // MARK: Errors

    private func emptyValue(_ name: String) -> CoreAIPigeonError {
      CoreAIPigeonError(.coreAIError, "Native value for '\(name)' has no storage.")
    }

    private func unresolved(_ name: String) -> CoreAIPigeonError {
      CoreAIPigeonError(
        .coreAIError, "Native value for '\(name)' is not in the expected storage state.")
    }
  }
#endif
