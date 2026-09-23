// Runs Vision for real on bundled, deterministic images rendered by
// tool/make_assets.swift. Run one file at a time:
//
//   flutter test integration_test/apple_vision_test.dart -d macos
import 'dart:developer';
import 'dart:io';

import 'package:apple_vision/apple_vision.dart';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late ImageInput ocr;
  late ImageInput qr;
  late ImageInput shapes;
  late ImageInput circle;
  late ImageInput document;

  setUpAll(() async {
    ocr = await ImageInput.asset('assets/ocr_text.png');
    qr = await ImageInput.asset('assets/qr_code.png');
    shapes = await ImageInput.asset('assets/shapes.png');
    circle = await ImageInput.asset('assets/shapes_circle.png');
    document = await ImageInput.asset('assets/document.png');
  });

  test('Vision is supported on this OS', () async {
    expect(await AppleVision.isSupported(), isTrue);
    log('platform: ${await AppleVision.platformVersion()}');
  });

  test('text recognition reads the rendered words', () async {
    final lines = await AppleVision.perform(ocr, const RecognizeTextRequest());
    log('OCR: ${lines.map((l) => '${l.text} ${l.quad.boundingBox}')}');
    expect(lines.map((l) => l.text), [
      'HELLO VISION',
      'FLUTTER PLUGIN',
      'APPLE SILICON',
    ]);
    for (final line in lines) {
      expect(line.confidence, greaterThan(0.5));
    }
    // The first line is drawn in the top third, so in Vision's lower-left
    // space its box sits high, and in Flutter's space it sits near the top.
    final top = lines.first.quad.boundingBox;
    expect(top.y, greaterThan(0.6));
    final pixels = top.toImageCoordinates(const Size(900, 420));
    expect(pixels.top, lessThan(140));
    expect(pixels.left, closeTo(60, 25));
  }, timeout: _firstTextRecognition);

  test('text recognition honours options and region of interest', () async {
    final lines = await AppleVision.perform(
      ocr,
      const RecognizeTextRequest(
        recognitionLevel: RecognitionLevel.fast,
        recognitionLanguages: ['en-US'],
        customWords: ['FLUTTER'],
        maximumCandidateCount: 3,
        regionOfInterest: NormalizedRect(x: 0, y: 0, width: 1, height: 0.4),
      ),
    );
    expect(lines.map((l) => l.text), ['APPLE SILICON']);
    expect(lines.single.candidates, isNotEmpty);
    final languages = await AppleVision.supportedRecognitionLanguages();
    expect(languages, contains(startsWith('en')));
  }, timeout: _firstTextRecognition);

  test('a QR code decodes to the exact payload', () async {
    final codes = await AppleVision.perform(
      qr,
      const DetectBarcodesRequest(symbologies: [BarcodeSymbology.qr]),
    );
    expect(codes, hasLength(1));
    expect(codes.single.symbology, BarcodeSymbology.qr);
    expect(codes.single.payload, 'apple_vision:qr-payload-42');
    final box = codes.single.quad.boundingBox;
    expect(box.x, closeTo(48 / 516, 0.03));
    expect(box.width, closeTo(420 / 516, 0.05));
    expect(
      await AppleVision.supportedBarcodeSymbologies(),
      contains(BarcodeSymbology.qr),
    );
  });

  test('several requests run on one image in one call', () async {
    const text = RecognizeTextRequest();
    const faces = DetectFaceRectanglesRequest();
    const classify = ClassifyImageRequest();
    const aesthetics = CalculateImageAestheticsScoresRequest();
    const smudge = DetectLensSmudgeRequest();
    const textRects = DetectTextRectanglesRequest(reportCharacterBoxes: true);
    final analysis = await AppleVision.analyze(
      ocr,
      requests: [text, faces, classify, aesthetics, smudge, textRects],
    );
    expect(analysis.imageSize, const Size(900, 420));
    expect(analysis.resultOf(text), hasLength(3));
    expect(analysis.resultOf(faces), isEmpty);
    final labels = analysis.resultOf(classify);
    log('classify: ${labels.take(5)}');
    expect(labels, isNotEmpty);
    final identifiers = await AppleVision.supportedClassificationIdentifiers();
    expect(identifiers.length, greaterThan(1000));
    for (final label in labels) {
      expect(identifiers, contains(label.identifier));
      expect(label.confidence, inInclusiveRange(0, 1));
    }
    expect(labels.first.identifier, 'document');
    final scores = analysis.resultOf(aesthetics);
    log('aesthetics: $scores smudge: ${analysis.resultOf(smudge)}');
    expect(scores.overallScore, inInclusiveRange(-1, 1));
    expect(analysis.resultOf(smudge), inInclusiveRange(0, 1));
    final rects = analysis.resultOf(textRects);
    expect(rects, hasLength(3));
    expect(rects.first.characterBoxes, isNotEmpty);
  }, timeout: _firstTextRecognition);

  test('synthetic images have no people, animals or horizon', () async {
    const body = DetectHumanBodyPoseRequest(detectsHands: true);
    const hands = DetectHumanHandPoseRequest(maximumHandCount: 2);
    const humans = DetectHumanRectanglesRequest();
    const landmarks = DetectFaceLandmarksRequest();
    const quality = DetectFaceCaptureQualityRequest();
    const animals = RecognizeAnimalsRequest();
    const animalPose = DetectAnimalBodyPoseRequest();
    const persons = GeneratePersonInstanceMaskRequest();
    const horizon = DetectHorizonRequest();
    final analysis = await AppleVision.analyze(
      ocr,
      requests: [
        body,
        hands,
        humans,
        landmarks,
        quality,
        animals,
        animalPose,
        persons,
        horizon,
      ],
    );
    for (final request in analysis.requests) {
      expect(analysis.errorFor(request), isNull, reason: '$request');
    }
    expect(analysis.resultOf(body), isEmpty);
    expect(analysis.resultOf(hands), isEmpty);
    expect(analysis.resultOf(humans), isEmpty);
    expect(analysis.resultOf(landmarks), isEmpty);
    expect(analysis.resultOf(quality), isEmpty);
    expect(analysis.resultOf(animals), isEmpty);
    expect(analysis.resultOf(animalPose), isEmpty);
    expect(analysis.resultOf(persons), isNull);
    expect(analysis.resultOf(horizon), isNull);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('identical images have zero feature-print distance', () async {
    const request = GenerateImageFeaturePrintRequest();
    final a = await AppleVision.perform(shapes, request);
    final b = await AppleVision.perform(shapes, request);
    final c = await AppleVision.perform(circle, request);
    final d = await AppleVision.perform(ocr, request);
    expect(a.elementCount, 768);
    expect(a.vector, hasLength(768));
    expect(await a.distanceTo(b), closeTo(0, 1e-6));
    final near = await a.distanceTo(c);
    final far = await a.distanceTo(d);
    log('feature print distances: circle $near, text $far');
    expect(near, greaterThan(0.01));
    expect(far, greaterThan(0.01));
    expect(await FeaturePrint.distanceBetween(a.token, b.token), 0);
  });

  test('saliency returns a heat map that encodes as PNG', () async {
    const attention = GenerateAttentionBasedSaliencyImageRequest();
    const objectness = GenerateObjectnessBasedSaliencyImageRequest();
    final analysis = await AppleVision.analyze(
      shapes,
      requests: [attention, objectness],
    );
    for (final saliency in [
      analysis.resultOf(attention),
      analysis.resultOf(objectness),
    ]) {
      final map = saliency.heatMap;
      log('heat map: $map objects: ${saliency.salientObjects.length}');
      expect(map.width, 68);
      expect(map.height, 68);
      expect(map.pixelFormatType, MaskPixelFormat.oneComponent32Float);
      expect(map.bytes.length, map.bytesPerRow * map.height);
      final png = await map.toPng();
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final decoded = await _decodeSize(png);
      expect(decoded, const Size(68, 68));
    }
  });

  test('person segmentation returns a mask of the right shape', () async {
    final mask = await AppleVision.perform(
      shapes,
      const GeneratePersonSegmentationRequest(
        quality: SegmentationQuality.balanced,
      ),
    );
    log('person segmentation: $mask');
    expect(mask.pixelFormatType, MaskPixelFormat.oneComponent8);
    // Vision keeps the image's aspect ratio (800 x 600 is 4:3).
    expect(mask.width / mask.height, closeTo(4 / 3, 0.02));
    expect(mask.bytes.length, mask.bytesPerRow * mask.height);
    // Nobody is in the picture.
    expect(mask.valueAt(mask.width ~/ 2, mask.height ~/ 2), lessThan(0.1));
    final png = await mask.toPng();
    expect(await _decodeSize(png), mask.size);
  });

  test('foreground instance mask scales to the image', () async {
    final native = await AppleVision.perform(
      circle,
      const GenerateForegroundInstanceMaskRequest(),
    );
    log('foreground mask: $native');
    expect(native, isNotNull);
    expect(native!.instances, isNotEmpty);
    expect(native.instances, isNot(contains(0)));
    final scaled = await AppleVision.perform(
      circle,
      const GenerateForegroundInstanceMaskRequest(scaleMaskToImage: true),
    );
    expect(scaled!.mask.size, const Size(800, 600));
    // The circle's centre belongs to an instance; the corner does not.
    expect(scaled.mask.valueAt(400, 300), greaterThan(0));
    expect(scaled.mask.valueAt(5, 5), 0);
  });

  test('a drawn rectangle is detected where it was drawn', () async {
    final rectangles = await AppleVision.perform(
      shapes,
      const DetectRectanglesRequest(minimumSize: 0.2, minimumConfidence: 0.5),
    );
    expect(rectangles, hasLength(1));
    final box = rectangles.single.boundingBox.toImageCoordinates(
      const Size(800, 600),
    );
    // Drawn at x 120..680 and (Core Graphics) y 90..510 on an 800 x 600
    // canvas, which is top 90..510 in Flutter space as it is centred.
    expect(box.left, closeTo(120, 6));
    expect(box.right, closeTo(680, 6));
    expect(box.top, closeTo(90, 6));
    expect(box.bottom, closeTo(510, 6));
  });

  test('contours trace the rectangle', () async {
    final contours = await AppleVision.perform(
      shapes,
      const DetectContoursRequest(includePoints: true),
    );
    log('contours: $contours ${contours.contours}');
    expect(contours.contourCount, greaterThanOrEqualTo(1));
    final outline = contours.contours.first;
    expect(outline.aspectRatio, closeTo(560 / 420, 0.05));
    // Vision measures contour areas with both axes scaled by the image
    // width, so the 0.49 normalized area comes back multiplied by 600 / 800.
    expect(outline.area, closeTo(0.49 * 600 / 800, 0.02));
    expect(outline.points, hasLength(outline.pointCount));
  });

  test('document segmentation and recognition find the page', () async {
    const segmentation = DetectDocumentSegmentationRequest(includeMask: true);
    const recognize = RecognizeDocumentsRequest();
    final analysis = await AppleVision.analyze(
      document,
      requests: [segmentation, recognize],
    );
    final documents = analysis.resultOf(recognize);
    log('documents: ${documents.map((d) => d.transcript)}');
    expect(documents, hasLength(1));
    expect(documents.single.transcript, contains('INVOICE 2026'));
    expect(documents.single.transcript, contains('35.50'));
    final page = analysis.resultOf(segmentation);
    log('document segmentation: $page');
    expect(page, isNotNull);
    final box = page!.quad.boundingBox.toImageCoordinates(
      const Size(1000, 760),
    );
    expect(box.left, closeTo(130, 40));
    expect(box.right, closeTo(870, 40));
    expect(page.mask, isNotNull);
  }, timeout: _firstTextRecognition);

  test('orientation is applied before analysis', () async {
    final size = await AppleVision.imageSize(
      ocr,
      orientation: ImageOrientation.right,
    );
    expect(size, const Size(420, 900));
  });

  test('encoded and pixel inputs work too', () async {
    final bytes = await rootBundle.load('assets/qr_code.png');
    final encoded = ImageInput.encoded(bytes.buffer.asUint8List());
    final codes = await AppleVision.perform(
      encoded,
      const DetectBarcodesRequest(),
    );
    expect(codes.single.payload, 'apple_vision:qr-payload-42');

    // A 64 x 32 BGRA image: white left half, black right half.
    final pixels = Uint8List(64 * 32 * 4);
    for (var y = 0; y < 32; y++) {
      for (var x = 0; x < 64; x++) {
        final value = x < 32 ? 255 : 0;
        final i = (y * 64 + x) * 4;
        pixels
          ..[i] = value
          ..[i + 1] = value
          ..[i + 2] = value
          ..[i + 3] = 255;
      }
    }
    final analysis = await AppleVision.analyze(
      ImageInput.pixels(width: 64, height: 32, bytes: pixels),
      requests: [const GenerateImageFeaturePrintRequest()],
    );
    expect(analysis.imageSize, const Size(64, 32));
  });

  test('errors carry stable codes', () async {
    await expectLater(
      AppleVision.perform(
        const ImageInput.file('/definitely/not/here.png'),
        const ClassifyImageRequest(),
      ),
      throwsA(
        isA<AppleVisionException>().having(
          (e) => e.code,
          'code',
          AppleVisionErrorCode.notFound,
        ),
      ),
    );
    await expectLater(
      AppleVision.perform(
        ImageInput.encoded(Uint8List.fromList([1, 2, 3])),
        const ClassifyImageRequest(),
      ),
      throwsA(
        isA<AppleVisionException>().having(
          (e) => e.code,
          'code',
          AppleVisionErrorCode.imageError,
        ),
      ),
    );
    await expectLater(
      AppleVision.perform(
        ImageInput.pixels(width: 10, height: 10, bytes: Uint8List(4)),
        const ClassifyImageRequest(),
      ),
      throwsA(
        isA<AppleVisionException>().having(
          (e) => e.code,
          'code',
          AppleVisionErrorCode.invalidArgument,
        ),
      ),
    );
    await expectLater(
      FeaturePrint.distanceBetween('not a token', 'nope'),
      throwsA(
        isA<AppleVisionException>().having(
          (e) => e.code,
          'code',
          AppleVisionErrorCode.invalidArgument,
        ),
      ),
    );
    expect(File('/definitely/not/here.png').existsSync(), isFalse);
  });
}

// The first accurate text recognition in a freshly installed app compiles
// Vision's text model, which took about 65 seconds on macOS 27.
const _firstTextRecognition = Timeout(Duration(minutes: 3));

Future<Size> _decodeSize(Uint8List png) async {
  final codec = await instantiateImageCodec(png);
  final frame = await codec.getNextFrame();
  return Size(frame.image.width.toDouble(), frame.image.height.toDouble());
}
