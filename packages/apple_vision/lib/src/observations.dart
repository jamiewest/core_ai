part of 'vision.dart';

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

/// One interpretation of a recognized line of text.
@immutable
final class TextCandidate {
  /// Creates a candidate.
  const TextCandidate({required this.text, required this.confidence});

  TextCandidate._(TextCandidateMessage message)
    : text = message.text,
      confidence = message.confidence;

  /// The recognized characters.
  final String text;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  @override
  String toString() => 'TextCandidate($text, confidence: $confidence)';
}

/// How a line of text runs.
enum TextDirection {
  /// Left to right, for example Latin scripts.
  leftToRight,

  /// Right to left, for example Arabic and Hebrew.
  rightToLeft,

  /// Top to bottom, for vertical Asian scripts.
  topToBottom,
}

/// A line of recognized text, from `RecognizeTextRequest`.
@immutable
final class RecognizedTextObservation {
  RecognizedTextObservation._(RecognizedTextObservationMessage message)
    : quad = NormalizedQuad._(message.quad),
      candidates = message.candidates
          .map(TextCandidate._)
          .toList(growable: false),
      transcript = message.transcript,
      isTitle = message.isTitle,
      recognitionLanguages = List.unmodifiable(message.recognitionLanguages),
      textDirection = switch (message.textDirection) {
        TextDirectionMessage.leftToRight => TextDirection.leftToRight,
        TextDirectionMessage.rightToLeft => TextDirection.rightToLeft,
        TextDirectionMessage.topToBottom => TextDirection.topToBottom,
        null => null,
      };

  /// Where the line sits in the image.
  final NormalizedQuad quad;

  /// The interpretations Vision considered, best first.
  ///
  /// Ask for more than one with `RecognizeTextRequest.maximumCandidateCount`.
  final List<TextCandidate> candidates;

  /// Vision's own transcript of the line.
  final String transcript;

  /// Whether Vision considers this line a title.
  final bool isTitle;

  /// The BCP-47 identifiers of the languages Vision recognized.
  final List<String> recognitionLanguages;

  /// Which way the line runs, when Vision could tell.
  final TextDirection? textDirection;

  /// The best interpretation's text.
  String get text => candidates.isEmpty ? transcript : candidates.first.text;

  /// The best interpretation's confidence, or the observation's own.
  double get confidence =>
      candidates.isEmpty ? quad.confidence : candidates.first.confidence;

  @override
  String toString() => 'RecognizedTextObservation($text)';
}

/// A region that holds text, from `DetectTextRectanglesRequest`.
@immutable
final class TextRectangleObservation {
  TextRectangleObservation._(TextObservationMessage message)
    : quad = NormalizedQuad._(message.quad),
      characterBoxes = message.characterBoxes
          ?.map(NormalizedQuad._)
          .toList(growable: false);

  /// Where the text sits in the image.
  final NormalizedQuad quad;

  /// One box per character, when the request asked for them.
  final List<NormalizedQuad>? characterBoxes;

  @override
  String toString() => 'TextRectangleObservation(${quad.boundingBox})';
}

// ---------------------------------------------------------------------------
// Barcodes
// ---------------------------------------------------------------------------

/// A barcode symbology Vision can detect.
enum BarcodeSymbology {
  /// Aztec.
  aztec(BarcodeSymbologyMessage.aztec),

  /// Code 39.
  code39(BarcodeSymbologyMessage.code39),

  /// Code 39 with a checksum.
  code39Checksum(BarcodeSymbologyMessage.code39Checksum),

  /// Code 39, full ASCII.
  code39FullAscii(BarcodeSymbologyMessage.code39FullAscii),

  /// Code 39, full ASCII, with a checksum.
  code39FullAsciiChecksum(BarcodeSymbologyMessage.code39FullAsciiChecksum),

  /// Code 93.
  code93(BarcodeSymbologyMessage.code93),

  /// Code 93i.
  code93i(BarcodeSymbologyMessage.code93i),

  /// Code 128.
  code128(BarcodeSymbologyMessage.code128),

  /// Data Matrix.
  dataMatrix(BarcodeSymbologyMessage.dataMatrix),

  /// EAN-8.
  ean8(BarcodeSymbologyMessage.ean8),

  /// EAN-13.
  ean13(BarcodeSymbologyMessage.ean13),

  /// Interleaved 2 of 5.
  i2of5(BarcodeSymbologyMessage.i2of5),

  /// Interleaved 2 of 5 with a checksum.
  i2of5Checksum(BarcodeSymbologyMessage.i2of5Checksum),

  /// ITF-14.
  itf14(BarcodeSymbologyMessage.itf14),

  /// PDF417.
  pdf417(BarcodeSymbologyMessage.pdf417),

  /// QR code.
  qr(BarcodeSymbologyMessage.qr),

  /// UPC-E.
  upce(BarcodeSymbologyMessage.upce),

  /// Codabar.
  codabar(BarcodeSymbologyMessage.codabar),

  /// GS1 DataBar.
  gs1DataBar(BarcodeSymbologyMessage.gs1DataBar),

  /// GS1 DataBar Expanded.
  gs1DataBarExpanded(BarcodeSymbologyMessage.gs1DataBarExpanded),

  /// GS1 DataBar Limited.
  gs1DataBarLimited(BarcodeSymbologyMessage.gs1DataBarLimited),

  /// MicroPDF417.
  microPdf417(BarcodeSymbologyMessage.microPdf417),

  /// Micro QR code.
  microQr(BarcodeSymbologyMessage.microQr),

  /// MSI Plessey.
  msiPlessey(BarcodeSymbologyMessage.msiPlessey);

  const BarcodeSymbology(this._message);

  final BarcodeSymbologyMessage _message;

  static BarcodeSymbology _from(BarcodeSymbologyMessage message) =>
      values.firstWhere((value) => value._message == message);
}

/// How a composite barcode's parts relate.
enum BarcodeCompositeType {
  /// GS1 composite type A.
  gs1TypeA,

  /// GS1 composite type B.
  gs1TypeB,

  /// GS1 composite type C.
  gs1TypeC,

  /// A linked symbology.
  linked,
}

/// A detected barcode.
@immutable
final class BarcodeObservation {
  BarcodeObservation._(BarcodeObservationMessage message)
    : quad = NormalizedQuad._(message.quad),
      symbology = BarcodeSymbology._from(message.symbology),
      payload = message.payload,
      payloadData = message.payloadData,
      supplementalPayload = message.supplementalPayload,
      supplementalCompositeType = switch (message.supplementalCompositeType) {
        BarcodeCompositeTypeMessage.gs1TypeA => BarcodeCompositeType.gs1TypeA,
        BarcodeCompositeTypeMessage.gs1TypeB => BarcodeCompositeType.gs1TypeB,
        BarcodeCompositeTypeMessage.gs1TypeC => BarcodeCompositeType.gs1TypeC,
        BarcodeCompositeTypeMessage.linked => BarcodeCompositeType.linked,
        null => null,
      },
      isGs1DataCarrier = message.isGs1DataCarrier,
      isColorInverted = message.isColorInverted;

  /// Where the barcode sits in the image.
  final NormalizedQuad quad;

  /// The symbology Vision decoded.
  final BarcodeSymbology symbology;

  /// The decoded payload, when it is text.
  final String? payload;

  /// The decoded payload as bytes, when Vision provides it.
  final Uint8List? payloadData;

  /// The payload of a composite barcode's second part.
  final String? supplementalPayload;

  /// How a composite barcode's parts relate.
  final BarcodeCompositeType? supplementalCompositeType;

  /// Whether the barcode carries GS1 data.
  final bool isGs1DataCarrier;

  /// Whether the barcode is light on dark rather than dark on light.
  final bool isColorInverted;

  /// How confident Vision is, from 0 to 1.
  double get confidence => quad.confidence;

  @override
  String toString() => 'BarcodeObservation(${symbology.name}: $payload)';
}

// ---------------------------------------------------------------------------
// Faces and people
// ---------------------------------------------------------------------------

/// How the points of a face landmark region connect.
enum PointsClassification {
  /// The points form a closed loop.
  closedPath,

  /// The points are unrelated.
  disconnected,

  /// The points form an open path.
  openPath,
}

/// One named group of face landmark points, such as the left eye.
@immutable
final class FaceLandmarkRegion {
  FaceLandmarkRegion._(LandmarkRegionMessage message)
    : name = message.name,
      pointsClassification = switch (message.pointsClassification) {
        PointsClassificationMessage.closedPath =>
          PointsClassification.closedPath,
        PointsClassificationMessage.disconnected =>
          PointsClassification.disconnected,
        PointsClassificationMessage.openPath => PointsClassification.openPath,
      },
      points = message.points.map(NormalizedPoint._).toList(growable: false),
      precisionEstimates = message.precisionEstimates == null
          ? null
          : List.unmodifiable(message.precisionEstimates!);

  /// The region's name, such as `leftEye` or `outerLips`.
  final String name;

  /// How the points connect.
  final PointsClassification pointsClassification;

  /// The landmark points, in Vision's lower-left-origin space.
  final List<NormalizedPoint> points;

  /// Per-point precision estimates, when Vision provides them.
  final List<double>? precisionEstimates;

  @override
  String toString() => 'FaceLandmarkRegion($name, ${points.length} points)';
}

/// A detected face.
@immutable
final class FaceObservation {
  FaceObservation._(FaceObservationMessage message)
    : boundingBox = NormalizedRect._(message.boundingBox),
      confidence = message.confidence,
      rollDegrees = message.rollDegrees,
      yawDegrees = message.yawDegrees,
      pitchDegrees = message.pitchDegrees,
      captureQuality = message.captureQuality,
      landmarks = message.landmarks
          .map(FaceLandmarkRegion._)
          .toList(growable: false);

  /// Where the face sits in the image.
  final NormalizedRect boundingBox;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  /// Rotation around the axis pointing out of the image, in degrees.
  final double rollDegrees;

  /// Rotation around the vertical axis, in degrees.
  final double yawDegrees;

  /// Rotation around the horizontal axis, in degrees.
  final double pitchDegrees;

  /// How usable the face is for recognition, from
  /// `DetectFaceCaptureQualityRequest`.
  final double? captureQuality;

  /// The landmark regions, from `DetectFaceLandmarksRequest`.
  final List<FaceLandmarkRegion> landmarks;

  /// The landmark region called [name], if it was detected.
  FaceLandmarkRegion? landmark(String name) {
    for (final region in landmarks) {
      if (region.name == name) return region;
    }
    return null;
  }

  @override
  String toString() => 'FaceObservation($boundingBox)';
}

/// A detected person.
@immutable
final class HumanObservation {
  HumanObservation._(HumanObservationMessage message)
    : boundingBox = NormalizedRect._(message.boundingBox),
      confidence = message.confidence,
      isUpperBodyOnly = message.isUpperBodyOnly;

  /// Where the person sits in the image.
  final NormalizedRect boundingBox;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  /// Whether the box covers only the upper body.
  final bool isUpperBodyOnly;

  @override
  String toString() => 'HumanObservation($boundingBox)';
}

// ---------------------------------------------------------------------------
// Poses
// ---------------------------------------------------------------------------

/// One located joint of a pose.
@immutable
final class Joint {
  Joint._(JointMessage message)
    : name = message.name,
      location = NormalizedPoint._(message.location);

  /// The joint's name, such as `leftWrist` or `thumbTip`.
  final String name;

  /// Where the joint sits, in Vision's lower-left-origin space.
  final NormalizedPoint location;

  @override
  String toString() => 'Joint($name at $location)';
}

/// Which hand a hand pose belongs to.
enum Chirality {
  /// The left hand.
  left,

  /// The right hand.
  right,
}

/// A hand or animal pose.
@immutable
final class PoseObservation {
  PoseObservation._(PoseObservationMessage message)
    : confidence = message.confidence,
      joints = message.joints.map(Joint._).toList(growable: false),
      chirality = switch (message.chirality) {
        ChiralityMessage.left => Chirality.left,
        ChiralityMessage.right => Chirality.right,
        null => null,
      };

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  /// The located joints, sorted by name.
  final List<Joint> joints;

  /// Which hand this is, for hand poses.
  final Chirality? chirality;

  /// The joint called [name], if it was located.
  Joint? joint(String name) {
    for (final joint in joints) {
      if (joint.name == name) return joint;
    }
    return null;
  }

  @override
  String toString() => 'PoseObservation(${joints.length} joints)';
}

/// A detected human body pose.
@immutable
final class BodyPoseObservation {
  BodyPoseObservation._(BodyPoseObservationMessage message)
    : confidence = message.confidence,
      joints = message.joints.map(Joint._).toList(growable: false),
      leftHand = message.leftHand == null
          ? null
          : PoseObservation._(message.leftHand!),
      rightHand = message.rightHand == null
          ? null
          : PoseObservation._(message.rightHand!);

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  /// The located joints, sorted by name.
  final List<Joint> joints;

  /// The left hand's pose, when the request asked for hands.
  final PoseObservation? leftHand;

  /// The right hand's pose, when the request asked for hands.
  final PoseObservation? rightHand;

  /// The joint called [name], if it was located.
  Joint? joint(String name) {
    for (final joint in joints) {
      if (joint.name == name) return joint;
    }
    return null;
  }

  @override
  String toString() => 'BodyPoseObservation(${joints.length} joints)';
}

// ---------------------------------------------------------------------------
// Classification
// ---------------------------------------------------------------------------

/// A label Vision assigned to an image or object.
@immutable
final class Classification {
  Classification._(ClassificationMessage message)
    : identifier = message.identifier,
      confidence = message.confidence,
      hasPrecisionRecallCurve = message.hasPrecisionRecallCurve;

  /// The label, such as `document` or `outdoor`.
  final String identifier;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  /// Whether Vision has precision/recall data for this label.
  final bool hasPrecisionRecallCurve;

  @override
  String toString() => 'Classification($identifier: $confidence)';
}

/// A recognized object, such as a dog or a cat.
@immutable
final class RecognizedObject {
  RecognizedObject._(RecognizedObjectMessage message)
    : boundingBox = NormalizedRect._(message.boundingBox),
      confidence = message.confidence,
      labels = message.labels.map(Classification._).toList(growable: false);

  /// Where the object sits in the image.
  final NormalizedRect boundingBox;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  /// The candidate labels, best first.
  final List<Classification> labels;

  @override
  String toString() =>
      'RecognizedObject(${labels.isEmpty ? '?' : labels.first.identifier})';
}

/// How pleasant and how useful Vision thinks an image is.
@immutable
final class AestheticsScores {
  AestheticsScores._(AestheticsScoresMessage message)
    : overallScore = message.overallScore,
      isUtility = message.isUtility,
      confidence = message.confidence;

  /// The overall score, from -1 (unpleasant) to 1 (pleasant).
  final double overallScore;

  /// Whether the image looks like a utility shot, such as a receipt or a
  /// screenshot, rather than a photo worth keeping.
  final bool isUtility;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  @override
  String toString() => 'AestheticsScores($overallScore, isUtility: $isUtility)';
}

// ---------------------------------------------------------------------------
// Saliency, masks and segmentation
// ---------------------------------------------------------------------------

/// Which parts of an image draw the eye, or hold objects.
@immutable
final class Saliency {
  Saliency._(SaliencyMessage message)
    : salientObjects = message.salientObjects
          .map(NormalizedQuad._)
          .toList(growable: false),
      heatMap = MaskImage._(message.heatMap),
      confidence = message.confidence;

  /// The boxes Vision considers salient. Attention-based saliency usually
  /// reports none.
  final List<NormalizedQuad> salientObjects;

  /// A low-resolution heat map, usually 68 by 68 float values.
  final MaskImage heatMap;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  @override
  String toString() => 'Saliency($heatMap, ${salientObjects.length} objects)';
}

/// A mask that separates individual instances from the background.
@immutable
final class InstanceMask {
  InstanceMask._(InstanceMaskMessage message)
    : instances = List.unmodifiable(message.instances),
      mask = MaskImage._(message.mask),
      confidence = message.confidence;

  /// The instance indices in [mask]; 0 means background and is never listed.
  final List<int> instances;

  /// The mask, one byte per pixel, holding the instance index.
  final MaskImage mask;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  @override
  String toString() => 'InstanceMask(${instances.length} instances, $mask)';
}

/// A document found by `DetectDocumentSegmentationRequest`.
@immutable
final class DocumentSegmentation {
  DocumentSegmentation._(DocumentSegmentationMessage message)
    : quad = NormalizedQuad._(message.quad),
      mask = message.mask == null ? null : MaskImage._(message.mask!);

  /// The document's four corners.
  final NormalizedQuad quad;

  /// The segmentation mask, when the request asked for it.
  final MaskImage? mask;

  @override
  String toString() => 'DocumentSegmentation(${quad.boundingBox})';
}

// ---------------------------------------------------------------------------
// Horizon, contours and feature prints
// ---------------------------------------------------------------------------

/// The horizon Vision found in a photo.
@immutable
final class Horizon {
  Horizon._(HorizonMessage message)
    : angleDegrees = message.angleDegrees,
      confidence = message.confidence,
      transform = List.unmodifiable(message.transform);

  /// How far the image is rotated from level, in degrees.
  final double angleDegrees;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  /// The normalized affine transform that levels the image, as
  /// `[a, b, c, d, tx, ty]`.
  final List<double> transform;

  @override
  String toString() => 'Horizon($angleDegrees degrees)';
}

/// One closed contour of a `DetectContoursRequest`.
@immutable
final class Contour {
  Contour._(ContourMessage message)
    : indexPath = List.unmodifiable(message.indexPath),
      aspectRatio = message.aspectRatio,
      area = message.area,
      perimeter = message.perimeter,
      boundingBox = NormalizedRect._(message.boundingBox),
      pointCount = message.pointCount,
      childCount = message.childCount,
      _points = message.points;

  /// Where the contour sits in the observation's tree.
  final List<int> indexPath;

  /// The bounding box's width divided by its height.
  final double aspectRatio;

  /// The enclosed area, as a fraction of the image area.
  final double area;

  /// The length of the contour, in normalized units.
  final double perimeter;

  /// The box that contains the contour.
  final NormalizedRect boundingBox;

  /// How many points the contour has.
  final int pointCount;

  /// How many contours are nested directly inside this one.
  final int childCount;

  final Float64List? _points;

  /// The contour's points, when the request asked for them.
  ///
  /// Null unless `DetectContoursRequest.includePoints` was set.
  List<NormalizedPoint>? get points {
    final data = _points;
    if (data == null) return null;
    return List.generate(
      data.length ~/ 2,
      (index) => NormalizedPoint(data[index * 2], data[index * 2 + 1]),
      growable: false,
    );
  }

  @override
  String toString() => 'Contour($indexPath, $pointCount points)';
}

/// The contours Vision traced in an image.
@immutable
final class Contours {
  Contours._(ContoursMessage message)
    : contourCount = message.contourCount,
      confidence = message.confidence,
      contours = message.contours.map(Contour._).toList(growable: false);

  /// How many contours Vision found, including nested ones.
  final int contourCount;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  /// The contours, each followed by its children.
  final List<Contour> contours;

  @override
  String toString() => 'Contours($contourCount)';
}

/// A vector that describes an image, for comparing images.
@immutable
final class FeaturePrint {
  FeaturePrint._(FeaturePrintMessage message)
    : elementCount = message.elementCount,
      isDouble = message.isDouble,
      bytes = message.data,
      token = message.token,
      confidence = message.confidence;

  /// How many elements the vector has.
  final int elementCount;

  /// Whether [bytes] holds 64-bit rather than 32-bit floats.
  final bool isDouble;

  /// The vector's raw bytes, in host byte order.
  final Uint8List bytes;

  /// An opaque token that [distanceTo] uses to ask Vision for a distance.
  ///
  /// Store it to compare against this image later.
  final String token;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  /// The vector as 64-bit floats.
  Float64List get vector {
    final data = ByteData.sublistView(bytes);
    final result = Float64List(elementCount);
    for (var i = 0; i < elementCount; i++) {
      result[i] = isDouble
          ? data.getFloat64(i * 8, Endian.host)
          : data.getFloat32(i * 4, Endian.host);
    }
    return result;
  }

  /// Vision's own distance between this print and [other].
  ///
  /// Identical images give 0; larger numbers mean less alike.
  Future<double> distanceTo(FeaturePrint other) => guardPlatformCall(
    () => AppleVisionBindings.instance.host.featurePrintDistance(
      token,
      other.token,
    ),
  );

  /// Vision's own distance between two stored [token]s.
  static Future<double> distanceBetween(String a, String b) =>
      guardPlatformCall(
        () => AppleVisionBindings.instance.host.featurePrintDistance(a, b),
      );

  @override
  String toString() => 'FeaturePrint($elementCount elements)';
}

// ---------------------------------------------------------------------------
// Documents
// ---------------------------------------------------------------------------

/// How a run of document text is aligned.
enum DocumentTextAlignment {
  /// Centered.
  center,

  /// Aligned to the leading edge.
  leading,

  /// Aligned to the trailing edge.
  trailing,
}

/// The marker style of a document list.
enum DocumentListMarker {
  /// A bullet.
  bullet,

  /// A hyphen.
  hyphen,

  /// Lowercase letters.
  lowercaseLatin,

  /// Uppercase letters.
  uppercaseLatin,

  /// Decimal numbers.
  decimal,

  /// Decorated decimal numbers.
  decorativeDecimal,

  /// Composite decimal numbers such as `1.2`.
  compositeDecimal,
}

/// A run of text inside a recognized document.
@immutable
final class DocumentText {
  DocumentText._(DocumentTextMessage message)
    : transcript = message.transcript,
      lines = message.lines
          .map(RecognizedTextObservation._)
          .toList(growable: false),
      alignment = switch (message.alignment) {
        TextAlignmentMessage.center => DocumentTextAlignment.center,
        TextAlignmentMessage.leading => DocumentTextAlignment.leading,
        TextAlignmentMessage.trailing => DocumentTextAlignment.trailing,
        null => null,
      };

  /// All of the run's text, with line breaks.
  final String transcript;

  /// The individual lines.
  final List<RecognizedTextObservation> lines;

  /// How the run is aligned, when Vision could tell.
  final DocumentTextAlignment? alignment;

  @override
  String toString() => 'DocumentText($transcript)';
}

/// One cell of a table inside a recognized document.
@immutable
final class DocumentTableCell {
  DocumentTableCell._(DocumentTableCellMessage message)
    : rowStart = message.rowStart,
      rowEnd = message.rowEnd,
      columnStart = message.columnStart,
      columnEnd = message.columnEnd,
      text = message.text;

  /// The first row the cell covers.
  final int rowStart;

  /// The last row the cell covers.
  final int rowEnd;

  /// The first column the cell covers.
  final int columnStart;

  /// The last column the cell covers.
  final int columnEnd;

  /// The cell's text.
  final String text;

  @override
  String toString() => 'DocumentTableCell($rowStart,$columnStart: $text)';
}

/// A table inside a recognized document.
@immutable
final class DocumentTable {
  DocumentTable._(DocumentTableMessage message)
    : rowCount = message.rowCount,
      columnCount = message.columnCount,
      cells = message.cells.map(DocumentTableCell._).toList(growable: false);

  /// How many rows the table has.
  final int rowCount;

  /// How many columns the table has.
  final int columnCount;

  /// Every cell, row by row.
  final List<DocumentTableCell> cells;

  @override
  String toString() => 'DocumentTable(${rowCount}x$columnCount)';
}

/// One item of a list inside a recognized document.
@immutable
final class DocumentListItem {
  DocumentListItem._(DocumentListItemMessage message)
    : markerType = switch (message.markerType) {
        ListMarkerMessage.bullet => DocumentListMarker.bullet,
        ListMarkerMessage.hyphen => DocumentListMarker.hyphen,
        ListMarkerMessage.lowercaseLatin => DocumentListMarker.lowercaseLatin,
        ListMarkerMessage.uppercaseLatin => DocumentListMarker.uppercaseLatin,
        ListMarkerMessage.decimal => DocumentListMarker.decimal,
        ListMarkerMessage.decorativeDecimal =>
          DocumentListMarker.decorativeDecimal,
        ListMarkerMessage.compositeDecimal =>
          DocumentListMarker.compositeDecimal,
        null => null,
      },
      markerText = message.markerText,
      text = message.itemText;

  /// The marker style, when Vision could tell.
  final DocumentListMarker? markerType;

  /// The marker itself, such as `1.` or `-`.
  final String markerText;

  /// The item's text, without its marker.
  final String text;

  @override
  String toString() => 'DocumentListItem($markerText $text)';
}

/// A list inside a recognized document.
@immutable
final class DocumentList {
  DocumentList._(DocumentListMessage message)
    : items = message.items.map(DocumentListItem._).toList(growable: false);

  /// The list's items.
  final List<DocumentListItem> items;

  @override
  String toString() => 'DocumentList(${items.length} items)';
}

/// A document Vision read, from `RecognizeDocumentsRequest`.
///
/// This is a flattened view of the top-level `DocumentObservation.Container`:
/// nested containers inside tables and lists are reduced to their text.
@immutable
final class DocumentObservation {
  DocumentObservation._(DocumentObservationMessage message)
    : transcript = message.transcript,
      title = message.title,
      paragraphs = message.paragraphs
          .map(DocumentText._)
          .toList(growable: false),
      barcodes = message.barcodes
          .map(BarcodeObservation._)
          .toList(growable: false),
      tables = message.tables.map(DocumentTable._).toList(growable: false),
      lists = message.lists.map(DocumentList._).toList(growable: false),
      confidence = message.confidence;

  /// The whole document's text, in reading order.
  final String transcript;

  /// The document's title, when Vision found one.
  final String? title;

  /// The document's paragraphs.
  final List<DocumentText> paragraphs;

  /// Barcodes printed on the document.
  final List<BarcodeObservation> barcodes;

  /// The document's tables.
  final List<DocumentTable> tables;

  /// The document's lists.
  final List<DocumentList> lists;

  /// How confident Vision is, from 0 to 1.
  final double confidence;

  @override
  String toString() => 'DocumentObservation(${transcript.length} characters)';
}
