import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_playground/image_playground.dart';
import 'package:image_playground/testing.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a1ioAAAAASUVORK5CYII=',
  );
  Matcher code(ImagePlaygroundErrorCode value) =>
      isA<ImagePlaygroundException>().having((e) => e.code, 'code', value);
  tearDown(() async {
    final count = await ImagePlayground.liveHandleCount();
    await ImagePlayground.releaseAll();
    expect(count, 0, reason: 'Native session leaked');
  });
  testWidgets('real framework capabilities list known OS 27 styles', (_) async {
    expect(await ImagePlayground.isSupported(), isTrue);
    final caps = await ImagePlayground.capabilities();
    expect(caps.supportsVersion27Options, isTrue);
    expect(
      caps.styles,
      containsAll([
        ImagePlaygroundStyle.animation,
        ImagePlaygroundStyle.sketch,
        ImagePlaygroundStyle.any,
      ]),
    );
  });
  testWidgets('text and extracted concepts configure a real controller', (
    _,
  ) async {
    final session = await ImagePlayground.prepare(
      concepts: const [
        ImagePlaygroundConcept.text('A cat'),
        ImagePlaygroundConcept.extracted(
          'A cat sits beside a tree.',
          title: 'Story',
        ),
      ],
      allowedStyles: [
        ImagePlaygroundStyle.animation,
        ImagePlaygroundStyle.sketch,
      ],
      selectedStyle: ImagePlaygroundStyle.sketch,
      options: const ImagePlaygroundOptions(
        personalization: Personalization.disabled,
        variety: CreationVariety.low,
        strategy: CreationStrategy.generateNew,
        size: ImageSize(512, 512),
      ),
    );
    try {
      final info = await session.info();
      expect(info.conceptCount, 2);
      expect(info.hasSourceImage, isFalse);
      expect(info.allowedStyles, [
        ImagePlaygroundStyle.animation,
        ImagePlaygroundStyle.sketch,
      ]);
      expect(info.selectedStyle, ImagePlaygroundStyle.sketch);
      expect(info.isPresenting, isFalse);
    } finally {
      await session.dispose();
    }
  });
  testWidgets(
    'encoded and BGRA inputs become image concepts and source images',
    (_) async {
      final session = await ImagePlayground.prepare(
        concepts: [ImagePlaygroundConcept.image(ImageInput.encoded(png))],
        sourceImage: ImageInput.pixels(
          width: 2,
          height: 1,
          bgra: Uint8List.fromList([0, 0, 255, 255, 0, 255, 0, 255]),
        ),
      );
      try {
        final info = await session.info();
        expect(info.conceptCount, 1);
        expect(info.hasSourceImage, isTrue);
      } finally {
        await session.dispose();
      }
    },
  );
  testWidgets('local image files decode without user filesystem access', (
    _,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'image_playground_test_',
    );
    try {
      final file = await File('${directory.path}/input.png').writeAsBytes(png);
      final session = await ImagePlayground.prepare(
        sourceImage: ImageInput.file(file.path),
      );
      try {
        expect((await session.info()).hasSourceImage, isTrue);
      } finally {
        await session.dispose();
      }
    } finally {
      await directory.delete(recursive: true);
    }
  });
  testWidgets('invalid images and drawings fail without leaking handles', (
    _,
  ) async {
    await expectLater(
      ImagePlayground.prepare(
        sourceImage: ImageInput.encoded(Uint8List.fromList([1, 2, 3])),
      ),
      throwsA(code(ImagePlaygroundErrorCode.imageError)),
    );
    await expectLater(
      ImagePlayground.prepare(
        concepts: [
          ImagePlaygroundConcept.drawing(Uint8List.fromList([1, 2, 3])),
        ],
      ),
      throwsA(code(ImagePlaygroundErrorCode.imageError)),
    );
    await expectLater(
      ImagePlayground.prepare(
        sourceImage: const ImageInput.file('/missing/image.png'),
      ),
      throwsA(code(ImagePlaygroundErrorCode.notFound)),
    );
  });
  testWidgets('pixel dimensions and strides are checked before Core Graphics', (
    _,
  ) async {
    for (final input in [
      ImageInput.pixels(width: -1, height: 1, bgra: Uint8List(4)),
      ImageInput.pixels(
        width: 1,
        height: 1,
        bytesPerRow: 3,
        bgra: Uint8List(4),
      ),
      ImageInput.pixels(width: 1, height: 2, bgra: Uint8List(4)),
      ImageInput.pixels(
        width: 0x7fffffffffffffff,
        height: 4,
        bgra: Uint8List(4),
      ),
    ]) {
      await expectLater(
        ImagePlayground.prepare(sourceImage: input),
        throwsA(code(ImagePlaygroundErrorCode.invalidArgument)),
      );
    }
  });
  testWidgets(
    'invalid concepts, style lists and selected styles are rejected',
    (_) async {
      await expectLater(
        ImagePlayground.prepare(
          concepts: const [ImagePlaygroundConcept.text('  ')],
        ),
        throwsA(code(ImagePlaygroundErrorCode.invalidArgument)),
      );
      await expectLater(
        ImagePlayground.prepare(allowedStyles: []),
        throwsA(code(ImagePlaygroundErrorCode.invalidArgument)),
      );
      await expectLater(
        ImagePlayground.prepare(
          allowedStyles: [
            ImagePlaygroundStyle.sketch,
            ImagePlaygroundStyle.sketch,
          ],
        ),
        throwsA(code(ImagePlaygroundErrorCode.invalidArgument)),
      );
      await expectLater(
        ImagePlayground.prepare(
          allowedStyles: [ImagePlaygroundStyle.sketch],
          selectedStyle: ImagePlaygroundStyle.animation,
        ),
        throwsA(code(ImagePlaygroundErrorCode.invalidArgument)),
      );
    },
  );
  testWidgets('requested size rejects non-finite and nonpositive dimensions', (
    _,
  ) async {
    for (final size in [
      const ImageSize(0, 512),
      const ImageSize(double.nan, 1),
      const ImageSize(1, double.infinity),
    ]) {
      await expectLater(
        ImagePlayground.prepare(options: ImagePlaygroundOptions(size: size)),
        throwsA(code(ImagePlaygroundErrorCode.invalidArgument)),
      );
    }
  });
  testWidgets('cancel before presentation closes the native session', (
    _,
  ) async {
    final session = await ImagePlayground.prepare();
    final id = session.handle;
    await session.cancel();
    expect((await session.info()).isPresenting, isFalse);
    await session.dispose();
    await expectLater(
      ImagePlaygroundBindings.instance.host.info(id),
      throwsA(
        isA<PlatformException>().having(
          (e) => e.code,
          'code',
          'invalid_handle',
        ),
      ),
    );
  });
  testWidgets('releaseAll clears multiple native controllers', (_) async {
    final first = await ImagePlayground.prepare();
    final second = await ImagePlayground.prepare();
    expect(await ImagePlayground.liveHandleCount(), 2);
    expect(await ImagePlayground.releaseAll(), 2);
    await first.dispose();
    await second.dispose();
  });
  testWidgets('system sheet opens, rejects overlap, cancels and disposes', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('Sheet host'))),
    );
    await tester.pumpAndSettle();
    final caps = await ImagePlayground.capabilities();
    expect(
      caps.isAvailable,
      isTrue,
      reason: 'Enable Image Playground before this UI integration check.',
    );
    // Empty concepts avoid initiating image generation or choosing a provider.
    final session = await ImagePlayground.prepare();
    final other = await ImagePlayground.prepare();
    final result = session.present();
    try {
      for (var i = 0; i < 50 && !(await session.info()).isPresenting; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect((await session.info()).isPresenting, isTrue);
      await expectLater(
        other.present(),
        throwsA(code(ImagePlaygroundErrorCode.busy)),
      );
      await session.cancel();
      expect(await result.timeout(const Duration(seconds: 10)), isNull);
      expect((await session.info()).isPresenting, isFalse);
    } finally {
      await session.dispose();
      await other.dispose();
    }
    await tester.pumpAndSettle();
  });
}
