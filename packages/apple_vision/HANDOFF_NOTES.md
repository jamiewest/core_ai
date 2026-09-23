# apple_vision handoff notes

Status: complete for the implemented still-image API. Codex finished the
README/CHANGELOG review and independently reran formatting, analysis, all
18 unit tests, all 16 macOS integration tests, and the iOS device debug build
on 2026-09-22. All pass. An iPhone runtime run remains optional and unverified
by Codex. See `../../docs/CODEX_HANDOFF.md` for the continuation record.

## What is bridged

Vision's modern Swift API (struct requests on `ImageRequestHandler`), 25
requests, all through one host call, `perform(image, orientation,
requests)`. It decodes the image once and runs the requests in order on one
shared handler. A request that fails on its own comes back with its own
`ErrorMessage` and does not fail the rest of the call.

* Text: `RecognizeTextRequest` (level, languages, custom words, language
  correction, auto language, minimum text height, candidate count),
  `RecognizeDocumentsRequest` (flattened: transcript, title, paragraphs,
  tables as cell text, lists, barcodes), `DetectTextRectanglesRequest`.
* Barcodes: `DetectBarcodesRequest` (symbologies, composite coalescing,
  payload string and bytes).
* Faces and people: face rectangles, landmarks (13 named regions), capture
  quality, human rectangles, body pose (with hands), hand pose, animal body
  pose, `RecognizeAnimalsRequest`.
* Image-level: `ClassifyImageRequest`, `CalculateImageAestheticsScoresRequest`,
  `DetectLensSmudgeRequest`, `GenerateImageFeaturePrintRequest` (vector plus a
  token; `distanceTo` uses Vision's own `distance(to:)`).
* Masks: attention and objectness saliency (68x68 `L00f` heat map plus
  salient boxes), `GeneratePersonSegmentationRequest`, person and foreground
  instance masks (optionally scaled to image size through
  `generateScaledMask`), `DetectDocumentSegmentationRequest` (quad plus an
  optional mask).
* Geometry: `DetectRectanglesRequest` (all tuning options),
  `DetectHorizonRequest`, `DetectContoursRequest` (flattened tree, area,
  perimeter, bbox, optional points).
* Dart: sealed `ImageInput` (file, asset, encoded, BGRA pixels), an
  `ImageOrientation` enum, and a region of interest on every request. Typed
  results come from a generic `VisionRequest<R>` through
  `AppleVision.perform` or `analyze(...).resultOf(request)`. Geometry is
  normalized with Vision's lower-left origin, and
  `toImageCoordinates(size, origin:)` converts it (default upper-left).
  `MaskImage` holds raw bytes, `valueAt`, and `toPng()` (native ImageIO
  encoder).

## Not bridged, and why

* Tracking and video: `TrackObject`, `TrackRectangle`, `TrackOpticalFlow`,
  homographic and translational registration, `DetectTrajectories`,
  `VideoProcessor`, `TargetedImageRequestHandler`. They need frame sequences
  and stateful requests across calls.
* `GenerateIterativeSegmentationRequest` (27+) is interactive and stateful.
* `CoreMLRequest` needs an `MLModel` and is not bridged. The core_ml package
  runs Core ML models directly, without Vision requests; core_ai runs
  `.aimodel` models.
* `DetectHumanBodyPose3DRequest` wants depth data for useful output.
* Compute-device selection (`setComputeDevice`) and explicit revisions.
* `InstanceMaskObservation.generateMaskedImage` and per-instance masks.
  Only the all-instances mask is returned.
* `DataDetector` matches inside `DocumentObservation`, and nested
  containers inside table cells and list items, which are reduced to text.

## Design decisions

* The HostApi is gated at iOS 27 / macOS 27, although most requests exist
  from iOS 18 / macOS 15. The reason: `PixelBufferObservation.pixelBuffer`,
  the only lossless way to get mask bytes with their row stride, is 27+.
  `cgImage` is 8-bit, and `withUnsafePointer` gives no stride. The gate also
  means no inner `#available` checks for the 26+ members (`transcript`,
  document recognition, contour boxes).
* There is no handle registry. `FeaturePrintObservation` is `Codable`, and a
  probe showed that a JSON round trip keeps `distance(to:)` exact (0.0 for
  self, and an identical cross-distance). So Dart holds an opaque token of
  about 4.3 KB.
* Wire format: a flat `RequestMessage` and `RequestResultMessage` with a
  kind enum; the public Dart API is sealed classes.

## Verification (run on macOS 27.0, Xcode 27, Flutter 3.47)

* `flutter analyze` in the package and in the example: no issues.
* `flutter test` in the package: 18 unit tests pass, against fakes.
* `cd example && flutter test integration_test/apple_vision_test.dart -d macos`
  passes all 16 tests (real Vision). Concrete assertions include: exact OCR
  lines `HELLO VISION / FLUTTER PLUGIN / APPLE SILICON`; the region of
  interest restricting OCR to the bottom line; the exact QR payload
  `apple_vision:qr-payload-42`, with its box within 3% of where it was drawn;
  `document` as the top classification; a feature-print self-distance of 0
  and a positive distance to other images; 68x68 `L00f` heat maps whose PNGs
  decode to 68x68; the drawn rectangle within 6 px; the contour aspect ratio
  and area; the foreground mask scaled to 800x600, with the circle's centre
  inside the mask and the corner outside it; the document page corners
  within 40 px and the recognized transcript; empty results for
  faces, poses, people and animals, and null for the horizon, on synthetic
  images; and error codes for a missing file, bad bytes, short pixel data
  and a bad token.
* `cd example && flutter build ios --no-codesign --debug` builds
  `Runner.app`.

## Quirks found

* The first accurate `RecognizeTextRequest` in a newly built app compiles
  Vision's text model on the Neural Engine, which took about 65 s here.
  Later runs take about 0.4 s. The OCR tests have a 3-minute timeout for
  this. Fast level does not need the compile.
* When the disk was full (1.4 GiB free), that compile failed with
  `CRImageReaderError.e5rtError(... , 13)` or `(... compile call failed, 11)`,
  in both sandboxed and unsandboxed apps and in a CLI. It passed once about
  9 GiB was free. The plugin surfaces this as `vision_error`.
* `Contour.calculateArea()` scales both axes by the image width. A 0.49
  normalized area on a 4:3 image comes back as 0.3675.
* Fast OCR misreads "FLUTTER" as "FLurrER"; accurate reads it correctly.
* Objectness saliency reported no salient boxes for a single large
  rectangle, even though the heat map is produced.
* The person-segmentation mask is `L008` at a size Vision chooses, keeping
  the image's aspect ratio.

## Files

* `pigeons/apple_vision_api.dart` is the schema (regenerate with pigeon,
  then `dart format lib/src/messages.g.dart`).
* `darwin/.../AppleVisionHostApiImpl.swift` builds and runs requests,
  `ObservationBridge.swift` converts observations, `ImageBridge.swift`
  decodes images and handles masks and PNGs, and `Errors.swift` holds the
  codes (`unsupported`, `invalid_argument`, `not_found`, `image_error`,
  `mask_error`, `vision_error`).
* `lib/src/vision.dart` is the library with parts `geometry`,
  `image_input`, `mask`, `observations` and `requests`.
* `tool/make_assets.swift` regenerates `example/assets/*.png` (`swift
  tool/make_assets.swift example/assets`).
* `example/test_driver/integration_test.dart` is for `flutter drive` on a
  device.
