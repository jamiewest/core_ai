// End-to-end tests against the real MediaIntelligence framework:
//
//   cd example && flutter test integration_test/media_intelligence_test.dart -d macos
//
// There are no photos of people in this repository, so face tests use an
// image without faces. To also check grouping on your own photos, pass a
// directory of images with faces:
//
//   --dart-define=MEDIA_INTELLIGENCE_FACE_DIR=/path/to/photos

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_intelligence/media_intelligence.dart';
import 'package:media_intelligence/testing.dart';
import 'package:media_intelligence_example/fixtures.dart';

Matcher throwsMediaIntelligence(MediaIntelligenceErrorCode code) => throwsA(
  isA<MediaIntelligenceException>().having((e) => e.code, 'code', code),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late MediaFixtures fixtures;

  setUpAll(() async {
    expect(await MediaIntelligence.isSupported(), isTrue);
    await MediaIntelligence.releaseAll();
    fixtures = await MediaFixtures.load();
  });

  tearDownAll(() => fixtures.dispose());

  tearDown(() async {
    final live = await MediaIntelligence.liveHandleCount();
    final routed = MediaIntelligenceBindings.instance.activeRequestCount;
    await MediaIntelligence.releaseAll();
    expect(live, 0, reason: 'a test leaked face analyzers');
    expect(routed, 0, reason: 'a test leaked face requests');
  });

  group('video', () {
    testWidgets('finds the second scene as the highlight', (_) async {
      final analysis = await VideoAnalyzer.analyze(fixtures.clip);
      expect(analysis.highlightsError, isNull);
      expect(analysis.keyFrameError, isNull);

      final highlights = analysis.highlights!;
      expect(highlights.highlights, isNotEmpty);
      final first = highlights.highlights.first;
      expect(first.start.inMilliseconds, inInclusiveRange(2500, 3600));
      expect(first.end.inMilliseconds, inInclusiveRange(5000, 6100));

      // The levels tile the whole clip in order.
      final levels = highlights.levels;
      expect(levels, isNotEmpty);
      expect(levels.first.range.start, Duration.zero);
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i].range.start, levels[i - 1].range.end);
      }
      expect(levels.last.range.end.inMilliseconds, closeTo(6000, 100));
      final inHighlight = levels.where((l) => l.range.start >= first.start);
      expect(inHighlight.every((l) => l.level > 0), isTrue);
      expect(levels.first.level, lessThan(inHighlight.first.level));

      final keyFrame = analysis.keyFrame!;
      expect(keyFrame.inMilliseconds, inInclusiveRange(3000, 6000));
    });

    testWidgets('runs only the requested analysis', (_) async {
      final analysis = await VideoAnalyzer.analyze(
        fixtures.clip,
        highlights: false,
      );
      expect(analysis.highlights, isNull);
      expect(analysis.highlightsError, isNull);
      expect(analysis.keyFrame, isNotNull);
    });

    testWidgets('reports an unreadable video per analysis', (_) async {
      final analysis = await VideoAnalyzer.analyze(
        MediaAsset(id: 'not-a-video', path: fixtures.scene.path),
        highlights: false,
      );
      expect(analysis.keyFrame, isNull);
      expect(analysis.keyFrameError, isA<MediaIntelligenceException>());
    });

    testWidgets('rejects bad requests', (_) async {
      await expectLater(
        VideoAnalyzer.analyze(
          const MediaAsset(id: 'gone', path: '/nonexistent/clip.mp4'),
        ),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.notFound),
      );
      await expectLater(
        VideoAnalyzer.analyze(
          fixtures.clip,
          highlights: false,
          keyFrame: false,
        ),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.invalidArgument),
      );
    });
  });

  group('face groups', () {
    late String library;

    setUp(() async {
      library =
          '${fixtures.libraryDirectory}_${DateTime.now().microsecondsSinceEpoch}';
    });

    tearDown(() async {
      if (Directory(library).existsSync()) {
        await FaceGroupAnalyzer.purge(library);
      }
    });

    testWidgets('purging a library that does not exist fails', (_) async {
      await expectLater(
        FaceGroupAnalyzer.purge(library),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.workingDirectory),
      );
    });

    testWidgets('adds an image without faces', (_) async {
      final analyzer = await FaceGroupAnalyzer.open(library);
      expect(Directory(library).existsSync(), isTrue);
      expect(await analyzer.state(), FaceGroupState.ready);

      final results = await analyzer.insertOrUpdate([fixtures.scene]).toList();
      expect(results, hasLength(1));
      expect(results.single.assetId, 'scene');
      expect(results.single.faces, isEmpty);

      await analyzer.update();
      expect(await analyzer.state(), FaceGroupState.ready);
      expect(await analyzer.assetIds(), isEmpty);
      expect(await analyzer.entityIds(), isEmpty);
      expect(await analyzer.faces(), isEmpty);
      expect(await analyzer.assetIdsByEntity(), isEmpty);
      expect(await analyzer.facesByEntity(), isEmpty);
      expect(await analyzer.facesInAssets(['scene']), isEmpty);

      final identified = await analyzer.identifyFaces([
        fixtures.scene,
      ]).toList();
      expect(identified.single.faces, isEmpty);

      await analyzer.deleteAssets(['scene']);
      await analyzer.deleteAllAssets();
      await analyzer.dispose();
    });

    testWidgets('reopens a library and rejects a disposed analyzer', (_) async {
      final first = await FaceGroupAnalyzer.open(library);
      await first.insertOrUpdate([fixtures.scene]).drain<void>();
      await first.dispose();
      expect(first.isDisposed, isTrue);
      expect(first.state, throwsStateError);
      expect(
        () => first.insertOrUpdate([fixtures.scene]).first,
        throwsStateError,
      );

      final second = await FaceGroupAnalyzer.open(library);
      expect(await second.state(), FaceGroupState.ready);
      await second.dispose();
    });

    testWidgets('validates assets before analyzing', (_) async {
      final analyzer = await FaceGroupAnalyzer.open(library);
      await expectLater(
        analyzer.insertOrUpdate([fixtures.scene, fixtures.scene]).toList(),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.invalidArgument),
      );
      await expectLater(
        analyzer.insertOrUpdate(const [
          MediaAsset(id: 'gone', path: '/nonexistent/photo.jpg'),
        ]).toList(),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.notFound),
      );
      await expectLater(
        analyzer.identifyFaces(const []).toList(),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.invalidArgument),
      );
      await expectLater(
        analyzer.insertOrUpdate([
          MediaAsset(id: 'video', path: fixtures.clip.path),
        ]).toList(),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.faceGroupProcessing),
      );
      await analyzer.dispose();
    });

    testWidgets('stops routing a cancelled request', (_) async {
      final analyzer = await FaceGroupAnalyzer.open(library);
      final subscription = analyzer
          .insertOrUpdate([fixtures.scene])
          .listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      expect(MediaIntelligenceBindings.instance.activeRequestCount, 0);
      await analyzer.dispose();
    });

    testWidgets('releaseAll disposes every analyzer', (_) async {
      await FaceGroupAnalyzer.open(library);
      await FaceGroupAnalyzer.open(library);
      expect(await MediaIntelligence.liveHandleCount(), 2);
      expect(await MediaIntelligence.releaseAll(), 2);
    });

    testWidgets('groups faces in photos from MEDIA_INTELLIGENCE_FACE_DIR', (
      _,
    ) async {
      const faceDirectory = String.fromEnvironment(
        'MEDIA_INTELLIGENCE_FACE_DIR',
      );
      if (faceDirectory.isEmpty) {
        markTestSkipped(
          'Pass --dart-define=MEDIA_INTELLIGENCE_FACE_DIR=<photos of people> '
          'to check face grouping.',
        );
        return;
      }
      final photos = [
        for (final file in Directory(faceDirectory).listSync())
          if (RegExp(
            r'\.(jpe?g|png|heic)$',
            caseSensitive: false,
          ).hasMatch(file.path))
            MediaAsset(id: file.uri.pathSegments.last, path: file.path),
      ];
      expect(photos, isNotEmpty);
      final analyzer = await FaceGroupAnalyzer.open(library);
      final results = await analyzer.insertOrUpdate(photos).toList();
      expect(
        results.map((r) => r.assetId).toSet(),
        photos.map((p) => p.id).toSet(),
      );
      expect(results.expand((r) => r.faces), isNotEmpty);
      await analyzer.update();
      final entities = await analyzer.entityIds();
      expect(entities, isNotEmpty);
      final byEntity = await analyzer.facesByEntity();
      expect(byEntity.keys.toSet(), entities.toSet());
      await analyzer.dispose();
    });
  });
}
