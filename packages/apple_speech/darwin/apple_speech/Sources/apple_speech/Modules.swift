#if canImport(Speech)
  import AVFoundation
  import CoreMedia
  import Foundation
  import Speech

  /// Builds `SpeechModule`s from messages and converts their results.
  @available(iOS 26.0, macOS 26.0, *)
  enum Modules {
    /// Builds the modules. With [validate], also rejects configurations that
    /// Speech fails on with misleading errors or traps: no transcriber,
    /// unsupported locales, and locales whose assets are not installed.
    static func build(_ configs: [ModuleConfigMessage], validate: Bool) async throws
      -> [any SpeechModule]
    {
      guard !configs.isEmpty else { throw Errors.invalidArgument("Pass at least one module.") }
      if validate {
        guard configs.contains(where: { $0.kind != .speechDetector }) else {
          throw Errors.invalidArgument(
            "SpeechDetector needs a SpeechTranscriber or DictationTranscriber in the "
              + "same analyzer.")
        }
      }
      var modules: [any SpeechModule] = []
      for config in configs {
        modules.append(try await build(config, validate: validate))
      }
      return modules
    }

    private static func build(_ config: ModuleConfigMessage, validate: Bool) async throws
      -> any SpeechModule
    {
      switch config.kind {
      case .speechTranscriber:
        let requested = try locale(config)
        if validate && !SpeechTranscriber.isAvailable {
          throw Errors.unsupported("SpeechTranscriber is not available on this device.")
        }
        let locale = try await resolve(
          requested, supported: await SpeechTranscriber.supportedLocale(equivalentTo: requested),
          what: "SpeechTranscriber", validate: validate)
        let module: SpeechTranscriber
        if let preset = config.speechPreset {
          module = SpeechTranscriber(locale: locale, preset: speechPreset(preset))
        } else {
          module = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: Set(
              try config.transcriptionOptions.map(speechTranscriptionOption)),
            reportingOptions: Set(try config.reportingOptions.map(speechReportingOption)),
            attributeOptions: Set(config.attributeOptions.map(speechAttributeOption)))
        }
        if validate {
          try await requireInstalled(
            locale, installed: await SpeechTranscriber.installedLocales, module: module)
        }
        return module
      case .dictationTranscriber:
        let requested = try locale(config)
        let locale = try await resolve(
          requested,
          supported: await DictationTranscriber.supportedLocale(equivalentTo: requested),
          what: "DictationTranscriber", validate: validate)
        let module: DictationTranscriber
        if let preset = config.dictationPreset {
          module = DictationTranscriber(locale: locale, preset: dictationPreset(preset))
        } else {
          module = DictationTranscriber(
            locale: locale,
            contentHints: Set(config.contentHints.map(contentHint)),
            transcriptionOptions: Set(
              config.transcriptionOptions.map(dictationTranscriptionOption)),
            reportingOptions: Set(try config.reportingOptions.map(dictationReportingOption)),
            attributeOptions: Set(config.attributeOptions.map(dictationAttributeOption)))
        }
        if validate {
          try await requireInstalled(
            locale, installed: await DictationTranscriber.installedLocales, module: module)
        }
        return module
      case .speechDetector:
        let level: SpeechDetector.SensitivityLevel
        switch config.sensitivityLevel ?? .medium {
        case .low: level = .low
        case .medium: level = .medium
        case .high: level = .high
        }
        return SpeechDetector(
          detectionOptions: .init(sensitivityLevel: level),
          reportResults: config.reportResults ?? true)
      }
    }

    private static func locale(_ config: ModuleConfigMessage) throws -> Locale {
      guard let identifier = config.locale, !identifier.isEmpty else {
        throw Errors.invalidArgument("A transcriber needs a locale.")
      }
      return Locale(identifier: identifier)
    }

    private static func resolve(
      _ requested: Locale, supported: Locale?, what: String, validate: Bool
    ) async throws -> Locale {
      if let supported { return supported }
      if validate { throw Errors.unsupportedLocale(identifier(requested), what) }
      return requested
    }

    private static func requireInstalled(
      _ locale: Locale, installed: [Locale], module: any SpeechModule
    ) async throws {
      let wanted = identifier(locale)
      if installed.contains(where: { identifier($0) == wanted }) { return }
      if await AssetInventory.status(forModules: [module]) == .installed { return }
      throw AppleSpeechPigeonError(
        .assetsNotInstalled,
        "The speech assets for \(wanted) are not installed. Call "
          + "AssetInventory.installAssets first.",
        details: ["locale": wanted])
    }

    /// A BCP 47 identifier ("en-US").
    static func identifier(_ locale: Locale) -> String {
      locale.identifier(.bcp47)
    }

    static func identifiers(_ locales: [Locale]) -> [String] {
      Array(Set(locales.map(identifier))).sorted()
    }

    // MARK: - Options

    static func speechPreset(_ preset: SpeechTranscriberPresetMessage)
      -> SpeechTranscriber.Preset
    {
      switch preset {
      case .transcription: return .transcription
      case .transcriptionWithAlternatives: return .transcriptionWithAlternatives
      case .timeIndexedTranscriptionWithAlternatives:
        return .timeIndexedTranscriptionWithAlternatives
      case .progressiveTranscription: return .progressiveTranscription
      case .timeIndexedProgressiveTranscription: return .timeIndexedProgressiveTranscription
      }
    }

    static func dictationPreset(_ preset: DictationPresetMessage) -> DictationTranscriber.Preset
    {
      switch preset {
      case .phrase: return .phrase
      case .shortDictation: return .shortDictation
      case .progressiveShortDictation: return .progressiveShortDictation
      case .longDictation: return .longDictation
      case .progressiveLongDictation: return .progressiveLongDictation
      case .timeIndexedLongDictation: return .timeIndexedLongDictation
      }
    }

    private static func speechTranscriptionOption(_ option: TranscriptionOptionMessage) throws
      -> SpeechTranscriber.TranscriptionOption
    {
      switch option {
      case .etiquetteReplacements: return .etiquetteReplacements
      case .punctuation, .emoji:
        throw Errors.invalidArgument(
          "SpeechTranscriber only supports the etiquetteReplacements transcription option.")
      }
    }

    private static func dictationTranscriptionOption(_ option: TranscriptionOptionMessage)
      -> DictationTranscriber.TranscriptionOption
    {
      switch option {
      case .punctuation: return .punctuation
      case .emoji: return .emoji
      case .etiquetteReplacements: return .etiquetteReplacements
      }
    }

    private static func speechReportingOption(_ option: ReportingOptionMessage) throws
      -> SpeechTranscriber.ReportingOption
    {
      switch option {
      case .volatileResults: return .volatileResults
      case .alternativeTranscriptions: return .alternativeTranscriptions
      case .fastResults: return .fastResults
      case .frequentFinalization:
        throw Errors.invalidArgument(
          "frequentFinalization is a DictationTranscriber reporting option.")
      }
    }

    private static func dictationReportingOption(_ option: ReportingOptionMessage) throws
      -> DictationTranscriber.ReportingOption
    {
      switch option {
      case .volatileResults: return .volatileResults
      case .alternativeTranscriptions: return .alternativeTranscriptions
      case .frequentFinalization: return .frequentFinalization
      case .fastResults:
        throw Errors.invalidArgument("fastResults is a SpeechTranscriber reporting option.")
      }
    }

    private static func speechAttributeOption(_ option: ResultAttributeOptionMessage)
      -> SpeechTranscriber.ResultAttributeOption
    {
      switch option {
      case .audioTimeRange: return .audioTimeRange
      case .transcriptionConfidence: return .transcriptionConfidence
      }
    }

    private static func dictationAttributeOption(_ option: ResultAttributeOptionMessage)
      -> DictationTranscriber.ResultAttributeOption
    {
      switch option {
      case .audioTimeRange: return .audioTimeRange
      case .transcriptionConfidence: return .transcriptionConfidence
      }
    }

    private static func contentHint(_ hint: ContentHintMessage) -> DictationTranscriber.ContentHint
    {
      switch hint {
      case .shortForm: return .shortForm
      case .farField: return .farField
      case .atypicalSpeech: return .atypicalSpeech
      }
    }

    static func options(_ message: AnalyzerOptionsMessage?) -> SpeechAnalyzer.Options? {
      guard let message else { return nil }
      let priority: TaskPriority
      switch message.priority {
      case .background: priority = .background
      case .utility: priority = .utility
      case .low: priority = .low
      case .medium: priority = .medium
      case .high: priority = .high
      case .userInitiated: priority = .userInitiated
      }
      let retention: SpeechAnalyzer.Options.ModelRetention
      switch message.modelRetention {
      case .whileInUse: retention = .whileInUse
      case .lingering: retention = .lingering
      case .processLifetime: retention = .processLifetime
      }
      if #available(iOS 27.0, macOS 27.0, *), let ignores = message.ignoresResourceLimits {
        return SpeechAnalyzer.Options(
          priority: priority, modelRetention: retention, ignoresResourceLimits: ignores)
      }
      return SpeechAnalyzer.Options(priority: priority, modelRetention: retention)
    }

    static func assetStatus(_ status: AssetInventory.Status) -> AssetStatusMessage {
      switch status {
      case .unsupported: return .unsupported
      case .supported: return .supported
      case .downloading: return .downloading
      case .installed: return .installed
      @unknown default: return .unsupported
      }
    }

    // MARK: - Results

    static func seconds(_ time: CMTime) -> Double? {
      guard time.isNumeric else { return nil }
      return time.seconds
    }

    static func transcriptionResult(
      requestId: Int64, moduleIndex: Int, range: CMTimeRange, finalization: CMTime,
      isFinal: Bool, text: AttributedString, alternatives: [AttributedString]
    ) -> AnalyzerResultMessage {
      AnalyzerResultMessage(
        requestId: requestId, moduleIndex: Int64(moduleIndex),
        rangeStart: seconds(range.start) ?? 0, rangeEnd: seconds(range.end) ?? 0,
        resultsFinalizationTime: seconds(finalization) ?? 0, isFinal: isFinal,
        text: String(text.characters), segments: segments(text),
        alternatives: alternatives.map { String($0.characters) })
    }

    /// One segment per attributed run (one per word when time ranges are
    /// requested), with whitespace trimmed and UTF-16 offsets.
    static func segments(_ text: AttributedString) -> [TranscriptionSegmentMessage] {
      var segments: [TranscriptionSegmentMessage] = []
      var offset = 0
      for run in text.runs {
        let substring = String(text[run.range].characters)
        defer { offset += substring.utf16.count }
        let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { continue }
        let leading = substring.prefix(while: { $0.isWhitespace || $0.isNewline })
        let timeRange = run.audioTimeRange
        segments.append(
          TranscriptionSegmentMessage(
            text: trimmed, start: Int64(offset + String(leading).utf16.count),
            length: Int64(trimmed.utf16.count),
            startTime: timeRange.flatMap { seconds($0.start) },
            endTime: timeRange.flatMap { seconds($0.end) },
            confidence: run.transcriptionConfidence, alternatives: []))
      }
      return segments
    }
  }
#endif
