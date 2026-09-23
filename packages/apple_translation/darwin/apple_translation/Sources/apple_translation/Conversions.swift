#if canImport(Translation)
  import Foundation
  import Translation

  /// Converts between Pigeon messages and Translation types.
  @available(iOS 18.0, macOS 15.0, *)
  enum Conversions {
    // MARK: - Languages

    /// Parses a BCP 47 identifier, rejecting blank input that would otherwise
    /// become an empty `Locale.Language`.
    static func language(_ identifier: String) throws -> Locale.Language {
      let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else {
        throw Errors.invalidArgument("A language identifier must not be empty.")
      }
      let language = Locale.Language(identifier: trimmed)
      guard language.languageCode != nil else {
        throw Errors.invalidArgument("\"\(identifier)\" is not a BCP 47 language identifier.")
      }
      return language
    }

    static func language(_ identifier: String?) throws -> Locale.Language? {
      guard let identifier else { return nil }
      return try language(identifier)
    }

    static func message(_ language: Locale.Language) -> LanguageMessage {
      let minimal = language.minimalIdentifier
      return LanguageMessage(
        minimalIdentifier: minimal,
        maximalIdentifier: language.maximalIdentifier,
        languageCode: language.languageCode?.identifier,
        script: language.script?.identifier,
        region: language.region?.identifier,
        localizedName: Locale.current.localizedString(forIdentifier: minimal))
    }

    static func message(_ language: Locale.Language?) -> LanguageMessage? {
      language.map { message($0) }
    }

    // MARK: - Status

    static func status(_ status: LanguageAvailability.Status) -> LanguageStatusMessage {
      switch status {
      case .installed: return .installed
      case .supported: return .supported
      case .unsupported: return .unsupported
      @unknown default: return .unsupported
      }
    }

    // MARK: - Strategy (iOS 26.4 / macOS 26.4)

    @available(iOS 26.4, macOS 26.4, *)
    static func strategy(_ message: StrategyMessage) -> TranslationSession.Strategy {
      switch message {
      case .highFidelity: return .highFidelity
      case .lowLatency: return .lowLatency
      }
    }

    @available(iOS 26.4, macOS 26.4, *)
    static func message(_ strategy: TranslationSession.Strategy) -> StrategyMessage {
      strategy == .lowLatency ? .lowLatency : .highFidelity
    }

    // MARK: - Requests and responses

    static func request(_ message: TranslationRequestMessage) throws -> TranslationSession.Request {
      if let segments = message.segments {
        guard #available(iOS 26.4, macOS 26.4, *) else {
          throw Errors.unsupported("Attributed text needs iOS 26.4 / macOS 26.4.")
        }
        return TranslationSession.Request(
          sourceText: attributed(segments), clientIdentifier: message.clientIdentifier)
      }
      return TranslationSession.Request(
        sourceText: message.sourceText, clientIdentifier: message.clientIdentifier)
    }

    @available(iOS 26.4, macOS 26.4, *)
    static func attributed(_ segments: [TextSegmentMessage]) -> AttributedString {
      var result = AttributedString()
      for segment in segments {
        var run = AttributedString(segment.text)
        if segment.skipsTranslation { run.translation.skipsTranslation = true }
        result.append(run)
      }
      return result
    }

    /// The runs of [text], merging neighbours with the same flag.
    @available(iOS 26.4, macOS 26.4, *)
    static func segments(_ text: AttributedString) -> [TextSegmentMessage] {
      var segments: [TextSegmentMessage] = []
      for run in text.runs {
        let piece = String(text[run.range].characters)
        let skips = run.translation.skipsTranslation ?? false
        if let last = segments.last, last.skipsTranslation == skips {
          segments[segments.count - 1] = TextSegmentMessage(
            text: last.text + piece, skipsTranslation: skips)
        } else {
          segments.append(TextSegmentMessage(text: piece, skipsTranslation: skips))
        }
      }
      return segments
    }

    static func response(_ response: TranslationSession.Response) -> TranslationResponseMessage {
      var targetSegments: [TextSegmentMessage]?
      if #available(iOS 26.4, macOS 26.4, *), response.attributedSourceText != nil,
        let attributed = response.attributedTargetText
      {
        targetSegments = segments(attributed)
      }
      return TranslationResponseMessage(
        sourceLanguage: message(response.sourceLanguage),
        targetLanguage: message(response.targetLanguage),
        sourceText: response.sourceText,
        targetText: response.targetText,
        targetSegments: targetSegments,
        clientIdentifier: response.clientIdentifier)
    }
  }
#endif
