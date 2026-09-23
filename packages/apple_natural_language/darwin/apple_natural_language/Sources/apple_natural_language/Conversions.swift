#if canImport(NaturalLanguage)
  import Foundation
  import NaturalLanguage

  /// Maps between Pigeon messages and NaturalLanguage types.
  enum Conversions {
    static func unit(_ message: TokenUnitMessage) -> NLTokenUnit {
      switch message {
      case .word: .word
      case .sentence: .sentence
      case .paragraph: .paragraph
      case .document: .document
      }
    }

    static func scheme(_ message: TagSchemeMessage) -> NLTagScheme {
      switch message {
      case .tokenType: .tokenType
      case .lexicalClass: .lexicalClass
      case .nameType: .nameType
      case .nameTypeOrLexicalClass: .nameTypeOrLexicalClass
      case .lemma: .lemma
      case .language: .language
      case .script: .script
      case .sentimentScore: .sentimentScore
      }
    }

    static func options(_ messages: [TagOptionMessage]) -> NLTagger.Options {
      var options: NLTagger.Options = []
      for message in messages {
        switch message {
        case .omitWords: options.insert(.omitWords)
        case .omitPunctuation: options.insert(.omitPunctuation)
        case .omitWhitespace: options.insert(.omitWhitespace)
        case .omitOther: options.insert(.omitOther)
        case .joinNames: options.insert(.joinNames)
        case .joinContractions: options.insert(.joinContractions)
        }
      }
      return options
    }

    static func attributes(_ flags: NLTokenizer.Attributes) -> [TokenAttributeMessage] {
      var result: [TokenAttributeMessage] = []
      if flags.contains(.numeric) { result.append(.numeric) }
      if flags.contains(.symbolic) { result.append(.symbolic) }
      if flags.contains(.emoji) { result.append(.emoji) }
      return result
    }

    static func distance(_ message: DistanceTypeMessage) -> NLDistanceType {
      switch message {
      case .cosine: .cosine
      }
    }

    static func assetsResult(_ result: NLTagger.AssetsResult) -> AssetsResultMessage {
      switch result {
      case .available: .available
      case .notAvailable: .notAvailable
      case .error: .error
      @unknown default: .error
      }
    }

    @available(iOS 17.0, macOS 14.0, *)
    static func assetsResult(_ result: NLContextualEmbedding.AssetsResult)
      -> AssetsResultMessage
    {
      switch result {
      case .available: .available
      case .notAvailable: .notAvailable
      case .error: .error
      @unknown default: .error
      }
    }

    static func modelType(_ type: NLModel.ModelType) -> ModelTypeMessage {
      switch type {
      case .classifier: .classifier
      case .sequence: .sequence
      @unknown default: .classifier
      }
    }

    /// Converts an `NSRange` in [text] to UTF-16 offsets, which is also how
    /// Dart indexes strings.
    static func range(_ range: Range<String.Index>, in text: String) -> (Int64, Int64) {
      let nsRange = NSRange(range, in: text)
      return (Int64(nsRange.location), Int64(nsRange.length))
    }

    /// The `String.Index` range for UTF-16 offsets from Dart.
    static func stringIndex(_ offset: Int64, in text: String) throws -> String.Index {
      guard let index = Range(NSRange(location: Int(offset), length: 0), in: text)?.lowerBound
      else {
        throw Errors.invalidArgument(
          "Offset \(offset) is outside the text, or splits a surrogate pair.")
      }
      return index
    }

    static func fileURL(_ path: String) throws -> URL {
      let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw Errors.notFound("No file at '\(url.path)'.")
      }
      return url
    }
  }
#endif
