#if canImport(CoreML)
  import CoreML
  import Foundation

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Converts between `MLMultiArray` and `MultiArrayMessage`.
  ///
  /// The storage is copied as raw bytes together with the element strides, so
  /// non-contiguous arrays survive the trip. Core ML hands out padded arrays
  /// more often than one would expect: a float16 output backed by a
  /// `CVPixelBuffer` has its rows aligned, so its last stride is larger than
  /// the row length.
  @available(iOS 18.0, macOS 15.0, *)
  enum MultiArrayBridge {
    /// Copies an array's layout and storage into a message.
    static func message(_ array: MLMultiArray) throws -> MultiArrayMessage {
      let data = array.withUnsafeBytes { pointer -> Data in
        guard let base = pointer.baseAddress, pointer.count > 0 else { return Data() }
        return Data(bytes: base, count: pointer.count)
      }
      return MultiArrayMessage(
        dataType: try MultiArrayDataTypeMessage(array.dataType),
        shape: array.shape.map { Int64(truncating: $0) },
        strides: array.strides.map { Int64(truncating: $0) },
        data: FlutterStandardTypedData(bytes: data))
    }

    /// Builds an array with the message's layout and contents.
    static func make(_ message: MultiArrayMessage) throws -> MLMultiArray {
      let shape = message.shape
      guard shape.allSatisfy({ $0 >= 0 }) else {
        throw Errors.invalidArgument("Shape \(shape) has negative dimensions.")
      }
      let dataType = try message.dataType.coreML
      let elementSize = message.dataType.byteCount
      let strides = message.strides.isEmpty ? contiguousStrides(shape) : message.strides
      guard strides.count == shape.count else {
        throw Errors.invalidArgument(
          "Strides \(strides) must have the same rank as shape \(shape).")
      }
      let expected = storageElements(shape: shape, strides: strides) * elementSize
      let source = message.data.data
      guard source.count == expected else {
        throw Errors.invalidArgument(
          "A \(message.dataType) array with shape \(shape) and strides \(strides) needs "
            + "\(expected) bytes of storage, got \(source.count).")
      }
      let array = MLMultiArray(
        shape: shape.map(Int.init), dataType: dataType, strides: strides.map(Int.init))
      try write(source, sourceStrides: strides, shape: shape, elementSize: elementSize, into: array)
      return array
    }

    /// Overwrites an array's contents, keeping its layout.
    static func overwrite(_ array: MLMultiArray, with message: MultiArrayMessage) throws {
      let shape = array.shape.map { Int64(truncating: $0) }
      guard try MultiArrayDataTypeMessage(array.dataType) == message.dataType,
        message.shape == shape
      else {
        throw Errors.invalidArgument(
          "Layout mismatch: the native array is \(array.dataType) \(shape); the data is "
            + "\(message.dataType) \(message.shape).")
      }
      let elementSize = message.dataType.byteCount
      let strides = message.strides.isEmpty ? contiguousStrides(shape) : message.strides
      let expected = storageElements(shape: shape, strides: strides) * elementSize
      let source = message.data.data
      guard source.count == expected else {
        throw Errors.invalidArgument(
          "The array needs \(expected) bytes of storage, got \(source.count).")
      }
      try write(source, sourceStrides: strides, shape: shape, elementSize: elementSize, into: array)
    }

    /// Copies [source] into [array], honouring the strides Core ML reports for
    /// the destination, which need not be the ones it was asked for.
    private static func write(
      _ source: Data, sourceStrides: [Int64], shape: [Int64], elementSize: Int,
      into array: MLMultiArray
    ) throws {
      guard !source.isEmpty else { return }
      var failure: (any Error)?
      array.withUnsafeMutableBytes { pointer, destinationStrides in
        guard let base = pointer.baseAddress else { return }
        let actual = destinationStrides.map(Int64.init)
        source.withUnsafeBytes { input in
          let from = input.baseAddress!
          if actual == sourceStrides, pointer.count == source.count {
            base.copyMemory(from: from, byteCount: source.count)
            return
          }
          let required = storageElements(shape: shape, strides: actual) * elementSize
          guard pointer.count >= required else {
            failure = Errors.invalidArgument(
              "Core ML allocated \(pointer.count) bytes for strides \(actual); "
                + "\(required) are needed.")
            return
          }
          forEachIndex(shape: shape) { index in
            var sourceOffset = 0
            var destinationOffset = 0
            for dimension in index.indices {
              sourceOffset += Int(index[dimension] * sourceStrides[dimension])
              destinationOffset += Int(index[dimension] * actual[dimension])
            }
            (base + destinationOffset * elementSize).copyMemory(
              from: from + sourceOffset * elementSize, byteCount: elementSize)
          }
        }
      }
      if let failure { throw failure }
    }

    /// Calls [body] for every logical index of [shape], in row-major order.
    private static func forEachIndex(shape: [Int64], _ body: ([Int64]) -> Void) {
      guard !shape.isEmpty else { return body([]) }
      guard shape.allSatisfy({ $0 > 0 }) else { return }
      var index = [Int64](repeating: 0, count: shape.count)
      while true {
        body(index)
        var dimension = shape.count - 1
        while dimension >= 0 {
          index[dimension] += 1
          if index[dimension] < shape[dimension] { break }
          index[dimension] = 0
          dimension -= 1
        }
        if dimension < 0 { return }
      }
    }
  }

  /// Row-major contiguous element strides for [shape].
  func contiguousStrides(_ shape: [Int64]) -> [Int64] {
    var strides = [Int64](repeating: 1, count: shape.count)
    var stride: Int64 = 1
    for index in shape.indices.reversed() {
      strides[index] = stride
      stride *= max(shape[index], 1)
    }
    return strides
  }

  /// The number of elements a strided layout spans (largest offset plus one).
  func storageElements(shape: [Int64], strides: [Int64]) -> Int {
    if shape.contains(0) { return 0 }
    var maxOffset: Int64 = 0
    for dimension in shape.indices {
      maxOffset += (shape[dimension] - 1) * strides[dimension]
    }
    return Int(maxOffset) + 1
  }
#endif
