#if canImport(CoreAI)
  import CoreAI
  import CoreVideo
  import Foundation

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Implements `CoreAIHostApi` on top of Core AI.
  ///
  /// Async methods are nonisolated, so their bodies run off the platform
  /// thread even though Pigeon starts them from a main-actor task.
  @available(iOS 27.0, macOS 27.0, *)
  final class CoreAIHostApiImpl: CoreAIHostApi, @unchecked Sendable {
    let registry = HandleRegistry()

    // MARK: - Device

    func deviceArchitectureName() throws -> String {
      AIModel.deviceArchitectureName
    }

    func availableComputeUnitKinds() throws -> [ComputeUnitKindMessage] {
      ComputeUnitKind.availableKinds.compactMap(ComputeUnitKindMessage.init)
        .sorted { $0.rawValue < $1.rawValue }
    }

    func describeSpecializationOptions(options: SpecializationOptionsMessage) throws
      -> SpecializationInfoMessage
    {
      try translatingErrors { SpecializationInfoMessage(try options.coreAI()) }
    }

    // MARK: - Models

    func loadModel(path: String, options: SpecializationOptionsMessage) async throws
      -> ModelInfoMessage
    {
      try await translatingErrors {
        let model = try await AIModel(
          contentsOf: try existingFileURL(path), options: try options.coreAI())
        return register(model)
      }
    }

    func specializeModel(
      path: String, options: SpecializationOptionsMessage, cache: ModelCacheMessage,
      policy: CachePolicyMessage
    ) async throws -> ModelInfoMessage {
      try await translatingErrors {
        let model = try await AIModel.specialize(
          contentsOf: try existingFileURL(path), options: try options.coreAI(),
          cache: try cache.coreAI(), cachePolicy: policy.coreAI)
        return register(model)
      }
    }

    func cachedModel(
      path: String, options: SpecializationOptionsMessage, cache: ModelCacheMessage
    ) async throws -> ModelInfoMessage? {
      try translatingErrors {
        try cache.coreAI().model(for: modelURL(path), options: try options.coreAI())
          .map(register)
      }
    }

    func modelFromBookmark(bookmark: FlutterStandardTypedData) async throws -> ModelInfoMessage? {
      try translatingErrors { try AIModel(resolvingBookmark: bookmark.data).map(register) }
    }

    func modelBookmarkData(modelHandle: Int64) throws -> FlutterStandardTypedData {
      FlutterStandardTypedData(bytes: try registry.model(modelHandle).bookmarkData)
    }

    func functionDescriptor(modelHandle: Int64, functionName: String) throws
      -> FunctionDescriptorMessage?
    {
      try translatingErrors {
        try registry.model(modelHandle).functionDescriptor(for: functionName)
          .map(FunctionDescriptorMessage.init)
      }
    }

    func loadFunction(modelHandle: Int64, functionName: String) async throws
      -> FunctionInfoMessage?
    {
      try translatingErrors {
        guard let function = try registry.model(modelHandle).loadFunction(named: functionName)
        else { return nil }
        let descriptor = try FunctionDescriptorMessage(function.descriptor)
        return FunctionInfoMessage(
          handle: registry.insert(.function(function)), descriptor: descriptor)
      }
    }

    func resolveDynamicDimensions(
      ownerHandle: Int64, functionName: String, role: ValueRoleMessage, valueName: String,
      shape: [Int64]
    ) throws -> NDArrayDescriptorMessage {
      try translatingErrors {
        let descriptor = try argumentDescriptor(ownerHandle, functionName, role, valueName)
        guard case .ndArray(let array) = descriptor else {
          throw Errors.invalidArgument("'\(valueName)' is an image, not an NDArray.")
        }
        return try NDArrayDescriptorMessage(array.resolving(shape: shape))
      }
    }

    private func register(_ model: AIModel) -> ModelInfoMessage {
      ModelInfoMessage(
        handle: registry.insert(.model(model)), functionNames: model.functionNames)
    }

    /// The descriptor of a function argument. [ownerHandle] is a function
    /// handle, or a model handle together with [functionName].
    private func argumentDescriptor(
      _ ownerHandle: Int64, _ functionName: String, _ role: ValueRoleMessage, _ name: String
    ) throws -> InferenceValue.Descriptor {
      if let function = try? registry.function(ownerHandle) {
        return try function.descriptor.descriptor(role: role, name: name)
      }
      guard
        let function = try registry.model(ownerHandle).functionDescriptor(for: functionName)
      else {
        throw Errors.notFound("The model has no function named '\(functionName)'.")
      }
      return try function.descriptor(role: role, name: name)
    }

    /// Cache lookups and deletions key on the model URL; the file itself may
    /// already be gone, so do not require it to exist.
    private func modelURL(_ path: String) -> URL {
      URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    // MARK: - Cache

    func deleteCacheEntry(
      path: String, options: SpecializationOptionsMessage, cache: ModelCacheMessage
    ) async throws {
      try translatingErrors {
        try cache.coreAI().deleteEntry(for: modelURL(path), options: try options.coreAI())
      }
    }

    func deleteCacheEntries(path: String, cache: ModelCacheMessage) async throws {
      try translatingErrors { try cache.coreAI().deleteEntries(for: modelURL(path)) }
    }

    func deleteAllCacheEntries(cache: ModelCacheMessage) async throws {
      try translatingErrors { try cache.coreAI().deleteAll() }
    }

    func deleteCacheEntryForBookmark(bookmark: FlutterStandardTypedData) async throws {
      try translatingErrors { try AIModelCache.deleteEntry(referencedBy: bookmark.data) }
    }

    func isCacheAvailable(cache: ModelCacheMessage) throws -> Bool {
      guard let group = cache.appGroupIdentifier else { return true }
      return AIModelCache(appGroup: group) != nil
    }

    // MARK: - Inference

    func run(request: RunRequestMessage) async throws -> RunResultMessage {
      try await translatingErrors {
        let function = try registry.function(request.functionHandle)
        var readLeases: [NativeValue] = []
        var writeLeases: [NativeValue] = []
        defer {
          readLeases.forEach { $0.releaseRead() }
          writeLeases.forEach { $0.releaseWrite() }
        }

        var inputs: [(String, RunInput)] = []
        for (name, message) in request.inputs.sorted(by: { $0.key < $1.key }) {
          if let reference = message as? NativeValueRefMessage {
            let value = try registry.value(reference.handle)
            try await value.acquireRead(handle: reference.handle)
            readLeases.append(value)
            inputs.append((name, try runInput(value, name: name)))
          } else {
            inputs.append((name, try runInput(message, name: name)))
          }
        }

        var states: [(String, NativeValue)] = []
        for (name, handle) in request.states.sorted(by: { $0.key < $1.key }) {
          let value = try registry.value(handle)
          try value.acquireWrite(handle: handle)
          writeLeases.append(value)
          try await value.resolve()
          states.append((name, value))
        }

        var outputViews: [(String, NativeValue)] = []
        for (name, handle) in request.outputViews.sorted(by: { $0.key < $1.key }) {
          let value = try registry.value(handle)
          try value.acquireWrite(handle: handle)
          writeLeases.append(value)
          try await value.resolve()
          outputViews.append((name, value))
        }

        var outputs = try await InferenceRunner(function: function).run(
          inputs: inputs, states: states, outputViews: outputViews)

        let retained = Set(request.retainedOutputs)
        var result: [String: ValueMessage] = [:]
        for name in Array(outputs.names) {
          guard let value = outputs.remove(name) else { continue }
          let retain = request.retainAllOutputs || retained.contains(name)
          switch value.kind {
          case .ndArray:
            guard let array = value.ndArray else { continue }
            result[name] =
              retain
              ? NativeValueRefMessage(handle: registry.insert(NativeValue(array)))
              : try NDArrayBridge.message(array)
          case .image:
            guard let mutable = value.pixelBuffer else { continue }
            let buffer: CVPixelBuffer = mutable.withUnsafeBuffer { $0 }
            result[name] =
              retain
              ? NativeValueRefMessage(handle: registry.insert(NativeValue(buffer)))
              : PixelBufferBridge.message(buffer)
          @unknown default:
            continue
          }
        }
        return RunResultMessage(outputs: result)
      }
    }

    private func runInput(_ message: ValueMessage, name: String) throws -> RunInput {
      switch message {
      case let array as NDArrayMessage:
        return .ndArray(try NDArrayBridge.make(array))
      case let buffer as PixelBufferMessage:
        return .pixelBuffer(CVReadOnlyPixelBuffer(unsafeBuffer: try PixelBufferBridge.make(buffer)))
      default:
        throw Errors.invalidArgument("Unsupported value for input '\(name)'.")
      }
    }

    /// A run input backed by a read-leased native value.
    private func runInput(_ value: NativeValue, name: String) throws -> RunInput {
      switch value.content {
      case .ndArray:
        return .ndArray(value.ndArray!)
      case .pixelBuffer:
        return .pixelBuffer(CVReadOnlyPixelBuffer(unsafeBuffer: value.pixelBuffer!))
      case .asyncValue, .asyncMutable:
        throw Errors.invalidArgument("Native value for input '\(name)' is not resolved.")
      }
    }

    func encode(request: EncodeRequestMessage) async throws -> [String: Int64] {
      try await translatingErrors {
        let function = try registry.function(request.functionHandle)
        let stream = try registry.stream(request.streamHandle)
        var writeLeases: [NativeValue] = []
        defer { writeLeases.forEach { $0.releaseWrite() } }

        var inputs: [String: InferenceFunction.AsyncValue] = [:]
        for (name, message) in request.inputs {
          switch message {
          case let reference as NativeValueRefMessage:
            inputs[name] = try registry.value(reference.handle).asyncInput(
              handle: reference.handle)
          case let array as NDArrayMessage:
            inputs[name] = InferenceFunction.AsyncValue(try NDArrayBridge.make(array))
          case let buffer as PixelBufferMessage:
            inputs[name] = InferenceFunction.AsyncValue(
              CVReadOnlyPixelBuffer(unsafeBuffer: try PixelBufferBridge.make(buffer)))
          default:
            throw Errors.invalidArgument("Unsupported value for input '\(name)'.")
          }
        }

        func leaseMutable(_ handles: [String: Int64]) async throws -> [(String, NativeValue)] {
          var result: [(String, NativeValue)] = []
          for (name, handle) in handles.sorted(by: { $0.key < $1.key }) {
            let value = try registry.value(handle)
            try value.acquireWrite(handle: handle)
            writeLeases.append(value)
            try await value.makeAsyncMutable()
            result.append((name, value))
          }
          return result
        }
        let states = try await leaseMutable(request.states)
        let outputViews = try await leaseMutable(request.outputViews)

        let outputs = try InferenceRunner(function: function).encode(
          inputs: inputs, states: states, outputViews: outputViews, stream: stream)
        return outputs.mapValues { registry.insert(NativeValue($0)) }
      }
    }

    func createComputeStream() throws -> Int64 {
      registry.insert(.stream(ComputeStream()))
    }

    func computeStreamCompleted(streamHandle: Int64) async throws {
      let stream = try registry.stream(streamHandle)
      await stream.currentWorkCompleted()
    }

    // MARK: - Native values

    func createNDArray(array: NDArrayMessage) async throws -> Int64 {
      try translatingErrors { registry.insert(NativeValue(try NDArrayBridge.make(array))) }
    }

    func allocateNDArray(
      scalarType: ScalarTypeMessage, shape: [Int64], strides: [Int64]?,
      interleaveLayout: InterleaveLayoutMessage?
    ) async throws -> Int64 {
      try translatingErrors {
        let array = try NDArrayBridge.allocate(
          scalarType: scalarType, shape: shape, strides: strides,
          interleaveLayout: interleaveLayout)
        return registry.insert(NativeValue(array))
      }
    }

    func allocateForDescriptor(
      ownerHandle: Int64, functionName: String, role: ValueRoleMessage, valueName: String,
      shape: [Int64]?, width: Int64?, height: Int64?
    ) async throws -> Int64 {
      try translatingErrors {
        switch try argumentDescriptor(ownerHandle, functionName, role, valueName) {
        case .ndArray(var descriptor):
          if descriptor.hasDynamicShape {
            guard let shape else {
              throw Errors.invalidArgument(
                "'\(valueName)' has dynamic shape \(descriptor.shape); pass a concrete shape.")
            }
            descriptor = try descriptor.resolving(shape: shape)
          } else if let shape, shape != descriptor.shape.map(Int64.init) {
            throw Errors.invalidArgument(
              "'\(valueName)' has fixed shape \(descriptor.shape), not \(shape).")
          }
          return registry.insert(NativeValue(NDArrayBridge.allocate(descriptor)))
        case .image(let image):
          let buffer = try PixelBufferBridge.create(
            width: try resolveDimension(image.width, width, "width", valueName),
            height: try resolveDimension(image.height, height, "height", valueName),
            pixelFormatType: image.pixelFormatType)
          return registry.insert(NativeValue(buffer))
        @unknown default:
          throw Errors.invalidArgument("Unsupported descriptor for '\(valueName)'.")
        }
      }
    }

    private func resolveDimension(
      _ described: Int, _ requested: Int64?, _ label: String, _ valueName: String
    ) throws -> Int {
      if described >= 0 {
        if let requested, requested != described {
          throw Errors.invalidArgument(
            "'\(valueName)' has fixed \(label) \(described), not \(requested).")
        }
        return described
      }
      guard let requested else {
        throw Errors.invalidArgument("'\(valueName)' has a dynamic \(label); pass one.")
      }
      return Int(requested)
    }

    func createPixelBuffer(pixelBuffer: PixelBufferMessage) async throws -> Int64 {
      try translatingErrors { registry.insert(NativeValue(try PixelBufferBridge.make(pixelBuffer))) }
    }

    func createPixelBufferFromEncodedImage(
      encoded: FlutterStandardTypedData, pixelFormatType: Int64, width: Int64?, height: Int64?
    ) async throws -> Int64 {
      try translatingErrors {
        let buffer = try PixelBufferBridge.fromEncodedImage(
          encoded.data, pixelFormatType: OSType(truncatingIfNeeded: pixelFormatType),
          width: width.map(Int.init), height: height.map(Int.init))
        return registry.insert(NativeValue(buffer))
      }
    }

    func readValue(handle: Int64) async throws -> ValueMessage {
      try await translatingErrors {
        let value = try registry.value(handle)
        return try await value.withRead(handle: handle) {
          switch value.content {
          case .ndArray: return try NDArrayBridge.message(value.ndArray!)
          case .pixelBuffer: return PixelBufferBridge.message(value.pixelBuffer!)
          case .asyncValue, .asyncMutable:
            throw CoreAIPigeonError(.coreAIError, "Native value \(handle) did not resolve.")
          }
        }
      }
    }

    func encodePixelBuffer(handle: Int64, encoding: ImageEncodingMessage, quality: Double)
      async throws -> FlutterStandardTypedData
    {
      try await translatingErrors {
        let value = try registry.value(handle)
        return try await value.withRead(handle: handle) {
          guard value.content == .pixelBuffer, let buffer = value.pixelBuffer else {
            throw Errors.invalidArgument("Native value \(handle) is not a pixel buffer.")
          }
          return FlutterStandardTypedData(
            bytes: try PixelBufferBridge.encode(buffer, as: encoding, quality: quality))
        }
      }
    }

    func writeNDArray(handle: Int64, array message: NDArrayMessage) async throws {
      try await translatingErrors {
        let value = try registry.value(handle)
        try await value.withWrite(handle: handle) {
          try await value.resolve()
          guard value.content == .ndArray, var array = value.ndArray.take() else {
            throw Errors.invalidArgument("Native value \(handle) is not an NDArray.")
          }
          defer { value.store(array) }
          try checkLayout(of: message, matches: array)
          try NDArrayBridge.overwrite(&array, with: message.data.data)
        }
      }
    }

    /// Byte-level writes are only meaningful when both sides share a layout.
    private func checkLayout(of message: NDArrayMessage, matches array: NDArray) throws {
      let shape = array.shape.map(Int64.init)
      let strides =
        message.strides.isEmpty ? contiguousStrides(message.shape) : message.strides
      guard try ScalarTypeMessage(array.scalarType) == message.scalarType,
        message.shape == shape,
        strides == array.strides.map(Int64.init),
        message.interleaveLayout?.dimension == array.interleaveLayout.map({ Int64($0.dimension) }),
        message.interleaveLayout?.factor == array.interleaveLayout.map({ Int64($0.factor) })
      else {
        throw Errors.invalidArgument(
          "Layout mismatch: the native array is \(array.scalarType) \(array.shape) with "
            + "strides \(array.strides); the data is \(message.scalarType) \(message.shape) "
            + "with strides \(strides).")
      }
    }

    private func contiguousStrides(_ shape: [Int64]) -> [Int64] {
      var strides = [Int64](repeating: 1, count: shape.count)
      var stride: Int64 = 1
      for index in shape.indices.reversed() {
        strides[index] = stride
        stride *= max(shape[index], 1)
      }
      return strides
    }

    func zeroValue(handle: Int64) async throws {
      try await translatingErrors {
        let value = try registry.value(handle)
        try await value.withWrite(handle: handle) {
          try await value.resolve()
          switch value.content {
          case .ndArray:
            guard var array = value.ndArray.take() else { return }
            NDArrayBridge.zero(&array)
            value.store(array)
          case .pixelBuffer:
            PixelBufferBridge.zero(value.pixelBuffer!)
          case .asyncValue, .asyncMutable:
            break
          }
        }
      }
    }

    func copyValue(handle: Int64) async throws -> Int64 {
      try await translatingErrors {
        let value = try registry.value(handle)
        let copy: NativeValue = try await value.withRead(handle: handle) {
          switch value.content {
          case .ndArray: return NativeValue(try NDArrayBridge.copy(value.ndArray!))
          case .pixelBuffer: return NativeValue(try PixelBufferBridge.copy(value.pixelBuffer!))
          case .asyncValue, .asyncMutable:
            throw CoreAIPigeonError(.coreAIError, "Native value \(handle) did not resolve.")
          }
        }
        return registry.insert(copy)
      }
    }

    func describeValue(handle: Int64) async throws -> NativeValueInfoMessage {
      try translatingErrors { try registry.value(handle).describe(handle: handle) }
    }

    // MARK: - Handles

    func release(handle: Int64) async throws {
      registry.remove(handle)
    }

    func releaseAll() async throws -> Int64 {
      Int64(registry.removeAll())
    }

    func liveHandleCount() throws -> Int64 {
      Int64(registry.count)
    }

    // MARK: - Assets

    func isValidAsset(path: String) throws -> Bool {
      AIModelAsset.isValid(at: modelURL(path))
    }

    func assetMetadata(path: String) async throws -> AssetMetadataMessage {
      try translatingErrors { try AssetBridge.metadata(path: path) }
    }

    func assetSummary(path: String, includeStatistics: Bool) async throws -> AssetSummaryMessage? {
      try translatingErrors {
        try AssetBridge.summary(path: path, includeStatistics: includeStatistics)
      }
    }

    func updateAssetMetadata(path: String, update: AssetMetadataUpdateMessage) async throws {
      try translatingErrors { try AssetBridge.updateMetadata(path: path, update: update) }
    }

    func removeAssetDerivedArtifacts(path: String) async throws {
      try translatingErrors { try AssetBridge.removeDerivedArtifacts(path: path) }
    }
  }
#endif
