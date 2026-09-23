#if canImport(CoreAI)
  import CoreAI
  import Foundation

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Converts between `NDArray` and `NDArrayMessage`, and manipulates NDArray
  /// storage as raw bytes (which works uniformly for every scalar type).
  @available(iOS 27.0, macOS 27.0, *)
  enum NDArrayBridge {
    /// Creates an NDArray with the message's layout and copies its bytes in.
    static func make(_ message: NDArrayMessage) throws -> NDArray {
      var array = try allocate(
        scalarType: message.scalarType,
        shape: message.shape,
        strides: message.strides,
        interleaveLayout: message.interleaveLayout)
      try overwrite(&array, with: message.data.data)
      return array
    }

    /// Allocates a zero-filled NDArray. Empty [strides] means row-major
    /// contiguous.
    static func allocate(
      scalarType: ScalarTypeMessage,
      shape: [Int64],
      strides: [Int64]?,
      interleaveLayout: InterleaveLayoutMessage?
    ) throws -> NDArray {
      guard shape.allSatisfy({ $0 >= 0 }) else {
        throw Errors.invalidArgument(
          "Shape \(shape) has negative dimensions. Resolve dynamic dimensions first.")
      }
      let type = scalarType.coreAI
      let dims = shape.map(Int.init)
      var array: NDArray
      if let strides, !strides.isEmpty {
        guard strides.count == shape.count else {
          throw Errors.invalidArgument(
            "Strides \(strides) must have the same rank as shape \(shape).")
        }
        let elementStrides = strides.map(Int.init)
        if let interleaveLayout {
          array = NDArray(
            shape: dims, scalarType: type, strides: elementStrides,
            interleaveLayout: interleaveLayout.coreAI)
        } else {
          array = NDArray(shape: dims, scalarType: type, strides: elementStrides)
        }
      } else {
        guard interleaveLayout == nil else {
          throw Errors.invalidArgument("An interleave layout requires explicit strides.")
        }
        array = NDArray(shape: dims, scalarType: type)
      }
      zero(&array)
      return array
    }

    /// Allocates a zero-filled NDArray with the descriptor's preferred layout.
    static func allocate(_ descriptor: NDArrayDescriptor) -> NDArray {
      var array = NDArray(descriptor: descriptor)
      zero(&array)
      return array
    }

    /// The size of the array's backing storage in bytes.
    static func byteCount(_ array: NDArray) -> Int {
      array.rawView().bytes.byteCount
    }

    /// Replaces the array's storage with [data], which must be exactly the
    /// storage size.
    static func overwrite(_ array: inout NDArray, with data: Data) throws {
      let expected = byteCount(array)
      guard data.count == expected else {
        throw Errors.invalidArgument(
          "NDArray of \(array.scalarType) with shape \(array.shape) and strides "
            + "\(array.strides) needs \(expected) bytes of storage, got \(data.count).")
      }
      guard expected > 0 else { return }
      array.mutableRawView().withUnsafeMutableBytes { destination, _, _ in
        data.withUnsafeBytes { source in
          destination.copyMemory(from: source.baseAddress!, byteCount: expected)
        }
      }
    }

    static func zero(_ array: inout NDArray) {
      let count = byteCount(array)
      guard count > 0 else { return }
      array.mutableRawView().withUnsafeMutableBytes { destination, _, _ in
        _ = memset(destination, 0, count)
      }
    }

    /// A copy of the array's raw storage.
    static func bytes(_ array: NDArray) -> Data {
      let raw = array.rawView()
      let count = raw.bytes.byteCount
      guard count > 0 else { return Data() }
      return raw.withUnsafeBytes { pointer, _, _ in Data(bytes: pointer, count: count) }
    }

    static func message(_ array: NDArray) throws -> NDArrayMessage {
      NDArrayMessage(
        scalarType: try ScalarTypeMessage(array.scalarType),
        shape: array.shape.map(Int64.init),
        strides: array.strides.map(Int64.init),
        interleaveLayout: array.interleaveLayout.map(InterleaveLayoutMessage.init),
        data: FlutterStandardTypedData(bytes: bytes(array)))
    }

    /// An independent copy with the same layout and contents.
    static func copy(_ array: NDArray) throws -> NDArray {
      var result = try allocate(
        scalarType: try ScalarTypeMessage(array.scalarType),
        shape: array.shape.map(Int64.init),
        strides: array.strides.map(Int64.init),
        interleaveLayout: array.interleaveLayout.map(InterleaveLayoutMessage.init))
      try overwrite(&result, with: bytes(array))
      return result
    }

    static func info(_ array: NDArray, handle: Int64) throws -> NativeValueInfoMessage {
      NativeValueInfoMessage(
        handle: handle,
        kind: .ndArray,
        scalarType: try ScalarTypeMessage(array.scalarType),
        shape: array.shape.map(Int64.init),
        strides: array.strides.map(Int64.init),
        interleaveLayout: array.interleaveLayout.map(InterleaveLayoutMessage.init),
        byteCount: Int64(byteCount(array)))
    }
  }
#endif
