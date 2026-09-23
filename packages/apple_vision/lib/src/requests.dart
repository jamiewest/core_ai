part of 'vision.dart';

/// How thoroughly `RecognizeTextRequest` reads text.
enum RecognitionLevel {
  /// Slower, but reads more text correctly.
  accurate(RecognitionLevelMessage.accurate),

  /// Faster, at the cost of accuracy.
  fast(RecognitionLevelMessage.fast);

  const RecognitionLevel(this._message);

  final RecognitionLevelMessage _message;
}

/// How an image is fitted to a model's input size.
enum CropAndScaleAction {
  /// Crop the centre square.
  centerCrop(CropAndScaleActionMessage.centerCrop),

  /// Scale the whole image to fit, letterboxing it.
  scaleToFit(CropAndScaleActionMessage.scaleToFit),

  /// Scale the whole image to fill, stretching it.
  scaleToFill(CropAndScaleActionMessage.scaleToFill),

  /// Scale to fit, then rotate 90 degrees counter-clockwise.
  scaleToFitPlus90CcwRotation(
    CropAndScaleActionMessage.scaleToFitPlus90CcwRotation,
  ),

  /// Scale to fill, then rotate 90 degrees counter-clockwise.
  scaleToFillPlus90CcwRotation(
    CropAndScaleActionMessage.scaleToFillPlus90CcwRotation,
  );

  const CropAndScaleAction(this._message);

  final CropAndScaleActionMessage _message;
}

/// How carefully `GeneratePersonSegmentationRequest` works.
enum SegmentationQuality {
  /// The highest quality, and the slowest.
  accurate(SegmentationQualityMessage.accurate),

  /// A compromise.
  balanced(SegmentationQualityMessage.balanced),

  /// The fastest, for live video.
  fast(SegmentationQualityMessage.fast);

  const SegmentationQuality(this._message);

  final SegmentationQualityMessage _message;
}

/// One Vision request to run on an image.
///
/// `R` is the type [AppleVision.perform] and [VisionAnalysis.resultOf] give
/// back for this request.
@immutable
sealed class VisionRequest<R> {
  const VisionRequest({this.regionOfInterest});

  /// The part of the image to analyze; the whole image by default.
  final NormalizedRect? regionOfInterest;

  RequestKindMessage get _kind;

  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
  );

  R _decode(RequestResultMessage message);

  @override
  String toString() => '$runtimeType()';
}

/// Reads the text in an image.
///
/// Mirrors `RecognizeTextRequest`.
final class RecognizeTextRequest
    extends VisionRequest<List<RecognizedTextObservation>> {
  /// Creates a text-recognition request.
  const RecognizeTextRequest({
    this.recognitionLevel,
    this.recognitionLanguages = const [],
    this.customWords = const [],
    this.usesLanguageCorrection,
    this.automaticallyDetectsLanguage,
    this.minimumTextHeightFraction,
    this.maximumCandidateCount = 1,
    super.regionOfInterest,
  });

  /// Speed against accuracy. Vision defaults to [RecognitionLevel.accurate].
  final RecognitionLevel? recognitionLevel;

  /// BCP-47 language identifiers, most preferred first.
  ///
  /// See [AppleVision.supportedRecognitionLanguages].
  final List<String> recognitionLanguages;

  /// Words that are not in the language model, such as product names.
  final List<String> customWords;

  /// Whether to apply language correction to the recognized text.
  final bool? usesLanguageCorrection;

  /// Whether Vision should pick the language itself.
  final bool? automaticallyDetectsLanguage;

  /// The smallest text to look for, as a fraction of the image height.
  final double? minimumTextHeightFraction;

  /// How many interpretations to return per line.
  final int maximumCandidateCount;

  @override
  RequestKindMessage get _kind => RequestKindMessage.recognizeText;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    recognitionLevel: recognitionLevel?._message,
    recognitionLanguages: recognitionLanguages,
    customWords: customWords,
    usesLanguageCorrection: usesLanguageCorrection,
    automaticallyDetectsLanguage: automaticallyDetectsLanguage,
    minimumTextHeightFraction: minimumTextHeightFraction,
    maximumCandidateCount: maximumCandidateCount,
  );

  @override
  List<RecognizedTextObservation> _decode(RequestResultMessage message) =>
      (message.recognizedText ?? const [])
          .map(RecognizedTextObservation._)
          .toList(growable: false);
}

/// Reads a document's text, tables, lists and barcodes.
///
/// Mirrors `RecognizeDocumentsRequest`.
final class RecognizeDocumentsRequest
    extends VisionRequest<List<DocumentObservation>> {
  /// Creates a document-recognition request.
  const RecognizeDocumentsRequest({
    this.recognitionLanguages = const [],
    this.customWords = const [],
    this.usesLanguageCorrection,
    this.automaticallyDetectsLanguage,
    this.minimumTextHeightFraction,
    this.maximumCandidateCount,
    this.detectsBarcodes,
    this.symbologies = const [],
    super.regionOfInterest,
  });

  /// BCP-47 language identifiers, most preferred first.
  final List<String> recognitionLanguages;

  /// Words that are not in the language model.
  final List<String> customWords;

  /// Whether to apply language correction.
  final bool? usesLanguageCorrection;

  /// Whether Vision should pick the language itself.
  final bool? automaticallyDetectsLanguage;

  /// The smallest text to look for, as a fraction of the image height.
  final double? minimumTextHeightFraction;

  /// How many interpretations to keep per line.
  final int? maximumCandidateCount;

  /// Whether to look for barcodes as well as text.
  final bool? detectsBarcodes;

  /// Which symbologies to look for; all of them by default.
  final List<BarcodeSymbology> symbologies;

  @override
  RequestKindMessage get _kind => RequestKindMessage.recognizeDocuments;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    recognitionLanguages: recognitionLanguages,
    customWords: customWords,
    usesLanguageCorrection: usesLanguageCorrection,
    automaticallyDetectsLanguage: automaticallyDetectsLanguage,
    minimumTextHeightFraction: minimumTextHeightFraction,
    maximumCandidateCount: maximumCandidateCount,
    detectsBarcodesInDocuments: detectsBarcodes,
    symbologies: symbologies.map((value) => value._message).toList(),
  );

  @override
  List<DocumentObservation> _decode(RequestResultMessage message) =>
      (message.documents ?? const [])
          .map(DocumentObservation._)
          .toList(growable: false);
}

/// Finds the regions of an image that hold text, without reading it.
///
/// Mirrors `DetectTextRectanglesRequest`.
final class DetectTextRectanglesRequest
    extends VisionRequest<List<TextRectangleObservation>> {
  /// Creates a text-rectangle request.
  const DetectTextRectanglesRequest({
    this.reportCharacterBoxes = false,
    super.regionOfInterest,
  });

  /// Whether to return a box per character as well as per region.
  final bool reportCharacterBoxes;

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectTextRectangles;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    reportCharacterBoxes: reportCharacterBoxes,
  );

  @override
  List<TextRectangleObservation> _decode(RequestResultMessage message) =>
      (message.textRectangles ?? const [])
          .map(TextRectangleObservation._)
          .toList(growable: false);
}

/// Finds and decodes barcodes.
///
/// Mirrors `DetectBarcodesRequest`.
final class DetectBarcodesRequest
    extends VisionRequest<List<BarcodeObservation>> {
  /// Creates a barcode request.
  const DetectBarcodesRequest({
    this.symbologies = const [],
    this.coalescesCompositeSymbologies,
    super.regionOfInterest,
  });

  /// Which symbologies to look for; all of them by default.
  ///
  /// See [AppleVision.supportedBarcodeSymbologies].
  final List<BarcodeSymbology> symbologies;

  /// Whether to merge the parts of a composite barcode into one observation.
  final bool? coalescesCompositeSymbologies;

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectBarcodes;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    symbologies: symbologies.map((value) => value._message).toList(),
    coalescesCompositeSymbologies: coalescesCompositeSymbologies,
  );

  @override
  List<BarcodeObservation> _decode(RequestResultMessage message) =>
      (message.barcodes ?? const [])
          .map(BarcodeObservation._)
          .toList(growable: false);
}

/// Finds faces and how they are turned.
///
/// Mirrors `DetectFaceRectanglesRequest`.
final class DetectFaceRectanglesRequest
    extends VisionRequest<List<FaceObservation>> {
  /// Creates a face-rectangle request.
  const DetectFaceRectanglesRequest({super.regionOfInterest});

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectFaceRectangles;

  @override
  List<FaceObservation> _decode(RequestResultMessage message) =>
      (message.faces ?? const [])
          .map(FaceObservation._)
          .toList(growable: false);
}

/// Finds faces and their landmarks: eyes, eyebrows, nose, lips and outline.
///
/// Mirrors `DetectFaceLandmarksRequest`.
final class DetectFaceLandmarksRequest
    extends VisionRequest<List<FaceObservation>> {
  /// Creates a face-landmark request.
  const DetectFaceLandmarksRequest({super.regionOfInterest});

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectFaceLandmarks;

  @override
  List<FaceObservation> _decode(RequestResultMessage message) =>
      (message.faces ?? const [])
          .map(FaceObservation._)
          .toList(growable: false);
}

/// Scores how usable each face is for recognition.
///
/// Mirrors `DetectFaceCaptureQualityRequest`.
final class DetectFaceCaptureQualityRequest
    extends VisionRequest<List<FaceObservation>> {
  /// Creates a capture-quality request.
  const DetectFaceCaptureQualityRequest({super.regionOfInterest});

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectFaceCaptureQuality;

  @override
  List<FaceObservation> _decode(RequestResultMessage message) =>
      (message.faces ?? const [])
          .map(FaceObservation._)
          .toList(growable: false);
}

/// Finds people.
///
/// Mirrors `DetectHumanRectanglesRequest`.
final class DetectHumanRectanglesRequest
    extends VisionRequest<List<HumanObservation>> {
  /// Creates a human-rectangle request.
  const DetectHumanRectanglesRequest({
    this.upperBodyOnly,
    super.regionOfInterest,
  });

  /// Whether to report only the upper body.
  final bool? upperBodyOnly;

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectHumanRectangles;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    upperBodyOnly: upperBodyOnly,
  );

  @override
  List<HumanObservation> _decode(RequestResultMessage message) =>
      (message.humans ?? const [])
          .map(HumanObservation._)
          .toList(growable: false);
}

/// Finds the joints of each person's body.
///
/// Mirrors `DetectHumanBodyPoseRequest`.
final class DetectHumanBodyPoseRequest
    extends VisionRequest<List<BodyPoseObservation>> {
  /// Creates a body-pose request.
  const DetectHumanBodyPoseRequest({this.detectsHands, super.regionOfInterest});

  /// Whether to include each person's hand poses.
  final bool? detectsHands;

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectHumanBodyPose;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    detectsHands: detectsHands,
  );

  @override
  List<BodyPoseObservation> _decode(RequestResultMessage message) =>
      (message.bodyPoses ?? const [])
          .map(BodyPoseObservation._)
          .toList(growable: false);
}

/// Finds the joints of each hand.
///
/// Mirrors `DetectHumanHandPoseRequest`.
final class DetectHumanHandPoseRequest
    extends VisionRequest<List<PoseObservation>> {
  /// Creates a hand-pose request.
  const DetectHumanHandPoseRequest({
    this.maximumHandCount,
    super.regionOfInterest,
  });

  /// How many hands to look for.
  final int? maximumHandCount;

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectHumanHandPose;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    maximumHandCount: maximumHandCount,
  );

  @override
  List<PoseObservation> _decode(RequestResultMessage message) =>
      (message.poses ?? const [])
          .map(PoseObservation._)
          .toList(growable: false);
}

/// Finds the joints of each cat or dog.
///
/// Mirrors `DetectAnimalBodyPoseRequest`.
final class DetectAnimalBodyPoseRequest
    extends VisionRequest<List<PoseObservation>> {
  /// Creates an animal-pose request.
  const DetectAnimalBodyPoseRequest({super.regionOfInterest});

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectAnimalBodyPose;

  @override
  List<PoseObservation> _decode(RequestResultMessage message) =>
      (message.poses ?? const [])
          .map(PoseObservation._)
          .toList(growable: false);
}

/// Finds cats and dogs.
///
/// Mirrors `RecognizeAnimalsRequest`.
final class RecognizeAnimalsRequest
    extends VisionRequest<List<RecognizedObject>> {
  /// Creates an animal-recognition request.
  const RecognizeAnimalsRequest({super.regionOfInterest});

  @override
  RequestKindMessage get _kind => RequestKindMessage.recognizeAnimals;

  @override
  List<RecognizedObject> _decode(RequestResultMessage message) =>
      (message.objects ?? const [])
          .map(RecognizedObject._)
          .toList(growable: false);
}

/// Labels the whole image, from a taxonomy of about 1300 identifiers.
///
/// Mirrors `ClassifyImageRequest`.
final class ClassifyImageRequest extends VisionRequest<List<Classification>> {
  /// Creates a classification request.
  const ClassifyImageRequest({this.cropAndScaleAction, super.regionOfInterest});

  /// How the image is fitted to the model's input.
  final CropAndScaleAction? cropAndScaleAction;

  @override
  RequestKindMessage get _kind => RequestKindMessage.classifyImage;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    cropAndScaleAction: cropAndScaleAction?._message,
  );

  @override
  List<Classification> _decode(RequestResultMessage message) =>
      (message.classifications ?? const [])
          .map(Classification._)
          .toList(growable: false);
}

/// Scores how pleasant and how useful an image is.
///
/// Mirrors `CalculateImageAestheticsScoresRequest`.
final class CalculateImageAestheticsScoresRequest
    extends VisionRequest<AestheticsScores> {
  /// Creates an aesthetics request.
  const CalculateImageAestheticsScoresRequest({
    this.cropAndScaleAction,
    super.regionOfInterest,
  });

  /// How the image is fitted to the model's input.
  final CropAndScaleAction? cropAndScaleAction;

  @override
  RequestKindMessage get _kind =>
      RequestKindMessage.calculateImageAestheticsScores;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    cropAndScaleAction: cropAndScaleAction?._message,
  );

  @override
  AestheticsScores _decode(RequestResultMessage message) =>
      AestheticsScores._(message.aesthetics!);
}

/// Finds the parts of an image a person would look at first.
///
/// Mirrors `GenerateAttentionBasedSaliencyImageRequest`.
final class GenerateAttentionBasedSaliencyImageRequest
    extends VisionRequest<Saliency> {
  /// Creates an attention-based saliency request.
  const GenerateAttentionBasedSaliencyImageRequest({super.regionOfInterest});

  @override
  RequestKindMessage get _kind =>
      RequestKindMessage.generateAttentionBasedSaliencyImage;

  @override
  Saliency _decode(RequestResultMessage message) =>
      Saliency._(message.saliency!);
}

/// Finds the parts of an image that hold objects.
///
/// Mirrors `GenerateObjectnessBasedSaliencyImageRequest`.
final class GenerateObjectnessBasedSaliencyImageRequest
    extends VisionRequest<Saliency> {
  /// Creates an objectness-based saliency request.
  const GenerateObjectnessBasedSaliencyImageRequest({super.regionOfInterest});

  @override
  RequestKindMessage get _kind =>
      RequestKindMessage.generateObjectnessBasedSaliencyImage;

  @override
  Saliency _decode(RequestResultMessage message) =>
      Saliency._(message.saliency!);
}

/// Separates people from the background.
///
/// Mirrors `GeneratePersonSegmentationRequest`. The mask is always produced,
/// even when there is nobody in the image, in which case it is all zeroes.
final class GeneratePersonSegmentationRequest extends VisionRequest<MaskImage> {
  /// Creates a person-segmentation request.
  const GeneratePersonSegmentationRequest({
    this.quality,
    super.regionOfInterest,
  });

  /// How carefully to work. Vision defaults to [SegmentationQuality.accurate].
  final SegmentationQuality? quality;

  @override
  RequestKindMessage get _kind => RequestKindMessage.generatePersonSegmentation;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    segmentationQuality: quality?._message,
  );

  @override
  MaskImage _decode(RequestResultMessage message) => MaskImage._(message.mask!);
}

/// Masks each person separately.
///
/// Mirrors `GeneratePersonInstanceMaskRequest`. The result is null when there
/// is nobody in the image.
final class GeneratePersonInstanceMaskRequest
    extends VisionRequest<InstanceMask?> {
  /// Creates a person-instance-mask request.
  const GeneratePersonInstanceMaskRequest({
    this.scaleMaskToImage = false,
    super.regionOfInterest,
  });

  /// Whether to scale the mask up to the analyzed image's size.
  final bool scaleMaskToImage;

  @override
  RequestKindMessage get _kind => RequestKindMessage.generatePersonInstanceMask;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    scaleMaskToImage: scaleMaskToImage,
  );

  @override
  InstanceMask? _decode(RequestResultMessage message) =>
      message.instanceMask == null
      ? null
      : InstanceMask._(message.instanceMask!);
}

/// Masks each foreground object separately.
///
/// Mirrors `GenerateForegroundInstanceMaskRequest`. The result is null when
/// Vision finds nothing in the foreground.
final class GenerateForegroundInstanceMaskRequest
    extends VisionRequest<InstanceMask?> {
  /// Creates a foreground-instance-mask request.
  const GenerateForegroundInstanceMaskRequest({
    this.scaleMaskToImage = false,
    super.regionOfInterest,
  });

  /// Whether to scale the mask up to the analyzed image's size.
  final bool scaleMaskToImage;

  @override
  RequestKindMessage get _kind =>
      RequestKindMessage.generateForegroundInstanceMask;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    scaleMaskToImage: scaleMaskToImage,
  );

  @override
  InstanceMask? _decode(RequestResultMessage message) =>
      message.instanceMask == null
      ? null
      : InstanceMask._(message.instanceMask!);
}

/// Finds the corners of a document in a photo.
///
/// Mirrors `DetectDocumentSegmentationRequest`. The result is null when no
/// document is found.
final class DetectDocumentSegmentationRequest
    extends VisionRequest<DocumentSegmentation?> {
  /// Creates a document-segmentation request.
  const DetectDocumentSegmentationRequest({
    this.includeMask = false,
    super.regionOfInterest,
  });

  /// Whether to return the full-size segmentation mask as well as the corners.
  final bool includeMask;

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectDocumentSegmentation;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    includeMask: includeMask,
  );

  @override
  DocumentSegmentation? _decode(RequestResultMessage message) =>
      message.documentSegmentation == null
      ? null
      : DocumentSegmentation._(message.documentSegmentation!);
}

/// Finds rectangular shapes.
///
/// Mirrors `DetectRectanglesRequest`.
final class DetectRectanglesRequest
    extends VisionRequest<List<NormalizedQuad>> {
  /// Creates a rectangle-detection request.
  const DetectRectanglesRequest({
    this.minimumAspectRatio,
    this.maximumAspectRatio,
    this.quadratureToleranceDegrees,
    this.minimumSize,
    this.minimumConfidence,
    this.maximumObservations,
    super.regionOfInterest,
  });

  /// The smallest width-to-height ratio to accept. Vision defaults to 0.5.
  final double? minimumAspectRatio;

  /// The largest width-to-height ratio to accept. Vision defaults to 1.
  final double? maximumAspectRatio;

  /// How far a corner may be from 90 degrees. Vision defaults to 30.
  final double? quadratureToleranceDegrees;

  /// The smallest rectangle to accept, as a fraction of the image. Vision
  /// defaults to 0.2.
  final double? minimumSize;

  /// The lowest confidence to report.
  final double? minimumConfidence;

  /// How many rectangles to report at most.
  final int? maximumObservations;

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectRectangles;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    minimumAspectRatio: minimumAspectRatio,
    maximumAspectRatio: maximumAspectRatio,
    quadratureToleranceDegrees: quadratureToleranceDegrees,
    minimumSize: minimumSize,
    minimumConfidence: minimumConfidence,
    maximumObservations: maximumObservations,
  );

  @override
  List<NormalizedQuad> _decode(RequestResultMessage message) =>
      (message.rectangles ?? const [])
          .map(NormalizedQuad._)
          .toList(growable: false);
}

/// Finds the horizon in a photo.
///
/// Mirrors `DetectHorizonRequest`. The result is null when Vision cannot
/// find a horizon, which is usual for synthetic images.
final class DetectHorizonRequest extends VisionRequest<Horizon?> {
  /// Creates a horizon request.
  const DetectHorizonRequest({super.regionOfInterest});

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectHorizon;

  @override
  Horizon? _decode(RequestResultMessage message) =>
      message.horizon == null ? null : Horizon._(message.horizon!);
}

/// Traces the outlines of the shapes in an image.
///
/// Mirrors `DetectContoursRequest`.
final class DetectContoursRequest extends VisionRequest<Contours> {
  /// Creates a contour request.
  const DetectContoursRequest({
    this.contrastAdjustment,
    this.contrastPivot,
    this.detectsDarkOnLight,
    this.maximumImageDimension,
    this.includePoints = false,
    super.regionOfInterest,
  });

  /// How much to boost contrast before tracing. Vision defaults to 2.
  final double? contrastAdjustment;

  /// The value contrast is adjusted around; null uses an automatic pivot.
  final double? contrastPivot;

  /// Whether the shapes are dark on a light background. Vision defaults to
  /// true.
  final bool? detectsDarkOnLight;

  /// The size the image is scaled to before tracing. Vision defaults to 512.
  final int? maximumImageDimension;

  /// Whether to return each contour's points.
  ///
  /// Contours can have thousands of points, so this is off by default.
  final bool includePoints;

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectContours;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    contrastAdjustment: contrastAdjustment,
    contrastPivot: contrastPivot,
    detectsDarkOnLight: detectsDarkOnLight,
    maximumImageDimension: maximumImageDimension,
    includeContourPoints: includePoints,
  );

  @override
  Contours _decode(RequestResultMessage message) =>
      Contours._(message.contours!);
}

/// Scores how smudged the camera lens looks.
///
/// Mirrors `DetectLensSmudgeRequest`. The result is the smudge confidence,
/// from 0 (clean) to 1 (smudged).
final class DetectLensSmudgeRequest extends VisionRequest<double> {
  /// Creates a lens-smudge request.
  const DetectLensSmudgeRequest({super.regionOfInterest});

  @override
  RequestKindMessage get _kind => RequestKindMessage.detectLensSmudge;

  @override
  double _decode(RequestResultMessage message) => message.smudge!.confidence;
}

/// Computes a vector that describes an image, for comparing images.
///
/// Mirrors `GenerateImageFeaturePrintRequest`.
final class GenerateImageFeaturePrintRequest
    extends VisionRequest<FeaturePrint> {
  /// Creates a feature-print request.
  const GenerateImageFeaturePrintRequest({
    this.cropAndScaleAction,
    super.regionOfInterest,
  });

  /// How the image is fitted to the model's input.
  final CropAndScaleAction? cropAndScaleAction;

  @override
  RequestKindMessage get _kind => RequestKindMessage.generateImageFeaturePrint;

  @override
  RequestMessage _toMessage() => RequestMessage(
    kind: _kind,
    regionOfInterest: regionOfInterest?._toMessage(),
    cropAndScaleAction: cropAndScaleAction?._message,
  );

  @override
  FeaturePrint _decode(RequestResultMessage message) =>
      FeaturePrint._(message.featurePrint!);
}
