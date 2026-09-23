#if canImport(CoreAI)
  import CoreAI
  import Foundation

  /// `AIModelAsset`: validation, metadata, summaries and derived artifacts.
  @available(iOS 27.0, macOS 27.0, *)
  enum AssetBridge {
    typealias Metadata = AIModelAsset.Metadata
    typealias CreatorDefinedValue = AIModelAsset.Metadata.CreatorDefinedValue

    static func metadata(path: String) throws -> AssetMetadataMessage {
      let asset = try AIModelAsset(contentsOf: try existingFileURL(path))
      let metadata = asset.metadata
      return AssetMetadataMessage(
        author: metadata.author,
        license: metadata.license,
        modelDescription: metadata.description,
        creationDateMillis: metadata.creationDate.map {
          Int64(($0.timeIntervalSince1970 * 1000).rounded())
        },
        creatorDefined: metadata.creatorDefinedMetadata.mapValues(encode))
    }

    static func summary(path: String, includeStatistics: Bool) throws -> AssetSummaryMessage? {
      let asset = try AIModelAsset(contentsOf: try existingFileURL(path))
      guard let summary = try asset.summary(includingStatistics: includeStatistics) else {
        return nil
      }
      func values(_ list: [AIModelAsset.ValueDescriptor]) -> [AssetValueDescriptorMessage] {
        list.map { AssetValueDescriptorMessage(name: $0.name, typeName: $0.typeName) }
      }
      return AssetSummaryMessage(
        functions: summary.functions.map {
          AssetFunctionDescriptorMessage(
            name: $0.name, inputs: values($0.inputs), states: values($0.states),
            outputs: values($0.outputs))
        },
        storageTypes: summary.storageTypes.map {
          NamedCountMessage(name: $0.typeName, count: Int64($0.count))
        },
        computeTypes: summary.computeTypes,
        operationDistribution: summary.operationDistribution.map {
          NamedCountMessage(name: $0.operationName, count: Int64($0.count))
        })
    }

    static func updateMetadata(path: String, update: AssetMetadataUpdateMessage) throws {
      var asset = try AIModelAsset(contentsOf: try existingFileURL(path))
      let additions = try update.creatorDefined.mapValues(decode)
      try asset.updateMetadata { metadata in
        if let author = update.author { metadata.author = author }
        if let license = update.license { metadata.license = license }
        if let description = update.modelDescription { metadata.description = description }
        if update.clearCreationDate {
          metadata.creationDate = nil
        } else if let millis = update.creationDateMillis {
          metadata.creationDate = Date(timeIntervalSince1970: Double(millis) / 1000)
        }
        for key in update.creatorDefinedRemovals {
          metadata.creatorDefinedMetadata[key] = nil
        }
        for (key, value) in additions {
          metadata.creatorDefinedMetadata[key] = value
        }
      }
    }

    static func removeDerivedArtifacts(path: String) throws {
      var asset = try AIModelAsset(contentsOf: try existingFileURL(path))
      try asset.removeDerivedArtifacts()
    }

    // MARK: Creator-defined values

    /// Maps a creator-defined value onto standard-codec types.
    private static func encode(_ value: CreatorDefinedValue) -> Any? {
      switch value {
      case .string(let string): return string
      case .integer(let integer): return Int64(integer)
      case .number(let number): return number
      case .bool(let bool): return bool
      case .array(let array): return array.map(encode)
      case .dictionary(let dictionary): return dictionary.mapValues(encode)
      @unknown default: return String(describing: value)
      }
    }

    /// Maps a standard-codec value onto a creator-defined value.
    ///
    /// The codec delivers Dart numbers and booleans as `NSNumber`, so the
    /// underlying Core Foundation type decides between bool, integer and
    /// floating point.
    private static func decode(_ value: Any?) throws -> CreatorDefinedValue {
      switch value {
      case let string as String:
        return .string(string)
      case let number as NSNumber:
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return .bool(number.boolValue) }
        if CFNumberIsFloatType(number) { return .number(number.doubleValue) }
        return .integer(number.intValue)
      case let array as [Any?]:
        return .array(try array.map(decode))
      case let dictionary as [AnyHashable: Any?]:
        var result: [String: CreatorDefinedValue] = [:]
        for (key, element) in dictionary {
          guard let key = key as? String else {
            throw Errors.invalidArgument("Creator-defined metadata keys must be strings.")
          }
          result[key] = try decode(element)
        }
        return .dictionary(result)
      default:
        throw Errors.invalidArgument(
          "Unsupported creator-defined metadata value \(String(describing: value)). Use "
            + "String, int, double, bool, List or Map.")
      }
    }
  }
#endif
