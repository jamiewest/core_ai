#if canImport(CoreML)
  import CoreML
  import Foundation

  // MARK: - Multi-array data types

  @available(iOS 18.0, macOS 15.0, *)
  extension MultiArrayDataTypeMessage {
    /// The Core ML data type. `int8` needs iOS 26 / macOS 26.
    var coreML: MLMultiArrayDataType {
      get throws {
        switch self {
        case .float16: return .float16
        case .float32: return .float32
        case .float64: return .float64
        case .int32: return .int32
        case .int8:
          if #available(iOS 26.0, macOS 26.0, *) { return .int8 }
          throw Errors.unsupported(
            "Int8 multi arrays need iOS 26 / macOS 26 or later.")
        }
      }
    }

    /// The size of one element in bytes.
    var byteCount: Int {
      switch self {
      case .float16: return 2
      case .float32: return 4
      case .float64: return 8
      case .int32: return 4
      case .int8: return 1
      }
    }

    init(_ type: MLMultiArrayDataType) throws {
      if #available(iOS 26.0, macOS 26.0, *), type == .int8 {
        self = .int8
        return
      }
      switch type {
      case .float16: self = .float16
      case .float32: self = .float32
      case .float64: self = .float64
      case .int32: self = .int32
      default:
        throw Errors.unsupported("Unsupported MLMultiArrayDataType \(type.rawValue).")
      }
    }
  }

  // MARK: - Feature types

  @available(iOS 18.0, macOS 15.0, *)
  extension FeatureTypeMessage {
    var coreML: MLFeatureType {
      switch self {
      case .invalid: return .invalid
      case .int64: return .int64
      case .float64: return .double
      case .string: return .string
      case .image: return .image
      case .multiArray: return .multiArray
      case .dictionary: return .dictionary
      case .sequence: return .sequence
      case .state: return .state
      }
    }

    init(_ type: MLFeatureType) {
      switch type {
      case .int64: self = .int64
      case .double: self = .float64
      case .string: self = .string
      case .image: self = .image
      case .multiArray: self = .multiArray
      case .dictionary: self = .dictionary
      case .sequence: self = .sequence
      case .state: self = .state
      default: self = .invalid
      }
    }
  }

  // MARK: - Compute units

  @available(iOS 18.0, macOS 15.0, *)
  extension ComputeUnitsMessage {
    var coreML: MLComputeUnits {
      switch self {
      case .cpuOnly: return .cpuOnly
      case .cpuAndGpu: return .cpuAndGPU
      case .all: return .all
      case .cpuAndNeuralEngine: return .cpuAndNeuralEngine
      }
    }

    init(_ units: MLComputeUnits) {
      switch units {
      case .cpuOnly: self = .cpuOnly
      case .cpuAndGPU: self = .cpuAndGpu
      case .cpuAndNeuralEngine: self = .cpuAndNeuralEngine
      default: self = .all
      }
    }
  }

  // MARK: - Configuration

  @available(iOS 18.0, macOS 15.0, *)
  extension ModelConfigurationMessage {
    func coreML() -> MLModelConfiguration {
      let configuration = MLModelConfiguration()
      configuration.computeUnits = computeUnits.coreML
      configuration.allowLowPrecisionAccumulationOnGPU = allowLowPrecisionAccumulationOnGPU
      if let functionName { configuration.functionName = functionName }
      if let modelDisplayName { configuration.modelDisplayName = modelDisplayName }
      if reshapeFrequency != nil || specializationStrategy != nil {
        var hints = configuration.optimizationHints
        switch reshapeFrequency {
        case .frequent: hints.reshapeFrequency = .frequent
        case .infrequent: hints.reshapeFrequency = .infrequent
        case nil: break
        }
        switch specializationStrategy {
        case .defaults: hints.specializationStrategy = .default
        case .fastPrediction: hints.specializationStrategy = .fastPrediction
        case nil: break
        }
        configuration.optimizationHints = hints
      }
      return configuration
    }

    init(_ configuration: MLModelConfiguration) {
      let hints = configuration.optimizationHints
      self.init(
        computeUnits: ComputeUnitsMessage(configuration.computeUnits),
        allowLowPrecisionAccumulationOnGPU: configuration.allowLowPrecisionAccumulationOnGPU,
        functionName: configuration.functionName,
        modelDisplayName: configuration.modelDisplayName,
        reshapeFrequency: hints.reshapeFrequency == .infrequent ? .infrequent : .frequent,
        specializationStrategy: hints.specializationStrategy == .fastPrediction
          ? .fastPrediction : .defaults)
    }
  }

  // MARK: - Compute devices

  @available(iOS 18.0, macOS 15.0, *)
  extension ComputeDeviceMessage {
    init(_ device: MLComputeDevice) {
      switch device {
      case .cpu:
        self.init(kind: .cpu, name: "CPU")
      case .gpu(let gpu):
        self.init(kind: .gpu, name: "GPU", metalDeviceName: gpu.metalDevice.name)
      case .neuralEngine(let engine):
        self.init(
          kind: .neuralEngine, name: "Neural Engine",
          neuralEngineCoreCount: Int64(engine.totalCoreCount))
      @unknown default:
        self.init(kind: .cpu, name: "\(device)")
      }
    }
  }
#endif
