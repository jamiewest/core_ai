#if canImport(CoreAI)
  import CoreAI
  import Foundation

  // MARK: - Scalar types

  @available(iOS 27.0, macOS 27.0, *)
  extension ScalarTypeMessage {
    var coreAI: NDArray.ScalarType {
      switch self {
      case .boolean: .bool
      case .int2: .int2
      case .int3: .int3
      case .int4: .int4
      case .int5: .int5
      case .int6: .int6
      case .int7: .int7
      case .int8: .int8
      case .int16: .int16
      case .int32: .int32
      case .int64: .int64
      case .int128: .int128
      case .uint1: .uint1
      case .uint2: .uint2
      case .uint3: .uint3
      case .uint4: .uint4
      case .uint5: .uint5
      case .uint6: .uint6
      case .uint7: .uint7
      case .uint8: .uint8
      case .uint16: .uint16
      case .uint32: .uint32
      case .uint64: .uint64
      case .uint128: .uint128
      case .float8e5m2: .float8e5m2
      case .float8e4m3fn: .float8e4m3fn
      case .float8e8m0fn: .float8e8m0fn
      case .float4e2m1fn: .float4e2m1fn
      case .float16: .float16
      case .float32: .float32
      case .float64: .float64
      case .bfloat16: .bfloat16
      case .cfloat16: .cfloat16
      case .cfloat32: .cfloat32
      case .cfloat64: .cfloat64
      }
    }

    init(_ type: NDArray.ScalarType) throws {
      switch type {
      case .bool: self = .boolean
      case .int2: self = .int2
      case .int3: self = .int3
      case .int4: self = .int4
      case .int5: self = .int5
      case .int6: self = .int6
      case .int7: self = .int7
      case .int8: self = .int8
      case .int16: self = .int16
      case .int32: self = .int32
      case .int64: self = .int64
      case .int128: self = .int128
      case .uint1: self = .uint1
      case .uint2: self = .uint2
      case .uint3: self = .uint3
      case .uint4: self = .uint4
      case .uint5: self = .uint5
      case .uint6: self = .uint6
      case .uint7: self = .uint7
      case .uint8: self = .uint8
      case .uint16: self = .uint16
      case .uint32: self = .uint32
      case .uint64: self = .uint64
      case .uint128: self = .uint128
      case .float8e5m2: self = .float8e5m2
      case .float8e4m3fn: self = .float8e4m3fn
      case .float8e8m0fn: self = .float8e8m0fn
      case .float4e2m1fn: self = .float4e2m1fn
      case .float16: self = .float16
      case .float32: self = .float32
      case .float64: self = .float64
      case .bfloat16: self = .bfloat16
      case .cfloat16: self = .cfloat16
      case .cfloat32: self = .cfloat32
      case .cfloat64: self = .cfloat64
      @unknown default:
        throw CoreAIPigeonError(
          .coreAIError, "Unsupported NDArray scalar type \(type). Update the core_ai plugin.")
      }
    }
  }

  // MARK: - Compute units and specialization

  @available(iOS 27.0, macOS 27.0, *)
  extension ComputeUnitKindMessage {
    var coreAI: ComputeUnitKind {
      switch self {
      case .cpu: .cpu
      case .gpu: .gpu
      case .neuralEngine: .neuralEngine
      }
    }

    init?(_ kind: ComputeUnitKind) {
      switch kind {
      case .cpu: self = .cpu
      case .gpu: self = .gpu
      case .neuralEngine: self = .neuralEngine
      @unknown default: return nil
      }
    }
  }

  @available(iOS 27.0, macOS 27.0, *)
  extension SpecializationOptionsMessage {
    func coreAI() throws -> SpecializationOptions {
      var options: SpecializationOptions
      switch preset {
      case .defaults:
        options = .default
      case .cpuOnly:
        options = .cpuOnly
      case .preferred:
        guard let kind = preferredComputeUnitKind else {
          throw Errors.invalidArgument(
            "SpecializationOptions with a preferred preset needs a preferredComputeUnitKind.")
        }
        options = SpecializationOptions(preferredComputeUnitKind: kind.coreAI)
      }
      options.expectFrequentReshapes = expectFrequentReshapes
      return options
    }
  }

  @available(iOS 27.0, macOS 27.0, *)
  extension SpecializationInfoMessage {
    init(_ options: SpecializationOptions) {
      self.init(
        allowedComputeUnitKinds: options.allowedComputeUnitKinds.compactMap(
          ComputeUnitKindMessage.init
        ).sorted { $0.rawValue < $1.rawValue },
        preferredComputeUnitKind: options.preferredComputeUnitKind.flatMap(
          ComputeUnitKindMessage.init),
        expectFrequentReshapes: options.expectFrequentReshapes)
    }
  }

  // MARK: - Cache

  @available(iOS 27.0, macOS 27.0, *)
  extension ModelCacheMessage {
    func coreAI() throws -> AIModelCache {
      guard let group = appGroupIdentifier else { return .default }
      guard let cache = AIModelCache(appGroup: group) else {
        throw Errors.invalidArgument(
          "No AIModelCache for app group '\(group)'. Check the App Groups entitlement.")
      }
      return cache
    }
  }

  @available(iOS 27.0, macOS 27.0, *)
  extension CachePolicyMessage {
    var coreAI: AIModelCache.Policy {
      switch (purgeOnStoragePressure, purgeOnSourceAssetChangedOrDeleted) {
      case (true, true): return .default
      case (false, false): return .persistent
      default:
        var conditions: AIModelCache.Policy.PurgeConditions = []
        if purgeOnStoragePressure { conditions.insert(.storagePressure) }
        if purgeOnSourceAssetChangedOrDeleted { conditions.insert(.sourceAssetChangedOrDeleted) }
        return AIModelCache.Policy(purgeConditions: conditions)
      }
    }
  }

  // MARK: - Descriptors

  @available(iOS 27.0, macOS 27.0, *)
  extension InterleaveLayoutMessage {
    init(_ layout: NDArray.InterleaveLayout) {
      self.init(dimension: Int64(layout.dimension), factor: Int64(layout.factor))
    }

    var coreAI: NDArray.InterleaveLayout {
      NDArray.InterleaveLayout(dimension: Int(dimension), factor: Int(factor))
    }
  }

  @available(iOS 27.0, macOS 27.0, *)
  extension NDArrayDescriptorMessage {
    init(_ descriptor: NDArrayDescriptor) throws {
      // Reading preferredStrides/minimumByteCount on a dynamic descriptor is a
      // programming error in Core AI, so only expose them for static shapes.
      let isDynamic = descriptor.hasDynamicShape
      self.init(
        scalarType: try ScalarTypeMessage(descriptor.scalarType),
        shape: descriptor.shape.map(Int64.init),
        hasDynamicShape: isDynamic,
        interleaveLayout: descriptor.interleaveLayout.map(InterleaveLayoutMessage.init),
        preferredStrides: isDynamic ? nil : descriptor.preferredStrides.map(Int64.init),
        minimumByteCount: isDynamic ? nil : Int64(descriptor.minimumByteCount))
    }
  }

  @available(iOS 27.0, macOS 27.0, *)
  extension ValueDescriptorMessage {
    init(name: String, descriptor: InferenceValue.Descriptor) throws {
      switch descriptor {
      case .ndArray(let array):
        self.init(name: name, kind: .ndArray, ndArray: try NDArrayDescriptorMessage(array))
      case .image(let image):
        self.init(
          name: name,
          kind: .image,
          image: ImageDescriptorMessage(
            width: Int64(image.width),
            height: Int64(image.height),
            pixelFormatType: Int64(image.pixelFormatType)))
      @unknown default:
        throw CoreAIPigeonError(.coreAIError, "Unsupported value descriptor for '\(name)'.")
      }
    }
  }

  @available(iOS 27.0, macOS 27.0, *)
  extension FunctionDescriptorMessage {
    init(_ descriptor: InferenceFunctionDescriptor) throws {
      func map(
        _ names: [String], _ lookup: (String) -> InferenceValue.Descriptor?
      ) throws -> [ValueDescriptorMessage] {
        try names.compactMap { name in
          try lookup(name).map { try ValueDescriptorMessage(name: name, descriptor: $0) }
        }
      }
      self.init(
        name: descriptor.name,
        inputs: try map(descriptor.inputNames, descriptor.inputDescriptor(of:)),
        states: try map(descriptor.stateNames, descriptor.stateDescriptor(of:)),
        outputs: try map(descriptor.outputNames, descriptor.outputDescriptor(of:)))
    }
  }

  @available(iOS 27.0, macOS 27.0, *)
  extension InferenceFunctionDescriptor {
    /// Looks up the descriptor of a named argument, throwing `not_found` when
    /// the function has no such argument.
    func descriptor(role: ValueRoleMessage, name: String) throws -> InferenceValue.Descriptor {
      let found: InferenceValue.Descriptor?
      switch role {
      case .input: found = inputDescriptor(of: name)
      case .state: found = stateDescriptor(of: name)
      case .output: found = outputDescriptor(of: name)
      }
      guard let found else {
        throw Errors.notFound("Function '\(self.name)' has no \(role) named '\(name)'.")
      }
      return found
    }
  }

  @available(iOS 27.0, macOS 27.0, *)
  extension NDArrayDescriptor {
    /// `resolvingDynamicDimensions(_:)` with the preconditions checked up
    /// front, so bad input throws instead of trapping.
    func resolving(shape newShape: [Int64]) throws -> NDArrayDescriptor {
      guard newShape.count == shape.count else {
        throw Errors.invalidArgument(
          "Shape \(newShape) has rank \(newShape.count); the descriptor has rank \(shape.count).")
      }
      for (index, (existing, proposed)) in zip(shape, newShape).enumerated() {
        guard proposed >= 0, existing == -1 || Int64(existing) == proposed else {
          throw Errors.invalidArgument(
            "Dimension \(index) cannot be \(proposed); the descriptor requires \(existing).")
        }
      }
      return resolvingDynamicDimensions(newShape.map(Int.init))
    }
  }

  // MARK: - Paths

  /// A file URL for [path], throwing `not_found` when nothing exists there.
  ///
  /// Core AI reports a missing model as a malformed asset ("Missing hash
  /// file"), so check existence first for a clearer error.
  func existingFileURL(_ path: String) throws -> URL {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw Errors.notFound("No file or directory at '\(url.path)'.")
    }
    return url
  }
#endif
