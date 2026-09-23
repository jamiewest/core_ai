# apple_vision

Flutter bindings for Apple's Vision framework on iOS and macOS: text and
document recognition, barcodes, faces, body and hand poses, classification,
aesthetics, saliency, segmentation masks, rectangles, horizon, contours and
image feature prints.

It wraps Vision's modern Swift API (struct requests such as
`RecognizeTextRequest`, run on an `ImageRequestHandler`) over Pigeon platform
channels.

## Requirements

* iOS 27+ or macOS 27+ at runtime. The plugin builds for iOS 15 and macOS 12,
  and on older systems `AppleVision.isSupported()` returns `false`.
  Most of these requests exist in Vision from iOS 18 / macOS 15. The plugin
  still requires 27 because it copies masks and heat maps losslessly with
  their row stride, through `PixelBufferObservation.pixelBuffer`, which is
  new in 27.
* Xcode 27 SDK.
* No permissions are needed: Vision runs on images you already have.

## Quick start

```dart
import 'dart:developer';

import 'package:apple_vision/apple_vision.dart';

Future<void> readLabel(String path) async {
  if (!await AppleVision.isSupported()) return;

  // One request:
  final lines = await AppleVision.perform(
    ImageInput.file(path),
    const RecognizeTextRequest(customWords: ['Flutter']),
  );
  for (final line in lines) {
    log('${line.text} (${line.confidence})');
  }

  // Several requests on one decoded image, in one platform call:
  const barcodes = DetectBarcodesRequest(symbologies: [BarcodeSymbology.qr]);
  const labels = ClassifyImageRequest();
  const heat = GenerateAttentionBasedSaliencyImageRequest();
  final analysis = await AppleVision.analyze(
    ImageInput.file(path),
    requests: [barcodes, labels, heat],
    orientation: ImageOrientation.up,
  );
  for (final code in analysis.resultOf(barcodes)) {
    // Vision geometry is normalized with a lower-left origin; convert it to
    // Flutter pixels (upper-left origin) for drawing.
    final rect = code.quad.boundingBox.toImageCoordinates(analysis.imageSize);
    log('${code.payload} at $rect');
  }
  final png = await analysis.resultOf(heat).heatMap.toPng();
  log('heat map PNG: ${png.length} bytes');
}
```

Images come in as `ImageInput.file`, `ImageInput.asset` (a bundled Flutter
asset), `ImageInput.encoded` (PNG/JPEG/HEIF bytes) or `ImageInput.pixels`
(raw BGRA8888, for example a camera frame). Every request takes an optional
`regionOfInterest`.

### Coordinates

Every observation uses Vision's normalized space: `0...1` on both axes, with
the **origin at the lower-left corner** and y growing upwards.
`NormalizedRect.toImageCoordinates`, `NormalizedPoint.toImageCoordinates` and
`NormalizedQuad.toImageCoordinates` convert to pixels. They default to
Flutter's upper-left origin; pass `origin: CoordinateOrigin.lowerLeft` for
Core Graphics conventions. `VisionAnalysis.imageSize` is the analyzed image's
size after its orientation was applied.

### Masks

Heat maps and segmentation masks come back as a `MaskImage`: raw bytes plus
`width`, `height`, `bytesPerRow` and the Core Video `pixelFormatType`
(`L008`, `L00h` or `L00f`). Use `valueAt(x, y)` to sample it (normalized to
`0...1`, with y counted from the top), or `toPng()` for an 8-bit grayscale PNG
encoded natively.

### Errors

Calls throw `AppleVisionException` with a stable `AppleVisionErrorCode`:
`unsupported`, `invalidArgument`, `notFound`, `imageError`, `maskError`,
`visionError` or `unknown`. In `analyze`, a request that fails on its own
does not fail the others: `analysis.errorFor(request)` returns its error, and
`resultOf(request)` throws it.

## Swift to Dart mapping

| Vision (Swift) | apple_vision (Dart) | Result |
| --- | --- | --- |
| `ImageRequestHandler(_:orientation:)` + `perform` | `AppleVision.analyze` / `AppleVision.perform` | `VisionAnalysis` |
| `CGImagePropertyOrientation` | `ImageOrientation` | |
| `NormalizedRect` / `NormalizedPoint` / `QuadrilateralProviding` | `NormalizedRect` / `NormalizedPoint` / `NormalizedQuad` | |
| `CoordinateOrigin` | `CoordinateOrigin` | |
| `RecognizeTextRequest` | `RecognizeTextRequest` | `List<RecognizedTextObservation>` |
| `RecognizeDocumentsRequest` | `RecognizeDocumentsRequest` | `List<DocumentObservation>` |
| `DetectTextRectanglesRequest` | `DetectTextRectanglesRequest` | `List<TextRectangleObservation>` |
| `DetectBarcodesRequest` | `DetectBarcodesRequest` | `List<BarcodeObservation>` |
| `DetectFaceRectanglesRequest` | `DetectFaceRectanglesRequest` | `List<FaceObservation>` |
| `DetectFaceLandmarksRequest` | `DetectFaceLandmarksRequest` | `List<FaceObservation>` (with `landmarks`) |
| `DetectFaceCaptureQualityRequest` | `DetectFaceCaptureQualityRequest` | `List<FaceObservation>` (with `captureQuality`) |
| `DetectHumanRectanglesRequest` | `DetectHumanRectanglesRequest` | `List<HumanObservation>` |
| `DetectHumanBodyPoseRequest` | `DetectHumanBodyPoseRequest` | `List<BodyPoseObservation>` |
| `DetectHumanHandPoseRequest` | `DetectHumanHandPoseRequest` | `List<PoseObservation>` |
| `DetectAnimalBodyPoseRequest` | `DetectAnimalBodyPoseRequest` | `List<PoseObservation>` |
| `RecognizeAnimalsRequest` | `RecognizeAnimalsRequest` | `List<RecognizedObject>` |
| `ClassifyImageRequest` | `ClassifyImageRequest` | `List<Classification>` |
| `CalculateImageAestheticsScoresRequest` | `CalculateImageAestheticsScoresRequest` | `AestheticsScores` |
| `GenerateAttentionBasedSaliencyImageRequest` | same name | `Saliency` |
| `GenerateObjectnessBasedSaliencyImageRequest` | same name | `Saliency` |
| `GeneratePersonSegmentationRequest` | same name | `MaskImage` |
| `GeneratePersonInstanceMaskRequest` | same name | `InstanceMask?` |
| `GenerateForegroundInstanceMaskRequest` | same name | `InstanceMask?` |
| `DetectDocumentSegmentationRequest` | same name | `DocumentSegmentation?` |
| `DetectRectanglesRequest` | `DetectRectanglesRequest` | `List<NormalizedQuad>` |
| `DetectHorizonRequest` | `DetectHorizonRequest` | `Horizon?` |
| `DetectContoursRequest` | `DetectContoursRequest` | `Contours` |
| `DetectLensSmudgeRequest` | `DetectLensSmudgeRequest` | `double` (smudge confidence) |
| `GenerateImageFeaturePrintRequest` | `GenerateImageFeaturePrintRequest` | `FeaturePrint` |
| `FeaturePrintObservation.distance(to:)` | `FeaturePrint.distanceTo` / `FeaturePrint.distanceBetween` | `double` |
| `PixelBufferObservation` | `MaskImage` | |
| `VisionError` | `AppleVisionException` (`visionError`, `invalidArgument`, `imageError`, ...) | |

Other queries: `AppleVision.supportedRecognitionLanguages`,
`supportedBarcodeSymbologies`, `supportedClassificationIdentifiers` and
`imageSize`.

## Not bridged

* **Tracking and video-sequence requests** (`TrackObjectRequest`,
  `TrackRectangleRequest`, `TrackOpticalFlowRequest`, translational and
  homographic image registration, `DetectTrajectoriesRequest`,
  `VideoProcessor`, `TargetedImageRequestHandler`). They are stateful across
  frames and belong in a streaming camera or video API, which this still-image
  plugin does not have.
* **`GenerateIterativeSegmentationRequest`** (27+) is interactive and stateful.
* **`CoreMLRequest`** needs an `MLModel` and is not bridged. The `core_ml`
  package runs Core ML models directly; it does not expose them as Vision
  requests. The `core_ai` package runs `.aimodel` models.
* **`DetectHumanBodyPose3DRequest`** needs depth data (`AVDepthData`) to be
  useful, which cannot be passed from Dart.
* **Compute-device selection** (`setComputeDevice`) and **explicit
  revisions**: the plugin always uses Vision's defaults.
* **Per-instance masks and masked images** from `InstanceMaskObservation`
  (`generateMask(for:)`, `generateMaskedImage`). Only the combined
  all-instances mask is returned, optionally scaled to the image size.
* **Document structure beyond the top level**: nested containers inside
  table cells and list items are reduced to their text, and
  `DataDetector` matches are not returned.
* The deprecated `VN*Request` Objective-C API.

## Known behavior

* **First accurate text recognition is slow.** On first use in a newly
  built app, Vision compiles its accurate text model for the Neural Engine.
  On macOS 27 this took about 65 seconds; later calls took well under a
  second. `RecognitionLevel.fast` does not need the compile, but is less
  accurate: it read "FLUTTER" as "FLurrER" in the tests. Recognizing documents
  shares the same model.
* **That compile needs free disk space.** When the disk was almost full, it
  failed with `visionError` and a `CRImageReaderError.e5rtError(...)` detail.
  It succeeded once space was freed.
* **Contour areas** from `Contour.area` are measured with both axes scaled by
  the image width. On a 4:3 image, a contour that covers 49% of the
  normalized square reports about 0.37.
* **Saliency heat maps** are 68 × 68 `L00f` (float32) regardless of the image
  size. Objectness saliency may produce a heat map with no `salientObjects`.
* **Person segmentation** returns an 8-bit mask at a size Vision picks (it
  keeps the image's aspect ratio), and a mask of zeroes when nobody is in the
  image. The instance-mask requests return `null` instead.
* **Synthetic images** return empty lists for faces, poses, people and
  animals, and `null` for the horizon.
* Masks are copied through the platform channel. Person segmentation at
  `accurate` quality can be several megabytes; use `balanced` or `fast` for
  live use.

## Tests

Verified on macOS 27 with Xcode 27: 18 Dart unit tests and all 16 real Vision
integration tests pass. The iOS device debug build also succeeds with
`flutter build ios --no-codesign --debug`. Runtime behavior on an iOS device
has not been verified in these checks.

* `flutter test` runs the Dart unit tests against fake host APIs.
* `cd example && flutter test integration_test/apple_vision_test.dart -d macos`
  runs real Vision on bundled, deterministic images, rendered by
  `swift tool/make_assets.swift example/assets`.
* On a device:
  `flutter drive --driver=test_driver/integration_test.dart --target=integration_test/apple_vision_test.dart -d <device> --publish-port`.
