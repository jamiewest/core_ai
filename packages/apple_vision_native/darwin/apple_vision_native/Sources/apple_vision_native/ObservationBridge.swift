#if canImport(Vision)
  import CoreGraphics
  import Foundation
  import Vision

  #if os(iOS)
    import Flutter
  #elseif os(macOS)
    import FlutterMacOS
  #endif

  /// Converts Vision observations into their wire form.
  ///
  /// All geometry stays in Vision's normalized space: the origin is the
  /// lower-left corner of the image and y grows upwards.
  @available(iOS 27.0, macOS 27.0, *)
  enum ObservationBridge {
    // MARK: - Geometry

    static func point(_ point: NormalizedPoint) -> NormalizedPointMessage {
      NormalizedPointMessage(x: Double(point.x), y: Double(point.y))
    }

    static func rect(_ rect: NormalizedRect) -> NormalizedRectMessage {
      NormalizedRectMessage(
        x: Double(rect.cgRect.origin.x), y: Double(rect.cgRect.origin.y),
        width: Double(rect.width), height: Double(rect.height))
    }

    static func quad(_ value: some QuadrilateralProviding, confidence: Float)
      -> QuadrilateralMessage
    {
      QuadrilateralMessage(
        topLeft: point(value.topLeft), topRight: point(value.topRight),
        bottomRight: point(value.bottomRight), bottomLeft: point(value.bottomLeft),
        boundingBox: rect(value.boundingBox), confidence: Double(confidence))
    }

    static func quad(_ observation: RectangleObservation) -> QuadrilateralMessage {
      quad(observation, confidence: observation.confidence)
    }

    // MARK: - Text

    static func text(
      _ observation: RecognizedTextObservation, maximumCandidateCount: Int
    ) -> RecognizedTextObservationMessage {
      let candidates = observation.topCandidates(max(1, maximumCandidateCount))
      return RecognizedTextObservationMessage(
        quad: quad(observation, confidence: observation.confidence),
        candidates: candidates.map {
          TextCandidateMessage(text: $0.string, confidence: Double($0.confidence))
        },
        transcript: observation.transcript,
        isTitle: observation.isTitle,
        recognitionLanguages: observation.recognitionLanguages.map(\.maximalIdentifier),
        textDirection: direction(observation.textDirection))
    }

    static func direction(_ value: RecognizedTextObservation.Direction?) -> TextDirectionMessage? {
      switch value {
      case .leftToRight: return .leftToRight
      case .rightToLeft: return .rightToLeft
      case .topToBottom: return .topToBottom
      default: return nil
      }
    }

    static func textRectangle(_ observation: TextObservation) -> TextObservationMessage {
      TextObservationMessage(
        quad: quad(observation, confidence: observation.confidence),
        characterBoxes: observation.characterBoxes?.map { quad($0) })
    }

    // MARK: - Barcodes

    static func barcode(_ observation: BarcodeObservation) -> BarcodeObservationMessage {
      BarcodeObservationMessage(
        quad: quad(observation, confidence: observation.confidence),
        symbology: symbology(observation.symbology),
        payload: observation.payloadString,
        payloadData: observation.payloadData.map { FlutterStandardTypedData(bytes: $0) },
        supplementalPayload: observation.supplementalPayloadString,
        supplementalCompositeType: composite(observation.supplementalCompositeType),
        isGs1DataCarrier: observation.isGS1DataCarrier,
        isColorInverted: observation.isColorInverted)
    }

    static func composite(
      _ value: BarcodeObservation.CompositeType?
    ) -> BarcodeCompositeTypeMessage? {
      switch value {
      case .gs1TypeA: return .gs1TypeA
      case .gs1TypeB: return .gs1TypeB
      case .gs1TypeC: return .gs1TypeC
      case .linked: return .linked
      default: return nil
      }
    }

    static func symbology(_ value: BarcodeSymbology) -> BarcodeSymbologyMessage {
      switch value {
      case .aztec: return .aztec
      case .code39: return .code39
      case .code39Checksum: return .code39Checksum
      case .code39FullASCII: return .code39FullAscii
      case .code39FullASCIIChecksum: return .code39FullAsciiChecksum
      case .code93: return .code93
      case .code93i: return .code93i
      case .code128: return .code128
      case .dataMatrix: return .dataMatrix
      case .ean8: return .ean8
      case .ean13: return .ean13
      case .i2of5: return .i2of5
      case .i2of5Checksum: return .i2of5Checksum
      case .itf14: return .itf14
      case .pdf417: return .pdf417
      case .qr: return .qr
      case .upce: return .upce
      case .codabar: return .codabar
      case .gs1DataBar: return .gs1DataBar
      case .gs1DataBarExpanded: return .gs1DataBarExpanded
      case .gs1DataBarLimited: return .gs1DataBarLimited
      case .microPDF417: return .microPdf417
      case .microQR: return .microQr
      case .msiPlessey: return .msiPlessey
      @unknown default: return .qr
      }
    }

    static func symbology(_ value: BarcodeSymbologyMessage) -> BarcodeSymbology {
      switch value {
      case .aztec: return .aztec
      case .code39: return .code39
      case .code39Checksum: return .code39Checksum
      case .code39FullAscii: return .code39FullASCII
      case .code39FullAsciiChecksum: return .code39FullASCIIChecksum
      case .code93: return .code93
      case .code93i: return .code93i
      case .code128: return .code128
      case .dataMatrix: return .dataMatrix
      case .ean8: return .ean8
      case .ean13: return .ean13
      case .i2of5: return .i2of5
      case .i2of5Checksum: return .i2of5Checksum
      case .itf14: return .itf14
      case .pdf417: return .pdf417
      case .qr: return .qr
      case .upce: return .upce
      case .codabar: return .codabar
      case .gs1DataBar: return .gs1DataBar
      case .gs1DataBarExpanded: return .gs1DataBarExpanded
      case .gs1DataBarLimited: return .gs1DataBarLimited
      case .microPdf417: return .microPDF417
      case .microQr: return .microQR
      case .msiPlessey: return .msiPlessey
      }
    }

    // MARK: - Faces and people

    static func face(_ observation: FaceObservation) -> FaceObservationMessage {
      FaceObservationMessage(
        boundingBox: rect(observation.boundingBox),
        confidence: Double(observation.confidence),
        rollDegrees: observation.roll.converted(to: .degrees).value,
        yawDegrees: observation.yaw.converted(to: .degrees).value,
        pitchDegrees: observation.pitch.converted(to: .degrees).value,
        captureQuality: observation.captureQuality.map { Double($0.score) },
        landmarks: landmarks(observation.landmarks))
    }

    static func landmarks(_ value: FaceObservation.Landmarks2D?) -> [LandmarkRegionMessage] {
      guard let value else { return [] }
      let regions: [(String, FaceObservation.Landmarks2D.Region)] = [
        ("allPoints", value.allPoints),
        ("faceContour", value.faceContour),
        ("leftEye", value.leftEye),
        ("rightEye", value.rightEye),
        ("leftEyebrow", value.leftEyebrow),
        ("rightEyebrow", value.rightEyebrow),
        ("nose", value.nose),
        ("noseCrest", value.noseCrest),
        ("medianLine", value.medianLine),
        ("outerLips", value.outerLips),
        ("innerLips", value.innerLips),
        ("leftPupil", value.leftPupil),
        ("rightPupil", value.rightPupil),
      ]
      return regions.compactMap { name, region in
        guard !region.points.isEmpty else { return nil }
        return LandmarkRegionMessage(
          name: name,
          pointsClassification: classification(region.pointsClassification),
          points: region.points.map { point($0) },
          precisionEstimates: region.precisionEstimatesPerPoint.map { $0.map(Double.init) })
      }
    }

    static func classification(
      _ value: FaceObservation.Landmarks2D.Region.PointsClassification
    ) -> PointsClassificationMessage {
      switch value {
      case .closedPath: return .closedPath
      case .disconnected: return .disconnected
      case .openPath: return .openPath
      @unknown default: return .disconnected
      }
    }

    static func human(_ observation: HumanObservation) -> HumanObservationMessage {
      HumanObservationMessage(
        boundingBox: rect(observation.boundingBox),
        confidence: Double(observation.confidence),
        isUpperBodyOnly: observation.isUpperBodyOnly)
    }

    // MARK: - Poses

    static func joints(_ values: [some Any: Joint]) -> [JointMessage] {
      values.values
        .map { JointMessage(name: $0.jointName, location: point($0.location)) }
        .sorted { $0.name < $1.name }
    }

    static func bodyPose(_ observation: HumanBodyPoseObservation) -> BodyPoseObservationMessage {
      BodyPoseObservationMessage(
        confidence: Double(observation.confidence),
        joints: joints(observation.allJoints()),
        leftHand: observation.leftHand.map { handPose($0) },
        rightHand: observation.rightHand.map { handPose($0) })
    }

    static func handPose(_ observation: HumanHandPoseObservation) -> PoseObservationMessage {
      PoseObservationMessage(
        confidence: Double(observation.confidence),
        joints: joints(observation.allJoints()),
        chirality: {
          switch observation.chirality {
          case .left: return .left
          case .right: return .right
          default: return nil
          }
        }())
    }

    static func animalPose(_ observation: AnimalBodyPoseObservation) -> PoseObservationMessage {
      PoseObservationMessage(
        confidence: Double(observation.confidence),
        joints: joints(observation.allJoints()),
        chirality: nil)
    }

    // MARK: - Classification

    static func classification(
      _ observation: ClassificationObservation
    ) -> ClassificationMessage {
      ClassificationMessage(
        identifier: observation.identifier,
        confidence: Double(observation.confidence),
        hasPrecisionRecallCurve: observation.hasPrecisionRecallCurve)
    }

    static func object(_ observation: RecognizedObjectObservation) -> RecognizedObjectMessage {
      RecognizedObjectMessage(
        boundingBox: rect(observation.boundingBox),
        confidence: Double(observation.confidence),
        labels: observation.labels.map { classification($0) })
    }

    static func aesthetics(
      _ observation: ImageAestheticsScoresObservation
    ) -> AestheticsScoresMessage {
      AestheticsScoresMessage(
        overallScore: Double(observation.overallScore),
        isUtility: observation.isUtility,
        confidence: Double(observation.confidence))
    }

    // MARK: - Masks

    static func mask(_ observation: PixelBufferObservation) throws -> MaskImageMessage {
      try observation.pixelBuffer.withUnsafeBuffer { try ImageBridge.mask($0) }
    }

    static func saliency(_ observation: SaliencyImageObservation) throws -> SaliencyMessage {
      SaliencyMessage(
        salientObjects: observation.salientObjects.map { quad($0) },
        heatMap: try mask(observation.heatMap),
        confidence: Double(observation.confidence))
    }

    static func instanceMask(
      _ observation: InstanceMaskObservation, scaledTo handler: ImageRequestHandler?
    ) throws -> InstanceMaskMessage {
      let mask: MaskImageMessage
      if let handler {
        mask = try ImageBridge.mask(
          observation.generateScaledMask(
            for: observation.allInstances, scaledToImageFrom: handler))
      } else {
        mask = try self.mask(observation.allInstancesMask)
      }
      return InstanceMaskMessage(
        instances: observation.allInstances.map(Int64.init),
        mask: mask,
        confidence: Double(observation.confidence))
    }

    static func documentSegmentation(
      _ observation: DetectedDocumentObservation, includeMask: Bool
    ) throws -> DocumentSegmentationMessage {
      DocumentSegmentationMessage(
        quad: quad(observation, confidence: observation.confidence),
        mask: includeMask ? try mask(observation.globalSegmentationMask) : nil)
    }

    // MARK: - Horizon, contours, feature prints

    static func horizon(_ observation: HorizonObservation) -> HorizonMessage {
      let t = observation.transform
      return HorizonMessage(
        angleDegrees: observation.angle.converted(to: .degrees).value,
        confidence: Double(observation.confidence),
        transform: [t.a, t.b, t.c, t.d, t.tx, t.ty].map(Double.init))
    }

    static func contours(
      _ observation: ContoursObservation, includePoints: Bool
    ) -> ContoursMessage {
      var messages: [ContourMessage] = []
      func visit(_ contour: ContoursObservation.Contour) {
        messages.append(self.contour(contour, includePoints: includePoints))
        for child in contour.childContours { visit(child) }
      }
      for contour in observation.topLevelContours { visit(contour) }
      return ContoursMessage(
        contourCount: Int64(observation.contourCount),
        confidence: Double(observation.confidence),
        contours: messages)
    }

    static func contour(
      _ contour: ContoursObservation.Contour, includePoints: Bool
    ) -> ContourMessage {
      var points: FlutterStandardTypedData?
      if includePoints {
        var flat: [Double] = []
        flat.reserveCapacity(contour.pointCount * 2)
        for point in contour.normalizedPoints {
          flat.append(Double(point.x))
          flat.append(Double(point.y))
        }
        points = FlutterStandardTypedData(float64: Data(bytes: flat, count: flat.count * 8))
      }
      return ContourMessage(
        indexPath: contour.indexPath.map(Int64.init),
        aspectRatio: Double(contour.aspectRatio),
        area: contour.calculateArea(),
        perimeter: contour.calculatePerimeter(),
        boundingBox: rect(contour.boundingBox),
        pointCount: Int64(contour.pointCount),
        childCount: Int64(contour.childContours.count),
        points: points)
    }

    static func featurePrint(_ observation: FeaturePrintObservation) throws -> FeaturePrintMessage {
      let token = try JSONEncoder().encode(observation)
      return FeaturePrintMessage(
        elementCount: Int64(observation.elementCount),
        isDouble: observation.elementType == .double,
        data: FlutterStandardTypedData(bytes: observation.data),
        token: String(decoding: token, as: UTF8.self),
        confidence: Double(observation.confidence))
    }

    // MARK: - Documents

    static func document(_ observation: DocumentObservation) -> DocumentObservationMessage {
      let container = observation.document
      return DocumentObservationMessage(
        transcript: container.text.transcript,
        title: container.title?.transcript,
        paragraphs: container.paragraphs.map { documentText($0) },
        barcodes: container.barcodes.map { barcode($0) },
        tables: container.tables.map { table($0) },
        lists: container.lists.map { list($0) },
        confidence: Double(observation.confidence))
    }

    static func documentText(
      _ value: DocumentObservation.Container.Text
    ) -> DocumentTextMessage {
      DocumentTextMessage(
        transcript: value.transcript,
        lines: value.lines.map { text($0, maximumCandidateCount: 1) },
        alignment: {
          switch value.textAlignment {
          case .center: return .center
          case .leading: return .leading
          case .trailing: return .trailing
          default: return nil
          }
        }())
    }

    static func table(_ value: DocumentObservation.Container.Table) -> DocumentTableMessage {
      let rows = value.rows
      let cells = rows.flatMap { $0 }.map { cell in
        DocumentTableCellMessage(
          rowStart: Int64(cell.rowRange.lowerBound),
          rowEnd: Int64(cell.rowRange.upperBound),
          columnStart: Int64(cell.columnRange.lowerBound),
          columnEnd: Int64(cell.columnRange.upperBound),
          text: cell.content.text.transcript)
      }
      return DocumentTableMessage(
        rowCount: Int64(rows.count),
        columnCount: Int64(value.columns.count),
        cells: cells)
    }

    static func list(_ value: DocumentObservation.Container.List) -> DocumentListMessage {
      DocumentListMessage(
        items: value.items.map { item in
          DocumentListItemMessage(
            markerType: marker(item.markerType),
            markerText: item.markerString,
            itemText: item.itemString)
        })
    }

    static func marker(
      _ value: DocumentObservation.Container.List.Marker?
    ) -> ListMarkerMessage? {
      switch value {
      case .bullet: return .bullet
      case .hyphen: return .hyphen
      case .lowercaseLatin: return .lowercaseLatin
      case .uppercaseLatin: return .uppercaseLatin
      case .decimal: return .decimal
      case .decorativeDecimal: return .decorativeDecimal
      case .compositeDecimal: return .compositeDecimal
      default: return nil
      }
    }
  }
#endif
