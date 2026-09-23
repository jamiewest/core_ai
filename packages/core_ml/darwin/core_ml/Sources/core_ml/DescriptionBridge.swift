#if canImport(CoreML)
  import CoreML
  import Foundation

  /// Converts `MLModelDescription` and its feature descriptions into messages.
  @available(iOS 18.0, macOS 15.0, *)
  enum DescriptionBridge {
    static func message(_ description: MLModelDescription) -> ModelDescriptionMessage {
      let labels = description.classLabels ?? []
      let strings = labels.compactMap { $0 as? String }
      let numbers = labels.compactMap { $0 as? NSNumber }
      return ModelDescriptionMessage(
        inputs: features(description.inputDescriptionsByName),
        outputs: features(description.outputDescriptionsByName),
        states: features(description.stateDescriptionsByName),
        trainingInputs: features(description.trainingInputDescriptionsByName),
        predictedFeatureName: description.predictedFeatureName,
        predictedProbabilitiesName: description.predictedProbabilitiesName,
        classLabelStrings: strings.count == labels.count && !labels.isEmpty ? strings : nil,
        classLabelInts: strings.isEmpty && !numbers.isEmpty
          ? numbers.map { $0.int64Value } : nil,
        isUpdatable: description.isUpdatable,
        metadata: metadata(description.metadata))
    }

    private static func features(_ descriptions: [String: MLFeatureDescription])
      -> [FeatureDescriptionMessage]
    {
      descriptions.keys.sorted().map { message(descriptions[$0]!) }
    }

    static func message(_ description: MLFeatureDescription) -> FeatureDescriptionMessage {
      FeatureDescriptionMessage(
        name: description.name,
        type: FeatureTypeMessage(description.type),
        optional: description.isOptional,
        multiArrayConstraint: description.multiArrayConstraint.flatMap(constraint),
        imageConstraint: description.imageConstraint.map(constraint),
        dictionaryConstraint: description.dictionaryConstraint.map {
          DictionaryConstraintMessage(keyType: FeatureTypeMessage($0.keyType))
        },
        sequenceConstraint: description.sequenceConstraint.map { sequence in
          let range = sequence.countRange
          return SequenceConstraintMessage(
            valueType: FeatureTypeMessage(sequence.valueDescription.type),
            minimumCount: Int64(range.location),
            maximumCount: upperBound(range))
        },
        stateConstraint: description.stateConstraint.flatMap { state in
          guard let dataType = try? MultiArrayDataTypeMessage(state.dataType) else { return nil }
          return StateConstraintMessage(
            dataType: dataType, bufferShape: state.bufferShape.map(Int64.init))
        })
    }

    private static func constraint(_ constraint: MLMultiArrayConstraint)
      -> MultiArrayConstraintMessage?
    {
      guard let dataType = try? MultiArrayDataTypeMessage(constraint.dataType) else { return nil }
      let shapeConstraint = constraint.shapeConstraint
      let ranges = shapeConstraint.sizeRangeForDimension.map { $0.rangeValue }
      return MultiArrayConstraintMessage(
        dataType: dataType,
        shape: constraint.shape.map { Int64(truncating: $0) },
        shapeConstraintType: ShapeConstraintTypeMessage(shapeConstraint.type),
        enumeratedShapes: shapeConstraint.enumeratedShapes.map {
          ShapeMessage(dimensions: $0.map { dimension in Int64(truncating: dimension) })
        },
        minimumSizes: ranges.map { Int64($0.location) },
        maximumSizes: ranges.map(upperBound))
    }

    private static func constraint(_ constraint: MLImageConstraint) -> ImageConstraintMessage {
      let sizeConstraint = constraint.sizeConstraint
      return ImageConstraintMessage(
        pixelsWide: Int64(constraint.pixelsWide),
        pixelsHigh: Int64(constraint.pixelsHigh),
        pixelFormatType: Int64(constraint.pixelFormatType),
        sizeConstraintType: ImageSizeConstraintTypeMessage(sizeConstraint.type),
        enumeratedSizes: sizeConstraint.enumeratedImageSizes.map {
          ImageSizeMessage(width: Int64($0.pixelsWide), height: Int64($0.pixelsHigh))
        },
        minimumWidth: Int64(sizeConstraint.pixelsWideRange.location),
        maximumWidth: upperBound(sizeConstraint.pixelsWideRange),
        minimumHeight: Int64(sizeConstraint.pixelsHighRange.location),
        maximumHeight: upperBound(sizeConstraint.pixelsHighRange))
    }

    /// The inclusive upper bound of a size range; `-1` when it is unbounded.
    private static func upperBound(_ range: NSRange) -> Int64 {
      guard range.length > 0, range.length < Int.max / 2 else { return -1 }
      return Int64(range.location + range.length - 1)
    }

    private static func metadata(_ metadata: [MLModelMetadataKey: Any]) -> ModelMetadataMessage {
      var creatorDefined: [String: String] = [:]
      if let defined = metadata[.creatorDefinedKey] as? [String: Any] {
        for (key, value) in defined {
          creatorDefined[key] = value as? String ?? String(describing: value)
        }
      }
      return ModelMetadataMessage(
        author: metadata[.author] as? String,
        license: metadata[.license] as? String,
        modelDescription: metadata[.description] as? String,
        versionString: metadata[.versionString] as? String,
        creatorDefined: creatorDefined)
    }
  }

  @available(iOS 18.0, macOS 15.0, *)
  extension ShapeConstraintTypeMessage {
    init(_ type: MLMultiArrayShapeConstraintType) {
      switch type {
      case .enumerated: self = .enumerated
      case .range: self = .range
      default: self = .unspecified
      }
    }
  }

  @available(iOS 18.0, macOS 15.0, *)
  extension ImageSizeConstraintTypeMessage {
    init(_ type: MLImageSizeConstraintType) {
      switch type {
      case .enumerated: self = .enumerated
      case .range: self = .range
      default: self = .unspecified
      }
    }
  }
#endif
