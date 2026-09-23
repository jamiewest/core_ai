#if canImport(Vision)
  import CoreGraphics
  import Foundation
  import Vision

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Runs Vision's still-image requests on behalf of Dart.
  @available(iOS 27.0, macOS 27.0, *)
  final class AppleVisionHostApiImpl: AppleVisionHostApi {
    func perform(
      image: ImageInputMessage, orientation: ImageOrientationMessage?, requests: [RequestMessage]
    ) async throws -> AnalysisMessage {
      let cgImage = try ImageBridge.cgImage(image)
      let cgOrientation = ImageBridge.orientation(orientation)
      let size = ImageBridge.size(of: cgImage, orientation: cgOrientation)
      let handler = ImageRequestHandler(cgImage, orientation: cgOrientation)
      var results: [RequestResultMessage] = []
      results.reserveCapacity(requests.count)
      for request in requests {
        do {
          results.append(try await run(request, on: handler))
        } catch {
          results.append(
            RequestResultMessage(kind: request.kind, error: Errors.message(Errors.translate(error)))
          )
        }
      }
      return AnalysisMessage(imageSize: size, results: results)
    }

    func imageSize(
      image: ImageInputMessage, orientation: ImageOrientationMessage?
    ) async throws -> ImageSizeMessage {
      let cgImage = try ImageBridge.cgImage(image)
      return ImageBridge.size(of: cgImage, orientation: ImageBridge.orientation(orientation))
    }

    func supportedRecognitionLanguages(level: RecognitionLevelMessage) throws -> [String] {
      var request = RecognizeTextRequest()
      request.recognitionLevel = level == .fast ? .fast : .accurate
      return request.supportedRecognitionLanguages.map(\.maximalIdentifier)
    }

    func supportedBarcodeSymbologies() throws -> [BarcodeSymbologyMessage] {
      DetectBarcodesRequest().supportedSymbologies.map { ObservationBridge.symbology($0) }
    }

    func supportedClassificationIdentifiers() throws -> [String] {
      ClassifyImageRequest().supportedIdentifiers
    }

    func encodeMaskAsPng(mask: MaskImageMessage) async throws -> FlutterStandardTypedData {
      FlutterStandardTypedData(bytes: try ImageBridge.png(mask))
    }

    func featurePrintDistance(tokenA: String, tokenB: String) async throws -> Double {
      let decoder = JSONDecoder()
      let a = try decode(tokenA, with: decoder, label: "tokenA")
      let b = try decode(tokenB, with: decoder, label: "tokenB")
      return try translatingErrors { try a.distance(to: b) }
    }

    private func decode(
      _ token: String, with decoder: JSONDecoder, label: String
    ) throws -> FeaturePrintObservation {
      do {
        return try decoder.decode(FeaturePrintObservation.self, from: Data(token.utf8))
      } catch {
        throw Errors.invalidArgument(
          "\(label) is not a feature-print token produced by this plugin.")
      }
    }

    // MARK: - Running one request

    private func run(
      _ message: RequestMessage, on handler: ImageRequestHandler
    ) async throws -> RequestResultMessage {
      try await translatingErrors {
        switch message.kind {
        case .recognizeText:
          return try await self.recognizeText(message, handler)
        case .recognizeDocuments:
          return try await self.recognizeDocuments(message, handler)
        case .detectTextRectangles:
          var request = DetectTextRectanglesRequest()
          request.reportCharacterBoxes = message.reportCharacterBoxes ?? false
          self.applyRegion(message, to: &request)
          let observations = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind,
            textRectangles: observations.map { ObservationBridge.textRectangle($0) })
        case .detectBarcodes:
          return try await self.detectBarcodes(message, handler)
        case .detectFaceRectangles:
          var request = DetectFaceRectanglesRequest()
          self.applyRegion(message, to: &request)
          let observations = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, faces: observations.map { ObservationBridge.face($0) })
        case .detectFaceLandmarks:
          var request = DetectFaceLandmarksRequest()
          self.applyRegion(message, to: &request)
          let observations = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, faces: observations.map { ObservationBridge.face($0) })
        case .detectFaceCaptureQuality:
          var request = DetectFaceCaptureQualityRequest()
          self.applyRegion(message, to: &request)
          let observations = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, faces: observations.map { ObservationBridge.face($0) })
        case .detectHumanRectangles:
          var request = DetectHumanRectanglesRequest()
          request.upperBodyOnly = message.upperBodyOnly ?? request.upperBodyOnly
          self.applyRegion(message, to: &request)
          let observations = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, humans: observations.map { ObservationBridge.human($0) })
        case .detectHumanBodyPose:
          var request = DetectHumanBodyPoseRequest()
          request.detectsHands = message.detectsHands ?? request.detectsHands
          self.applyRegion(message, to: &request)
          let observations = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, bodyPoses: observations.map { ObservationBridge.bodyPose($0) })
        case .detectHumanHandPose:
          var request = DetectHumanHandPoseRequest()
          if let count = message.maximumHandCount { request.maximumHandCount = Int(count) }
          self.applyRegion(message, to: &request)
          let observations = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, poses: observations.map { ObservationBridge.handPose($0) })
        case .detectAnimalBodyPose:
          var request = DetectAnimalBodyPoseRequest()
          self.applyRegion(message, to: &request)
          let observations = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, poses: observations.map { ObservationBridge.animalPose($0) })
        case .recognizeAnimals:
          var request = RecognizeAnimalsRequest()
          self.applyRegion(message, to: &request)
          let observations = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, objects: observations.map { ObservationBridge.object($0) })
        case .classifyImage:
          var request = ClassifyImageRequest()
          if let action = message.cropAndScaleAction {
            request.cropAndScaleAction = self.action(action)
          }
          self.applyRegion(message, to: &request)
          let observations = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind,
            classifications: observations.map { ObservationBridge.classification($0) })
        case .calculateImageAestheticsScores:
          var request = CalculateImageAestheticsScoresRequest()
          if let action = message.cropAndScaleAction {
            request.cropAndScaleAction = self.action(action)
          }
          self.applyRegion(message, to: &request)
          let observation = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, aesthetics: ObservationBridge.aesthetics(observation))
        case .generateAttentionBasedSaliencyImage:
          var request = GenerateAttentionBasedSaliencyImageRequest()
          self.applyRegion(message, to: &request)
          let observation = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, saliency: try ObservationBridge.saliency(observation))
        case .generateObjectnessBasedSaliencyImage:
          var request = GenerateObjectnessBasedSaliencyImageRequest()
          self.applyRegion(message, to: &request)
          let observation = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, saliency: try ObservationBridge.saliency(observation))
        case .generatePersonSegmentation:
          let request = GeneratePersonSegmentationRequest()
          switch message.segmentationQuality {
          case .accurate: request.qualityLevel = .accurate
          case .balanced: request.qualityLevel = .balanced
          case .fast: request.qualityLevel = .fast
          case .none: break
          }
          if let region = self.region(message) { request.regionOfInterest = region }
          let observation = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, mask: try ObservationBridge.mask(observation))
        case .generatePersonInstanceMask:
          var request = GeneratePersonInstanceMaskRequest()
          self.applyRegion(message, to: &request)
          let observation = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind,
            instanceMask: try observation.map {
              try ObservationBridge.instanceMask(
                $0, scaledTo: (message.scaleMaskToImage ?? false) ? handler : nil)
            })
        case .generateForegroundInstanceMask:
          var request = GenerateForegroundInstanceMaskRequest()
          self.applyRegion(message, to: &request)
          let observation = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind,
            instanceMask: try observation.map {
              try ObservationBridge.instanceMask(
                $0, scaledTo: (message.scaleMaskToImage ?? false) ? handler : nil)
            })
        case .detectDocumentSegmentation:
          var request = DetectDocumentSegmentationRequest()
          self.applyRegion(message, to: &request)
          let observation = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind,
            documentSegmentation: try observation.map {
              try ObservationBridge.documentSegmentation(
                $0, includeMask: message.includeMask ?? false)
            })
        case .detectRectangles:
          return try await self.detectRectangles(message, handler)
        case .detectHorizon:
          var request = DetectHorizonRequest()
          self.applyRegion(message, to: &request)
          let observation = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, horizon: observation.map { ObservationBridge.horizon($0) })
        case .detectContours:
          return try await self.detectContours(message, handler)
        case .detectLensSmudge:
          var request = DetectLensSmudgeRequest()
          self.applyRegion(message, to: &request)
          let observation = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind,
            smudge: SmudgeMessage(confidence: Double(observation.confidence)))
        case .generateImageFeaturePrint:
          var request = GenerateImageFeaturePrintRequest()
          if let action = message.cropAndScaleAction {
            request.cropAndScaleAction = self.action(action)
          }
          self.applyRegion(message, to: &request)
          let observation = try await handler.perform(request)
          return RequestResultMessage(
            kind: message.kind, featurePrint: try ObservationBridge.featurePrint(observation))
        }
      }
    }

    // MARK: - Requests with more options

    private func recognizeText(
      _ message: RequestMessage, _ handler: ImageRequestHandler
    ) async throws -> RequestResultMessage {
      var request = RecognizeTextRequest()
      if let level = message.recognitionLevel {
        request.recognitionLevel = level == .fast ? .fast : .accurate
      }
      if let languages = message.recognitionLanguages, !languages.isEmpty {
        request.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
      }
      if let words = message.customWords { request.customWords = words }
      if let correction = message.usesLanguageCorrection {
        request.usesLanguageCorrection = correction
      }
      if let automatic = message.automaticallyDetectsLanguage {
        request.automaticallyDetectsLanguage = automatic
      }
      if let minimum = message.minimumTextHeightFraction {
        request.minimumTextHeightFraction = Float(minimum)
      }
      applyRegion(message, to: &request)
      let observations = try await handler.perform(request)
      let candidates = Int(message.maximumCandidateCount ?? 1)
      return RequestResultMessage(
        kind: message.kind,
        recognizedText: observations.map {
          ObservationBridge.text($0, maximumCandidateCount: candidates)
        })
    }

    private func recognizeDocuments(
      _ message: RequestMessage, _ handler: ImageRequestHandler
    ) async throws -> RequestResultMessage {
      var request = RecognizeDocumentsRequest()
      var text = request.textRecognitionOptions
      if let languages = message.recognitionLanguages, !languages.isEmpty {
        text.recognitionLanguages = languages.map { Locale.Language(identifier: $0) }
      }
      if let words = message.customWords { text.customWords = words }
      if let correction = message.usesLanguageCorrection { text.useLanguageCorrection = correction }
      if let automatic = message.automaticallyDetectsLanguage {
        text.automaticallyDetectLanguage = automatic
      }
      if let minimum = message.minimumTextHeightFraction {
        text.minimumTextHeightFraction = Float(minimum)
      }
      if let count = message.maximumCandidateCount { text.maximumCandidateCount = Int(count) }
      request.textRecognitionOptions = text
      var barcodes = request.barcodeDetectionOptions
      if let enabled = message.detectsBarcodesInDocuments { barcodes.enabled = enabled }
      if let symbologies = message.symbologies, !symbologies.isEmpty {
        barcodes.symbologies = symbologies.map { ObservationBridge.symbology($0) }
      }
      if let coalesce = message.coalescesCompositeSymbologies {
        barcodes.coalesceCompositeSymbologies = coalesce
      }
      request.barcodeDetectionOptions = barcodes
      applyRegion(message, to: &request)
      let observations = try await handler.perform(request)
      return RequestResultMessage(
        kind: message.kind, documents: observations.map { ObservationBridge.document($0) })
    }

    private func detectBarcodes(
      _ message: RequestMessage, _ handler: ImageRequestHandler
    ) async throws -> RequestResultMessage {
      var request = DetectBarcodesRequest()
      if let symbologies = message.symbologies, !symbologies.isEmpty {
        request.symbologies = symbologies.map { ObservationBridge.symbology($0) }
      }
      if let coalesce = message.coalescesCompositeSymbologies {
        request.coalescesCompositeSymbologies = coalesce
      }
      applyRegion(message, to: &request)
      let observations = try await handler.perform(request)
      return RequestResultMessage(
        kind: message.kind, barcodes: observations.map { ObservationBridge.barcode($0) })
    }

    private func detectRectangles(
      _ message: RequestMessage, _ handler: ImageRequestHandler
    ) async throws -> RequestResultMessage {
      var request = DetectRectanglesRequest()
      if let value = message.minimumAspectRatio { request.minimumAspectRatio = Float(value) }
      if let value = message.maximumAspectRatio { request.maximumAspectRatio = Float(value) }
      if let value = message.quadratureToleranceDegrees {
        request.quadratureToleranceDegrees = Float(value)
      }
      if let value = message.minimumSize { request.minimumSize = Float(value) }
      if let value = message.minimumConfidence { request.minimumConfidence = Float(value) }
      if let value = message.maximumObservations { request.maximumObservations = Int(value) }
      applyRegion(message, to: &request)
      let observations = try await handler.perform(request)
      return RequestResultMessage(
        kind: message.kind,
        rectangles: observations.map { ObservationBridge.quad($0) })
    }

    private func detectContours(
      _ message: RequestMessage, _ handler: ImageRequestHandler
    ) async throws -> RequestResultMessage {
      var request = DetectContoursRequest()
      if let value = message.contrastAdjustment { request.contrastAdjustment = Float(value) }
      if let value = message.contrastPivot { request.contrastPivot = Float(value) }
      if let value = message.detectsDarkOnLight { request.detectsDarkOnLight = value }
      if let value = message.maximumImageDimension {
        request.maximumImageDimension = Int(value)
      }
      applyRegion(message, to: &request)
      let observation = try await handler.perform(request)
      return RequestResultMessage(
        kind: message.kind,
        contours: ObservationBridge.contours(
          observation, includePoints: message.includeContourPoints ?? false))
    }

    // MARK: - Helpers

    private func region(_ message: RequestMessage) -> NormalizedRect? {
      guard let roi = message.regionOfInterest else { return nil }
      return NormalizedRect(x: roi.x, y: roi.y, width: roi.width, height: roi.height)
    }

    private func applyRegion<T: ImageProcessingRequest>(
      _ message: RequestMessage, to request: inout T
    ) {
      if let region = region(message) { request.regionOfInterest = region }
    }

    private func action(_ value: CropAndScaleActionMessage) -> ImageCropAndScaleAction {
      switch value {
      case .centerCrop: return .centerCrop
      case .scaleToFit: return .scaleToFit
      case .scaleToFill: return .scaleToFill
      case .scaleToFitPlus90CcwRotation: return .scaleToFitPlus90CCWRotation
      case .scaleToFillPlus90CcwRotation: return .scaleToFillPlus90CCWRotation
      }
    }
  }
#endif
