#if canImport(CoreML)
  import CoreML
  import Foundation

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Implements `CoreMLHostApi` on top of Core ML.
  ///
  /// Async methods are nonisolated, so their bodies run off the platform
  /// thread even though Pigeon starts them from a main-actor task.
  @available(iOS 18.0, macOS 15.0, *)
  final class CoreMLHostApiImpl: CoreMLHostApi, @unchecked Sendable {
    let registry = HandleRegistry()

    // MARK: - Compilation

    func compileModel(path: String, destinationPath: String?) async throws -> String {
      try await translatingErrors {
        let compiled = try await MLModel.compileModel(at: try existingFileURL(path))
        guard let destinationPath else { return compiled.path }
        let destination = URL(
          fileURLWithPath: (destinationPath as NSString).expandingTildeInPath)
        let manager = FileManager.default
        try manager.createDirectory(
          at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if manager.fileExists(atPath: destination.path) {
          try manager.removeItem(at: destination)
        }
        try manager.moveItem(at: compiled, to: destination)
        return destination.path
      }
    }

    // MARK: - Model assets

    func functionNames(compiledPath: String) async throws -> [String] {
      try await translatingErrors {
        let asset = try MLModelAsset(url: try existingFileURL(compiledPath))
        return try await asset.functionNames
      }
    }

    func assetModelDescription(compiledPath: String, functionName: String?) async throws
      -> ModelDescriptionMessage
    {
      try await translatingErrors {
        let asset = try MLModelAsset(url: try existingFileURL(compiledPath))
        let description: MLModelDescription
        if let functionName {
          description = try await asset.modelDescription(of: functionName)
        } else {
          description = try await asset.modelDescription
        }
        return DescriptionBridge.message(description)
      }
    }

    // MARK: - Models

    func loadModel(compiledPath: String, configuration: ModelConfigurationMessage) async throws
      -> ModelInfoMessage
    {
      try await translatingErrors {
        let model = try await MLModel.load(
          contentsOf: try existingFileURL(compiledPath),
          configuration: configuration.coreML())
        return ModelInfoMessage(
          handle: registry.insert(.model(model)),
          modelDescription: DescriptionBridge.message(model.modelDescription),
          configuration: ModelConfigurationMessage(model.configuration))
      }
    }

    // MARK: - Prediction

    func predict(request: PredictionRequestMessage) async throws -> PredictionResultMessage {
      try await translatingErrors {
        let model = try registry.model(request.modelHandle)
        let inputs = try featureProvider(request.inputs, model: model)
        let options = MLPredictionOptions()
        let prediction: any MLFeatureProvider
        if let stateHandle = request.stateHandle {
          let box = try registry.state(stateHandle)
          prediction = try await box.exclusively(handle: stateHandle) { state in
            try await model.prediction(from: inputs, using: state, options: options)
          }
        } else {
          prediction = try await model.prediction(from: inputs, options: options)
        }
        return PredictionResultMessage(outputs: try messages(of: prediction))
      }
    }

    func predictBatch(request: BatchPredictionRequestMessage) async throws
      -> BatchPredictionResultMessage
    {
      try translatingErrors {
        let model = try registry.model(request.modelHandle)
        let providers = try request.inputs.map {
          try featureProvider($0.features, model: model) as any MLFeatureProvider
        }
        let batch = try model.predictions(
          from: MLArrayBatchProvider(array: providers), options: MLPredictionOptions())
        var outputs: [FeatureMapMessage] = []
        outputs.reserveCapacity(batch.count)
        for index in 0..<batch.count {
          outputs.append(
            FeatureMapMessage(features: try messages(of: batch.features(at: index))))
        }
        return BatchPredictionResultMessage(outputs: outputs)
      }
    }

    private func featureProvider(_ inputs: [String: FeatureValueMessage], model: MLModel) throws
      -> MLDictionaryFeatureProvider
    {
      let descriptions = model.modelDescription.inputDescriptionsByName
      var values: [String: MLFeatureValue] = [:]
      for (name, message) in inputs {
        values[name] = try FeatureValueBridge.featureValue(
          message, name: name, description: descriptions[name])
      }
      return try MLDictionaryFeatureProvider(dictionary: values)
    }

    private func messages(of provider: any MLFeatureProvider) throws
      -> [String: FeatureValueMessage]
    {
      var result: [String: FeatureValueMessage] = [:]
      for name in provider.featureNames {
        guard let value = provider.featureValue(for: name), value.type != .state else { continue }
        result[name] = try FeatureValueBridge.message(value, name: name)
      }
      return result
    }

    // MARK: - State

    func makeState(modelHandle: Int64) throws -> Int64 {
      let model = try registry.model(modelHandle)
      return registry.insert(.state(StateBox(model.makeState(), model: model)))
    }

    func readState(stateHandle: Int64, stateName: String) async throws -> MultiArrayMessage {
      try await translatingErrors {
        let box = try registry.state(stateHandle)
        try checkState(box, stateName)
        return try await box.exclusively(handle: stateHandle) { state in
          try state.withMultiArray(for: stateName) { try MultiArrayBridge.message($0) }
        }
      }
    }

    func writeState(stateHandle: Int64, stateName: String, array: MultiArrayMessage) async throws {
      try await translatingErrors {
        let box = try registry.state(stateHandle)
        try checkState(box, stateName)
        try await box.exclusively(handle: stateHandle) { state in
          try state.withMultiArray(for: stateName) {
            try MultiArrayBridge.overwrite($0, with: array)
          }
        }
      }
    }

    /// Core ML traps on an unknown state name, so check it first.
    private func checkState(_ box: StateBox, _ stateName: String) throws {
      let states = box.model.modelDescription.stateDescriptionsByName
      guard states[stateName] != nil else {
        throw Errors.notFound(
          "The model has no state named '\(stateName)'. States: "
            + "\(states.keys.sorted()).")
      }
    }

    // MARK: - Compute devices

    func availableComputeDevices() throws -> [ComputeDeviceMessage] {
      MLModel.availableComputeDevices.map(ComputeDeviceMessage.init)
    }

    func allComputeDevices() throws -> [ComputeDeviceMessage] {
      MLComputeDevice.allComputeDevices.map(ComputeDeviceMessage.init)
    }

    // MARK: - Images

    func encodeImage(
      image: PixelBufferMessage, encoding: ImageEncodingMessage, quality: Double
    ) async throws -> FlutterStandardTypedData {
      try translatingErrors {
        let buffer = try PixelBufferBridge.make(image)
        return FlutterStandardTypedData(
          bytes: try PixelBufferBridge.encode(buffer, as: encoding, quality: quality))
      }
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
  }
#endif
