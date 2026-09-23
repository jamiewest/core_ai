// Pigeon schema for the apple_vision plugin.
//
// Regenerate with:
//   dart run pigeon --input pigeons/apple_vision_api.dart
//   dart format lib/src/messages.g.dart
//
// Wire-format conventions:
// * One `perform` call decodes the image once and runs every request on the
//   same `ImageRequestHandler`, in order. Result `i` belongs to request `i`;
//   a request that failed carries an [ErrorMessage] instead of observations.
// * Requests travel as a flat [RequestMessage] with a [RequestKindMessage]
//   discriminator and one optional field per Vision request property. The
//   public Dart API exposes a sealed `VisionRequest` hierarchy instead.
// * Geometry is normalized to the unit square with Vision's own convention:
//   the origin is the LOWER-LEFT corner and y grows upwards.
// * Masks and heat maps travel as raw pixel bytes plus size, row stride and
//   the Core Video four-character pixel format.
// * Feature prints travel as the raw vector bytes plus an opaque `token`
//   (the observation's `Codable` JSON) so `featurePrintDistance` can use
//   Vision's own metric later on.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(
  PigeonOptions(
    dartOut: 'lib/src/messages.g.dart',
    dartOptions: DartOptions(),
    swiftOut: 'darwin/apple_vision/Sources/apple_vision/Messages.g.swift',
    swiftOptions: SwiftOptions(errorClassName: 'AppleVisionPigeonError'),
    dartPackageName: 'apple_vision',
    copyrightHeader: 'pigeons/copyright.txt',
  ),
)
// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------
/// How the bytes of an image input should be interpreted.
enum ImageInputKindMessage { file, encoded, pixels }

/// Mirrors `CGImagePropertyOrientation` (raw values 1 to 8, in order).
enum ImageOrientationMessage {
  up,
  upMirrored,
  down,
  downMirrored,
  leftMirrored,
  right,
  rightMirrored,
  left,
}

/// Mirrors `RecognizeTextRequest.RecognitionLevel`.
enum RecognitionLevelMessage { accurate, fast }

/// Mirrors `ImageCropAndScaleAction`.
enum CropAndScaleActionMessage {
  centerCrop,
  scaleToFit,
  scaleToFill,
  scaleToFitPlus90CcwRotation,
  scaleToFillPlus90CcwRotation,
}

/// Mirrors `BarcodeSymbology`.
enum BarcodeSymbologyMessage {
  aztec,
  code39,
  code39Checksum,
  code39FullAscii,
  code39FullAsciiChecksum,
  code93,
  code93i,
  code128,
  dataMatrix,
  ean8,
  ean13,
  i2of5,
  i2of5Checksum,
  itf14,
  pdf417,
  qr,
  upce,
  codabar,
  gs1DataBar,
  gs1DataBarExpanded,
  gs1DataBarLimited,
  microPdf417,
  microQr,
  msiPlessey,
}

/// Mirrors `BarcodeObservation.CompositeType`.
enum BarcodeCompositeTypeMessage { gs1TypeA, gs1TypeB, gs1TypeC, linked }

/// Mirrors `HumanHandPoseObservation.Chirality`.
enum ChiralityMessage { left, right }

/// Mirrors `FaceObservation.Landmarks2D.Region.PointsClassification`.
enum PointsClassificationMessage { closedPath, disconnected, openPath }

/// Mirrors `GeneratePersonSegmentationRequest.QualityLevel`.
enum SegmentationQualityMessage { accurate, balanced, fast }

/// Mirrors `RecognizedTextObservation.Direction`.
enum TextDirectionMessage { leftToRight, rightToLeft, topToBottom }

/// Mirrors `DocumentObservation.Container.Text.Alignment`.
enum TextAlignmentMessage { center, leading, trailing }

/// Mirrors `DocumentObservation.Container.List.Marker`.
enum ListMarkerMessage {
  bullet,
  hyphen,
  lowercaseLatin,
  uppercaseLatin,
  decimal,
  decorativeDecimal,
  compositeDecimal,
}

/// Every Vision request this plugin can run on a still image.
enum RequestKindMessage {
  recognizeText,
  recognizeDocuments,
  detectTextRectangles,
  detectBarcodes,
  detectFaceRectangles,
  detectFaceLandmarks,
  detectFaceCaptureQuality,
  detectHumanRectangles,
  detectHumanBodyPose,
  detectHumanHandPose,
  detectAnimalBodyPose,
  recognizeAnimals,
  classifyImage,
  calculateImageAestheticsScores,
  generateAttentionBasedSaliencyImage,
  generateObjectnessBasedSaliencyImage,
  generatePersonSegmentation,
  generatePersonInstanceMask,
  generateForegroundInstanceMask,
  detectDocumentSegmentation,
  detectRectangles,
  detectHorizon,
  detectContours,
  detectLensSmudge,
  generateImageFeaturePrint,
}

// ---------------------------------------------------------------------------
// Geometry
// ---------------------------------------------------------------------------

/// A point in Vision's normalized, lower-left-origin coordinate space.
class NormalizedPointMessage {
  NormalizedPointMessage({required this.x, required this.y});

  double x;
  double y;
}

/// A rectangle in Vision's normalized, lower-left-origin coordinate space.
class NormalizedRectMessage {
  NormalizedRectMessage({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  double x;
  double y;
  double width;
  double height;
}

/// A `QuadrilateralProviding` observation: four corners plus their axis
/// aligned bounding box.
class QuadrilateralMessage {
  QuadrilateralMessage({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
    required this.boundingBox,
    required this.confidence,
  });

  NormalizedPointMessage topLeft;
  NormalizedPointMessage topRight;
  NormalizedPointMessage bottomRight;
  NormalizedPointMessage bottomLeft;
  NormalizedRectMessage boundingBox;
  double confidence;
}

// ---------------------------------------------------------------------------
// Images
// ---------------------------------------------------------------------------

/// An image to analyze.
class ImageInputMessage {
  ImageInputMessage({
    required this.kind,
    this.path,
    this.bytes,
    this.width,
    this.height,
    this.bytesPerRow,
  });

  ImageInputKindMessage kind;

  /// For `file`.
  String? path;

  /// Encoded image bytes (`encoded`) or BGRA8 pixels (`pixels`).
  Uint8List? bytes;

  /// For `pixels`.
  int? width;
  int? height;
  int? bytesPerRow;
}

/// The pixel size of a decoded image, after applying its orientation.
class ImageSizeMessage {
  ImageSizeMessage({required this.width, required this.height});

  int width;
  int height;
}

/// Raw bytes of a mask or heat map produced by Vision.
class MaskImageMessage {
  MaskImageMessage({
    required this.width,
    required this.height,
    required this.bytesPerRow,
    required this.pixelFormatType,
    required this.bytes,
  });

  int width;
  int height;

  /// Distance in bytes between the starts of consecutive rows.
  int bytesPerRow;

  /// The Core Video four-character code, for example `L00f`
  /// (`kCVPixelFormatType_OneComponent32Float`).
  int pixelFormatType;

  /// [height] rows of [bytesPerRow] bytes.
  Uint8List bytes;
}

// ---------------------------------------------------------------------------
// Requests
// ---------------------------------------------------------------------------

/// One Vision request, with the options that apply to its [kind].
class RequestMessage {
  RequestMessage({
    required this.kind,
    this.regionOfInterest,
    this.recognitionLevel,
    this.recognitionLanguages,
    this.customWords,
    this.usesLanguageCorrection,
    this.automaticallyDetectsLanguage,
    this.minimumTextHeightFraction,
    this.maximumCandidateCount,
    this.reportCharacterBoxes,
    this.symbologies,
    this.coalescesCompositeSymbologies,
    this.detectsBarcodesInDocuments,
    this.cropAndScaleAction,
    this.upperBodyOnly,
    this.detectsHands,
    this.maximumHandCount,
    this.minimumAspectRatio,
    this.maximumAspectRatio,
    this.quadratureToleranceDegrees,
    this.minimumSize,
    this.minimumConfidence,
    this.maximumObservations,
    this.contrastAdjustment,
    this.contrastPivot,
    this.detectsDarkOnLight,
    this.maximumImageDimension,
    this.includeContourPoints,
    this.segmentationQuality,
    this.scaleMaskToImage,
    this.includeMask,
  });

  RequestKindMessage kind;

  /// Defaults to the full image.
  NormalizedRectMessage? regionOfInterest;

  // Text recognition.
  RecognitionLevelMessage? recognitionLevel;

  /// BCP-47 language identifiers, most preferred first.
  List<String>? recognitionLanguages;
  List<String>? customWords;
  bool? usesLanguageCorrection;
  bool? automaticallyDetectsLanguage;
  double? minimumTextHeightFraction;
  int? maximumCandidateCount;
  bool? reportCharacterBoxes;

  // Barcodes.
  List<BarcodeSymbologyMessage>? symbologies;
  bool? coalescesCompositeSymbologies;
  bool? detectsBarcodesInDocuments;

  // Classification, aesthetics, feature prints.
  CropAndScaleActionMessage? cropAndScaleAction;

  // People and poses.
  bool? upperBodyOnly;
  bool? detectsHands;
  int? maximumHandCount;

  // Rectangles.
  double? minimumAspectRatio;
  double? maximumAspectRatio;
  double? quadratureToleranceDegrees;
  double? minimumSize;
  double? minimumConfidence;
  int? maximumObservations;

  // Contours.
  double? contrastAdjustment;
  double? contrastPivot;
  bool? detectsDarkOnLight;
  int? maximumImageDimension;
  bool? includeContourPoints;

  // Segmentation and masks.
  SegmentationQualityMessage? segmentationQuality;

  /// Return the instance mask scaled to the size of the analyzed image.
  bool? scaleMaskToImage;

  /// Return mask bytes at all. Off by default for document segmentation,
  /// whose mask is large and rarely needed.
  bool? includeMask;
}

// ---------------------------------------------------------------------------
// Observations
// ---------------------------------------------------------------------------

/// One interpretation of a recognized line of text.
class TextCandidateMessage {
  TextCandidateMessage({required this.text, required this.confidence});

  String text;
  double confidence;
}

/// Mirrors `RecognizedTextObservation`.
class RecognizedTextObservationMessage {
  RecognizedTextObservationMessage({
    required this.quad,
    required this.candidates,
    required this.transcript,
    required this.isTitle,
    required this.recognitionLanguages,
    this.textDirection,
  });

  QuadrilateralMessage quad;
  List<TextCandidateMessage> candidates;
  String transcript;
  bool isTitle;
  List<String> recognitionLanguages;
  TextDirectionMessage? textDirection;
}

/// Mirrors `TextObservation` (text rectangles, no recognition).
class TextObservationMessage {
  TextObservationMessage({required this.quad, this.characterBoxes});

  QuadrilateralMessage quad;
  List<QuadrilateralMessage>? characterBoxes;
}

/// Mirrors `BarcodeObservation`.
class BarcodeObservationMessage {
  BarcodeObservationMessage({
    required this.quad,
    required this.symbology,
    this.payload,
    this.payloadData,
    this.supplementalPayload,
    this.supplementalCompositeType,
    required this.isGs1DataCarrier,
    required this.isColorInverted,
  });

  QuadrilateralMessage quad;
  BarcodeSymbologyMessage symbology;
  String? payload;
  Uint8List? payloadData;
  String? supplementalPayload;
  BarcodeCompositeTypeMessage? supplementalCompositeType;
  bool isGs1DataCarrier;
  bool isColorInverted;
}

/// One named region of `FaceObservation.Landmarks2D`.
class LandmarkRegionMessage {
  LandmarkRegionMessage({
    required this.name,
    required this.pointsClassification,
    required this.points,
    this.precisionEstimates,
  });

  /// The Swift property name, for example `leftEye`.
  String name;
  PointsClassificationMessage pointsClassification;
  List<NormalizedPointMessage> points;
  List<double>? precisionEstimates;
}

/// Mirrors `FaceObservation`.
class FaceObservationMessage {
  FaceObservationMessage({
    required this.boundingBox,
    required this.confidence,
    required this.rollDegrees,
    required this.yawDegrees,
    required this.pitchDegrees,
    this.captureQuality,
    required this.landmarks,
  });

  NormalizedRectMessage boundingBox;
  double confidence;
  double rollDegrees;
  double yawDegrees;
  double pitchDegrees;
  double? captureQuality;

  /// Empty unless the request was `detectFaceLandmarks`.
  List<LandmarkRegionMessage> landmarks;
}

/// Mirrors `HumanObservation`.
class HumanObservationMessage {
  HumanObservationMessage({
    required this.boundingBox,
    required this.confidence,
    required this.isUpperBodyOnly,
  });

  NormalizedRectMessage boundingBox;
  double confidence;
  bool isUpperBodyOnly;
}

/// Mirrors `Joint`.
class JointMessage {
  JointMessage({required this.name, required this.location});

  /// The raw value of the pose's `JointName`, for example `leftWrist`.
  String name;
  NormalizedPointMessage location;
}

/// A hand or animal pose: `HumanHandPoseObservation` or
/// `AnimalBodyPoseObservation`.
class PoseObservationMessage {
  PoseObservationMessage({
    required this.confidence,
    required this.joints,
    this.chirality,
  });

  double confidence;
  List<JointMessage> joints;
  ChiralityMessage? chirality;
}

/// Mirrors `HumanBodyPoseObservation`.
class BodyPoseObservationMessage {
  BodyPoseObservationMessage({
    required this.confidence,
    required this.joints,
    this.leftHand,
    this.rightHand,
  });

  double confidence;
  List<JointMessage> joints;
  PoseObservationMessage? leftHand;
  PoseObservationMessage? rightHand;
}

/// Mirrors `ClassificationObservation`.
class ClassificationMessage {
  ClassificationMessage({
    required this.identifier,
    required this.confidence,
    required this.hasPrecisionRecallCurve,
  });

  String identifier;
  double confidence;
  bool hasPrecisionRecallCurve;
}

/// Mirrors `RecognizedObjectObservation`.
class RecognizedObjectMessage {
  RecognizedObjectMessage({
    required this.boundingBox,
    required this.confidence,
    required this.labels,
  });

  NormalizedRectMessage boundingBox;
  double confidence;
  List<ClassificationMessage> labels;
}

/// Mirrors `ImageAestheticsScoresObservation`.
class AestheticsScoresMessage {
  AestheticsScoresMessage({
    required this.overallScore,
    required this.isUtility,
    required this.confidence,
  });

  double overallScore;
  bool isUtility;
  double confidence;
}

/// Mirrors `SaliencyImageObservation`.
class SaliencyMessage {
  SaliencyMessage({
    required this.salientObjects,
    required this.heatMap,
    required this.confidence,
  });

  List<QuadrilateralMessage> salientObjects;
  MaskImageMessage heatMap;
  double confidence;
}

/// Mirrors `InstanceMaskObservation`.
class InstanceMaskMessage {
  InstanceMaskMessage({
    required this.instances,
    required this.mask,
    required this.confidence,
  });

  /// The instance indices in `allInstances` (never includes 0, the
  /// background).
  List<int> instances;
  MaskImageMessage mask;
  double confidence;
}

/// Mirrors `DetectedDocumentObservation`.
class DocumentSegmentationMessage {
  DocumentSegmentationMessage({required this.quad, this.mask});

  QuadrilateralMessage quad;
  MaskImageMessage? mask;
}

/// Mirrors `HorizonObservation`.
class HorizonMessage {
  HorizonMessage({
    required this.angleDegrees,
    required this.confidence,
    required this.transform,
  });

  double angleDegrees;
  double confidence;

  /// The normalized `CGAffineTransform` as `[a, b, c, d, tx, ty]`.
  List<double> transform;
}

/// One contour of a `ContoursObservation`.
class ContourMessage {
  ContourMessage({
    required this.indexPath,
    required this.aspectRatio,
    required this.area,
    required this.perimeter,
    required this.boundingBox,
    required this.pointCount,
    required this.childCount,
    this.points,
  });

  /// The contour's position in the observation's tree.
  List<int> indexPath;
  double aspectRatio;
  double area;
  double perimeter;
  NormalizedRectMessage boundingBox;
  int pointCount;
  int childCount;

  /// Interleaved x, y pairs; only present when the request asked for points.
  Float64List? points;
}

/// Mirrors `ContoursObservation`.
class ContoursMessage {
  ContoursMessage({
    required this.contourCount,
    required this.confidence,
    required this.contours,
  });

  int contourCount;
  double confidence;

  /// Top-level contours, each with its children flattened after it.
  List<ContourMessage> contours;
}

/// Mirrors `FeaturePrintObservation`.
class FeaturePrintMessage {
  FeaturePrintMessage({
    required this.elementCount,
    required this.isDouble,
    required this.data,
    required this.token,
    required this.confidence,
  });

  int elementCount;

  /// Whether [data] holds `Float64`s rather than `Float32`s.
  bool isDouble;
  Uint8List data;

  /// The observation's `Codable` JSON, for [AppleVisionHostApi.
  /// featurePrintDistance].
  String token;
  double confidence;
}

/// Mirrors `SmudgeObservation`.
class SmudgeMessage {
  SmudgeMessage({required this.confidence});

  double confidence;
}

/// A run of text inside a recognized document.
class DocumentTextMessage {
  DocumentTextMessage({
    required this.transcript,
    required this.lines,
    this.alignment,
  });

  String transcript;
  List<RecognizedTextObservationMessage> lines;
  TextAlignmentMessage? alignment;
}

/// One cell of a table inside a recognized document.
class DocumentTableCellMessage {
  DocumentTableCellMessage({
    required this.rowStart,
    required this.rowEnd,
    required this.columnStart,
    required this.columnEnd,
    required this.text,
  });

  int rowStart;
  int rowEnd;
  int columnStart;
  int columnEnd;
  String text;
}

/// A table inside a recognized document.
class DocumentTableMessage {
  DocumentTableMessage({
    required this.rowCount,
    required this.columnCount,
    required this.cells,
  });

  int rowCount;
  int columnCount;
  List<DocumentTableCellMessage> cells;
}

/// One item of a list inside a recognized document.
class DocumentListItemMessage {
  DocumentListItemMessage({
    this.markerType,
    required this.markerText,
    required this.itemText,
  });

  ListMarkerMessage? markerType;
  String markerText;
  String itemText;
}

/// A list inside a recognized document.
class DocumentListMessage {
  DocumentListMessage({required this.items});

  List<DocumentListItemMessage> items;
}

/// Mirrors `DocumentObservation`, flattened to its top-level container.
class DocumentObservationMessage {
  DocumentObservationMessage({
    required this.transcript,
    this.title,
    required this.paragraphs,
    required this.barcodes,
    required this.tables,
    required this.lists,
    required this.confidence,
  });

  String transcript;
  String? title;
  List<DocumentTextMessage> paragraphs;
  List<BarcodeObservationMessage> barcodes;
  List<DocumentTableMessage> tables;
  List<DocumentListMessage> lists;
  double confidence;
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

/// A failure, either of one request or of the whole call.
class ErrorMessage {
  ErrorMessage({required this.code, required this.message, this.details});

  String code;
  String message;
  String? details;
}

/// The outcome of one [RequestMessage]. Exactly one payload field is set,
/// unless [error] is, in which case the request failed on its own.
class RequestResultMessage {
  RequestResultMessage({
    required this.kind,
    this.error,
    this.recognizedText,
    this.textRectangles,
    this.barcodes,
    this.rectangles,
    this.faces,
    this.humans,
    this.bodyPoses,
    this.poses,
    this.classifications,
    this.objects,
    this.aesthetics,
    this.saliency,
    this.instanceMask,
    this.mask,
    this.documentSegmentation,
    this.horizon,
    this.contours,
    this.featurePrint,
    this.smudge,
    this.documents,
  });

  RequestKindMessage kind;
  ErrorMessage? error;

  List<RecognizedTextObservationMessage>? recognizedText;
  List<TextObservationMessage>? textRectangles;
  List<BarcodeObservationMessage>? barcodes;

  /// Detected rectangles, and the salient objects of a saliency request.
  List<QuadrilateralMessage>? rectangles;
  List<FaceObservationMessage>? faces;
  List<HumanObservationMessage>? humans;
  List<BodyPoseObservationMessage>? bodyPoses;
  List<PoseObservationMessage>? poses;
  List<ClassificationMessage>? classifications;
  List<RecognizedObjectMessage>? objects;
  AestheticsScoresMessage? aesthetics;
  SaliencyMessage? saliency;
  InstanceMaskMessage? instanceMask;

  /// Person segmentation.
  MaskImageMessage? mask;
  DocumentSegmentationMessage? documentSegmentation;
  HorizonMessage? horizon;
  ContoursMessage? contours;
  FeaturePrintMessage? featurePrint;
  SmudgeMessage? smudge;
  List<DocumentObservationMessage>? documents;
}

/// Everything one [AppleVisionHostApi.perform] call produced.
class AnalysisMessage {
  AnalysisMessage({required this.imageSize, required this.results});

  /// The size of the decoded image, after applying its orientation.
  ImageSizeMessage imageSize;

  /// One entry per request, in the order they were given.
  List<RequestResultMessage> results;
}

// ---------------------------------------------------------------------------
// APIs
// ---------------------------------------------------------------------------

/// Always registered.
@HostApi()
abstract class AppleVisionPlatformApi {
  /// Whether the Vision requests this plugin uses are available
  /// (iOS 27+ / macOS 27+).
  bool isSupported();

  /// A readable operating-system version, for diagnostics.
  String platformVersion();

  /// Resolves a Flutter asset key to a file path, or null when it is missing.
  String? assetPath(String assetKey, String? package);
}

/// Registered only when Vision is available.
@HostApi()
abstract class AppleVisionHostApi {
  /// Decodes [image] once and runs every request on it, in order.
  @async
  AnalysisMessage perform(
    ImageInputMessage image,
    ImageOrientationMessage? orientation,
    List<RequestMessage> requests,
  );

  /// The pixel size of [image] after applying [orientation].
  @async
  ImageSizeMessage imageSize(
    ImageInputMessage image,
    ImageOrientationMessage? orientation,
  );

  /// BCP-47 identifiers of the languages text recognition supports.
  List<String> supportedRecognitionLanguages(RecognitionLevelMessage level);

  /// The barcode symbologies this device can detect.
  List<BarcodeSymbologyMessage> supportedBarcodeSymbologies();

  /// Every identifier `ClassifyImageRequest` can return.
  List<String> supportedClassificationIdentifiers();

  /// Encodes a mask or heat map as a PNG.
  @async
  Uint8List encodeMaskAsPng(MaskImageMessage mask);

  /// Vision's own distance between two feature prints, by their tokens.
  @async
  double featurePrintDistance(String tokenA, String tokenB);
}
