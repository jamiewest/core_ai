#if canImport(CoreML)
  import CoreML
  import CoreVideo
  import Foundation

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Converts between `MLFeatureValue` and `FeatureValueMessage`.
  @available(iOS 18.0, macOS 15.0, *)
  enum FeatureValueBridge {
    /// Builds the feature value for input [name].
    ///
    /// [description] is the model's description of that input, which supplies
    /// the size and pixel format an encoded image has to be converted to.
    static func featureValue(
      _ message: FeatureValueMessage, name: String, description: MLFeatureDescription?
    ) throws -> MLFeatureValue {
      switch message {
      case let array as MultiArrayMessage:
        return MLFeatureValue(multiArray: try MultiArrayBridge.make(array))
      case let buffer as PixelBufferMessage:
        return MLFeatureValue(pixelBuffer: try PixelBufferBridge.make(buffer))
      case let image as EncodedImageMessage:
        return MLFeatureValue(
          pixelBuffer: try pixelBuffer(for: image, name: name, description: description))
      case let value as StringValueMessage:
        return MLFeatureValue(string: value.value)
      case let value as Int64ValueMessage:
        return MLFeatureValue(int64: value.value)
      case let value as DoubleValueMessage:
        return MLFeatureValue(double: value.value)
      case let value as DictionaryValueMessage:
        return try dictionaryValue(value, name: name)
      case let value as SequenceValueMessage:
        return MLFeatureValue(sequence: try sequence(value, name: name))
      case let value as UndefinedValueMessage:
        return MLFeatureValue(undefined: value.featureType.coreML)
      default:
        throw Errors.invalidArgument("Unsupported value for feature '\(name)'.")
      }
    }

    /// Copies a feature value into a message.
    static func message(_ value: MLFeatureValue, name: String) throws -> FeatureValueMessage {
      if value.isUndefined {
        return UndefinedValueMessage(featureType: FeatureTypeMessage(value.type))
      }
      switch value.type {
      case .int64:
        return Int64ValueMessage(value: value.int64Value)
      case .double:
        return DoubleValueMessage(value: value.doubleValue)
      case .string:
        return StringValueMessage(value: value.stringValue)
      case .multiArray:
        guard let array = value.multiArrayValue else {
          throw Errors.invalidArgument("Feature '\(name)' has no multi array.")
        }
        return try MultiArrayBridge.message(array)
      case .image:
        guard let buffer = value.imageBufferValue else {
          throw Errors.invalidArgument("Feature '\(name)' has no image.")
        }
        return PixelBufferBridge.message(buffer)
      case .dictionary:
        return dictionaryMessage(value.dictionaryValue)
      case .sequence:
        guard let sequence = value.sequenceValue else {
          throw Errors.invalidArgument("Feature '\(name)' has no sequence.")
        }
        return sequence.type == .string
          ? SequenceValueMessage(strings: sequence.stringValues)
          : SequenceValueMessage(int64s: sequence.int64Values.map { $0.int64Value })
      default:
        throw Errors.unsupported(
          "Feature '\(name)' has unsupported type \(value.type.rawValue).")
      }
    }

    // MARK: Images

    private static func pixelBuffer(
      for image: EncodedImageMessage, name: String, description: MLFeatureDescription?
    ) throws -> CVPixelBuffer {
      let constraint = description?.imageConstraint
      let format =
        image.pixelFormatType.map { OSType(truncatingIfNeeded: $0) }
        ?? constraint?.pixelFormatType
        ?? kCVPixelFormatType_32BGRA
      let width = image.width.map(Int.init) ?? constraint?.pixelsWide
      let height = image.height.map(Int.init) ?? constraint?.pixelsHigh
      let data: Data
      if let bytes = image.bytes {
        data = bytes.data
      } else if let path = image.path {
        data = try Data(contentsOf: try existingFileURL(path))
      } else {
        throw Errors.invalidArgument(
          "Image feature '\(name)' has neither encoded bytes nor a file path.")
      }
      return try PixelBufferBridge.fromEncodedImage(
        data, pixelFormatType: format,
        width: (width ?? 0) > 0 ? width : nil,
        height: (height ?? 0) > 0 ? height : nil)
    }

    // MARK: Dictionaries and sequences

    private static func dictionaryValue(_ message: DictionaryValueMessage, name: String) throws
      -> MLFeatureValue
    {
      var dictionary: [AnyHashable: NSNumber] = [:]
      if let stringKeyed = message.stringKeyed {
        for (key, value) in stringKeyed { dictionary[key] = NSNumber(value: value) }
      } else if let int64Keyed = message.int64Keyed {
        for (key, value) in int64Keyed {
          dictionary[NSNumber(value: key)] = NSNumber(value: value)
        }
      } else {
        throw Errors.invalidArgument(
          "Dictionary feature '\(name)' has neither string nor int64 keys.")
      }
      return try MLFeatureValue(dictionary: dictionary)
    }

    private static func dictionaryMessage(_ dictionary: [AnyHashable: NSNumber])
      -> DictionaryValueMessage
    {
      if dictionary.keys.allSatisfy({ $0 is String }) {
        var result: [String: Double] = [:]
        for (key, value) in dictionary {
          if let key = key as? String { result[key] = value.doubleValue }
        }
        return DictionaryValueMessage(stringKeyed: result)
      }
      var result: [Int64: Double] = [:]
      for (key, value) in dictionary {
        if let key = key as? NSNumber { result[key.int64Value] = value.doubleValue }
      }
      return DictionaryValueMessage(int64Keyed: result)
    }

    private static func sequence(_ message: SequenceValueMessage, name: String) throws
      -> MLSequence
    {
      if let strings = message.strings { return MLSequence(strings: strings) }
      if let int64s = message.int64s {
        return MLSequence(int64s: int64s.map { NSNumber(value: $0) })
      }
      throw Errors.invalidArgument(
        "Sequence feature '\(name)' has neither strings nor int64s.")
    }
  }
#endif
