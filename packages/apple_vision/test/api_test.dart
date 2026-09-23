import 'dart:typed_data';

import 'package:apple_vision/apple_vision.dart';
import 'package:apple_vision/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

NormalizedPointMessage _p(double x, double y) =>
    NormalizedPointMessage(x: x, y: y);

QuadrilateralMessage _quad() => QuadrilateralMessage(
  topLeft: _p(0.1, 0.9),
  topRight: _p(0.9, 0.9),
  bottomRight: _p(0.9, 0.5),
  bottomLeft: _p(0.1, 0.5),
  boundingBox: NormalizedRectMessage(x: 0.1, y: 0.5, width: 0.8, height: 0.4),
  confidence: 0.75,
);

class FakeHost implements AppleVisionHostApi {
  final performed = <List<RequestMessage>>[];
  ImageInputMessage? lastImage;
  ImageOrientationMessage? lastOrientation;
  List<RequestResultMessage> Function(List<RequestMessage>)? respond;
  Object? throwOnPerform;

  @override
  Future<AnalysisMessage> perform(
    ImageInputMessage image,
    ImageOrientationMessage? orientation,
    List<RequestMessage> requests,
  ) async {
    if (throwOnPerform != null) throw throwOnPerform!;
    lastImage = image;
    lastOrientation = orientation;
    performed.add(requests);
    return AnalysisMessage(
      imageSize: ImageSizeMessage(width: 640, height: 480),
      results: respond!(requests),
    );
  }

  @override
  Future<double> featurePrintDistance(String tokenA, String tokenB) async =>
      tokenA == tokenB ? 0 : 1.5;

  @override
  Future<Uint8List> encodeMaskAsPng(MaskImageMessage mask) async =>
      Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, mask.width]);

  @override
  Future<List<BarcodeSymbologyMessage>> supportedBarcodeSymbologies() async => [
    BarcodeSymbologyMessage.qr,
    BarcodeSymbologyMessage.ean13,
  ];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakePlatform implements AppleVisionPlatformApi {
  FakePlatform({this.supported = true, this.paths = const {}});

  final bool supported;
  final Map<String, String> paths;

  @override
  Future<bool> isSupported() async => supported;

  @override
  Future<String?> assetPath(String assetKey, String? package) async =>
      paths[assetKey];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeHost host;

  setUp(() {
    host = FakeHost();
    AppleVisionBindings.instance = AppleVisionBindings(
      host: host,
      platform: FakePlatform(paths: {'assets/a.png': '/bundle/a.png'}),
    );
  });

  group('geometry', () {
    const size = Size(200, 100);

    test('Vision bottom-left quadrant maps to Flutter bottom-left', () {
      const rect = NormalizedRect(x: 0, y: 0, width: 0.5, height: 0.5);
      expect(
        rect.toImageCoordinates(size),
        const Rect.fromLTWH(0, 50, 100, 50),
      );
      expect(
        rect.toImageCoordinates(size, origin: CoordinateOrigin.lowerLeft),
        const Rect.fromLTWH(0, 0, 100, 50),
      );
    });

    test('a rect near the top has a small upper-left top', () {
      const rect = NormalizedRect(x: 0.25, y: 0.7, width: 0.5, height: 0.2);
      final pixels = rect.toImageCoordinates(size);
      expect(pixels.left, 50);
      expect(pixels.top, closeTo(10, 1e-9));
      expect(pixels.width, 100);
      expect(pixels.height, closeTo(20, 1e-9));
    });

    test('points flip vertically for upper-left origin', () {
      const point = NormalizedPoint(0.25, 0.8);
      final offset = point.toImageCoordinates(size);
      expect(offset.dx, 50);
      expect(offset.dy, closeTo(20, 1e-9));
      expect(
        point.toImageCoordinates(size, origin: CoordinateOrigin.lowerLeft),
        const Offset(50, 80),
      );
      expect(point.verticallyFlipped.y, closeTo(0.2, 1e-9));
    });

    test('verticallyFlipped rect keeps its size', () {
      const rect = NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.4);
      final flipped = rect.verticallyFlipped;
      expect(flipped.y, closeTo(0.4, 1e-9));
      expect(flipped.height, 0.4);
      expect(flipped.verticallyFlipped.y, closeTo(0.2, 1e-9));
    });
  });

  group('message mapping', () {
    test('requests are sent in order with their options', () async {
      host.respond = (requests) => [
        for (final r in requests) RequestResultMessage(kind: r.kind),
      ];
      const text = RecognizeTextRequest(
        recognitionLevel: RecognitionLevel.fast,
        recognitionLanguages: ['en-US'],
        customWords: ['Flutter'],
        usesLanguageCorrection: false,
        maximumCandidateCount: 3,
        regionOfInterest: NormalizedRect(x: 0, y: 0.5, width: 1, height: 0.5),
      );
      const barcodes = DetectBarcodesRequest(
        symbologies: [BarcodeSymbology.qr, BarcodeSymbology.microQr],
      );
      const rectangles = DetectRectanglesRequest(minimumSize: 0.3);
      await AppleVision.analyze(
        ImageInput.pixels(width: 2, height: 1, bytes: Uint8List(8)),
        requests: [text, barcodes, rectangles],
        orientation: ImageOrientation.right,
      );
      final sent = host.performed.single;
      expect(sent.map((r) => r.kind), [
        RequestKindMessage.recognizeText,
        RequestKindMessage.detectBarcodes,
        RequestKindMessage.detectRectangles,
      ]);
      expect(sent[0].recognitionLevel, RecognitionLevelMessage.fast);
      expect(sent[0].recognitionLanguages, ['en-US']);
      expect(sent[0].customWords, ['Flutter']);
      expect(sent[0].usesLanguageCorrection, isFalse);
      expect(sent[0].maximumCandidateCount, 3);
      expect(sent[0].regionOfInterest!.y, 0.5);
      expect(sent[1].symbologies, [
        BarcodeSymbologyMessage.qr,
        BarcodeSymbologyMessage.microQr,
      ]);
      expect(sent[2].minimumSize, 0.3);
      expect(host.lastOrientation, ImageOrientationMessage.right);
      expect(host.lastImage!.kind, ImageInputKindMessage.pixels);
      expect(host.lastImage!.width, 2);
    });

    test('results decode into typed observations', () async {
      const text = RecognizeTextRequest();
      const barcodes = DetectBarcodesRequest();
      const saliency = GenerateAttentionBasedSaliencyImageRequest();
      const mask = GenerateForegroundInstanceMaskRequest();
      host.respond = (_) => [
        RequestResultMessage(
          kind: RequestKindMessage.recognizeText,
          recognizedText: [
            RecognizedTextObservationMessage(
              quad: _quad(),
              candidates: [
                TextCandidateMessage(text: 'HELLO', confidence: 0.9),
                TextCandidateMessage(text: 'HELL0', confidence: 0.4),
              ],
              transcript: 'HELLO',
              isTitle: false,
              recognitionLanguages: ['en-Latn-US'],
              textDirection: TextDirectionMessage.leftToRight,
            ),
          ],
        ),
        RequestResultMessage(
          kind: RequestKindMessage.detectBarcodes,
          barcodes: [
            BarcodeObservationMessage(
              quad: _quad(),
              symbology: BarcodeSymbologyMessage.qr,
              payload: 'hi',
              isGs1DataCarrier: false,
              isColorInverted: false,
            ),
          ],
        ),
        RequestResultMessage(
          kind: RequestKindMessage.generateAttentionBasedSaliencyImage,
          saliency: SaliencyMessage(
            salientObjects: [],
            heatMap: MaskImageMessage(
              width: 2,
              height: 1,
              bytesPerRow: 8,
              pixelFormatType: MaskPixelFormat.oneComponent32Float,
              bytes: Float32List.fromList([0.25, 1]).buffer.asUint8List(),
            ),
            confidence: 1,
          ),
        ),
        RequestResultMessage(
          kind: RequestKindMessage.generateForegroundInstanceMask,
        ),
      ];
      final analysis = await AppleVision.analyze(
        const ImageInput.file('/x.png'),
        requests: [text, barcodes, saliency, mask],
      );
      expect(analysis.imageSize, const Size(640, 480));
      final line = analysis.resultOf(text).single;
      expect(line.text, 'HELLO');
      expect(line.confidence, 0.9);
      expect(line.candidates, hasLength(2));
      expect(line.textDirection, TextDirection.leftToRight);
      expect(line.quad.boundingBox.maxY, closeTo(0.9, 1e-9));
      final topLeft = line.quad.toImageCoordinates(analysis.imageSize).first;
      expect(topLeft.dx, closeTo(64, 1e-6));
      expect(topLeft.dy, closeTo(48, 1e-6));
      final code = analysis.resultOf(barcodes).single;
      expect(code.symbology, BarcodeSymbology.qr);
      expect(code.payload, 'hi');
      expect(code.confidence, 0.75);
      final heatMap = analysis.resultOf(saliency).heatMap;
      expect(heatMap.pixelFormat, 'L00f');
      expect(heatMap.valueAt(0, 0), 0.25);
      expect(heatMap.valueAt(1, 0), 1);
      expect(() => heatMap.valueAt(2, 0), throwsRangeError);
      expect(analysis.resultOf(mask), isNull);
    });

    test('8-bit and half-float masks sample correctly', () {
      final gray = MaskImage(
        width: 2,
        height: 2,
        bytesPerRow: 4,
        pixelFormatType: MaskPixelFormat.oneComponent8,
        bytes: Uint8List.fromList([0, 255, 9, 9, 51, 102, 9, 9]),
      );
      expect(gray.valueAt(1, 0), 1);
      expect(gray.valueAt(0, 1), closeTo(0.2, 1e-9));
      // Top row in Flutter space is Vision's y close to 1.
      expect(gray.valueAtPoint(const NormalizedPoint(0.9, 0.9)), 1);
      final half = MaskImage(
        width: 3,
        height: 1,
        bytesPerRow: 6,
        pixelFormatType: MaskPixelFormat.oneComponent16Half,
        // 1.0, 0.5, -2.0 in IEEE half precision, little endian.
        bytes: Uint8List.fromList([0x00, 0x3C, 0x00, 0x38, 0x00, 0xC0]),
      );
      expect(half.valueAt(0, 0), 1);
      expect(half.valueAt(1, 0), 0.5);
      expect(half.valueAt(2, 0), -2);
    });

    test('feature prints decode the vector and compare by token', () async {
      const request = GenerateImageFeaturePrintRequest();
      host.respond = (_) => [
        RequestResultMessage(
          kind: RequestKindMessage.generateImageFeaturePrint,
          featurePrint: FeaturePrintMessage(
            elementCount: 3,
            isDouble: false,
            data: Float32List.fromList([1, 2, 3]).buffer.asUint8List(),
            token: 'a',
            confidence: 1,
          ),
        ),
      ];
      final print = await AppleVision.perform(
        const ImageInput.file('/x.png'),
        request,
      );
      expect(print.vector, [1, 2, 3]);
      expect(await print.distanceTo(print), 0);
      expect(await FeaturePrint.distanceBetween('a', 'b'), 1.5);
    });

    test('mask PNG encoding goes through the host', () async {
      final png = await MaskImage(
        width: 7,
        height: 1,
        bytesPerRow: 7,
        pixelFormatType: MaskPixelFormat.oneComponent8,
        bytes: Uint8List(7),
      ).toPng();
      expect(png.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      expect(png.last, 7);
    });

    test('supported symbologies map back to the Dart enum', () async {
      expect(await AppleVision.supportedBarcodeSymbologies(), [
        BarcodeSymbology.qr,
        BarcodeSymbology.ean13,
      ]);
    });

    test('assets resolve through the platform API', () async {
      final input = await ImageInput.asset('assets/a.png');
      expect((input as FileImageInput).path, '/bundle/a.png');
      await expectLater(
        ImageInput.asset('assets/missing.png'),
        throwsA(
          isA<AppleVisionException>().having(
            (e) => e.code,
            'code',
            AppleVisionErrorCode.notFound,
          ),
        ),
      );
    });
  });

  group('errors', () {
    test('a failed request carries its own error', () async {
      const text = RecognizeTextRequest();
      const faces = DetectFaceRectanglesRequest();
      host.respond = (_) => [
        RequestResultMessage(
          kind: RequestKindMessage.recognizeText,
          error: ErrorMessage(
            code: 'vision_error',
            message: 'boom',
            details: 'VisionError.internalError',
          ),
        ),
        RequestResultMessage(
          kind: RequestKindMessage.detectFaceRectangles,
          faces: [],
        ),
      ];
      final analysis = await AppleVision.analyze(
        const ImageInput.file('/x.png'),
        requests: [text, faces],
      );
      expect(analysis.succeeded(text), isFalse);
      expect(analysis.errorFor(text)!.code, AppleVisionErrorCode.visionError);
      expect(analysis.errorFor(text)!.details, 'VisionError.internalError');
      expect(
        () => analysis.resultOf(text),
        throwsA(isA<AppleVisionException>()),
      );
      expect(analysis.resultOf(faces), isEmpty);
      expect(
        () => analysis.resultOf(const DetectHorizonRequest()),
        throwsStateError,
      );
    });

    test('perform rethrows the request error', () async {
      host.respond = (_) => [
        RequestResultMessage(
          kind: RequestKindMessage.detectContours,
          error: ErrorMessage(code: 'invalid_argument', message: 'bad'),
        ),
      ];
      await expectLater(
        AppleVision.perform(
          const ImageInput.file('/x.png'),
          const DetectContoursRequest(),
        ),
        throwsA(
          isA<AppleVisionException>().having(
            (e) => e.code,
            'code',
            AppleVisionErrorCode.invalidArgument,
          ),
        ),
      );
    });

    test('platform exceptions are translated', () async {
      host.throwOnPerform = PlatformException(
        code: 'not_found',
        message: 'No image file',
      );
      await expectLater(
        AppleVision.perform(
          const ImageInput.file('/nope.png'),
          const ClassifyImageRequest(),
        ),
        throwsA(
          isA<AppleVisionException>()
              .having((e) => e.code, 'code', AppleVisionErrorCode.notFound)
              .having((e) => e.message, 'message', 'No image file'),
        ),
      );
    });

    test('a missing host API means unsupported', () async {
      host.throwOnPerform = PlatformException(
        code: 'channel-error',
        message: 'Unable to establish connection on channel.',
      );
      await expectLater(
        AppleVision.perform(
          const ImageInput.file('/x.png'),
          const ClassifyImageRequest(),
        ),
        throwsA(
          isA<AppleVisionException>().having(
            (e) => e.code,
            'code',
            AppleVisionErrorCode.unsupported,
          ),
        ),
      );
    });

    test('unknown wire codes map to unknown', () {
      expect(
        AppleVisionErrorCode.fromWire('something_new'),
        AppleVisionErrorCode.unknown,
      );
    });

    test('an empty request list is rejected', () {
      expect(
        () => AppleVision.analyze(const ImageInput.file('/x'), requests: []),
        throwsArgumentError,
      );
    });

    test('isSupported reports the platform answer', () async {
      AppleVisionBindings.instance = AppleVisionBindings(
        host: host,
        platform: FakePlatform(supported: false),
      );
      expect(await AppleVision.isSupported(), isFalse);
    });
  });
}
