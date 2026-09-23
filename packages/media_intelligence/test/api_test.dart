import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_intelligence/media_intelligence.dart';
import 'package:media_intelligence/testing.dart';

/// A fake host that records calls and lets tests drive callbacks.
class FakeHost implements MediaIntelligenceHostApi {
  final List<String> calls = [];
  final List<int> released = [];
  final List<int> cancelled = [];
  final Map<int, List<AssetMessage>> started = {};
  PlatformException? nextError;
  VideoAnalysisMessage video = VideoAnalysisMessage();
  List<Object?> lastVideoArguments = [];
  int _nextHandle = 7;

  void _maybeThrow() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }

  @override
  Future<int> openFaceGroupAnalyzer(String workingDirectory) async {
    _maybeThrow();
    calls.add('open $workingDirectory');
    return _nextHandle++;
  }

  @override
  Future<void> purgeFaceGroups(String workingDirectory) async =>
      calls.add('purge $workingDirectory');

  @override
  Future<FaceGroupStateMessage> faceGroupState(int handle) async =>
      FaceGroupStateMessage.stale;

  @override
  Future<void> startInsertOrUpdateAssets(
    int handle,
    int requestId,
    List<AssetMessage> assets,
  ) async {
    _maybeThrow();
    started[requestId] = assets;
  }

  @override
  Future<void> startIdentifyFaces(
    int handle,
    int requestId,
    List<AssetMessage> assets,
  ) async {
    _maybeThrow();
    started[requestId] = assets;
  }

  @override
  Future<void> cancel(int requestId) async => cancelled.add(requestId);

  @override
  Future<List<String>> allEntityIds(int handle) async => ['person-1'];

  @override
  Future<List<AssetGroupMessage>> allAssetIdsByEntity(int handle) async => [
    AssetGroupMessage(entityId: 'person-1', assetIds: ['a', 'b']),
  ];

  @override
  Future<List<FaceGroupMessage>> facesInAssets(
    int handle,
    List<String> assetIds,
  ) async => [
    FaceGroupMessage(key: 'a', faces: [face('f1', 'a')]),
  ];

  @override
  Future<VideoAnalysisMessage> analyzeVideo(
    AssetMessage asset,
    bool highlights,
    bool keyFrame,
  ) async {
    _maybeThrow();
    lastVideoArguments = [asset.id, asset.path, highlights, keyFrame];
    return video;
  }

  @override
  Future<void> release(int handle) async => released.add(handle);

  @override
  Future<int> releaseAll() async => 0;

  @override
  Future<int> liveHandleCount() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakeHost: ${invocation.memberName}');
}

class FakePlatform implements MediaIntelligencePlatformApi {
  FakePlatform({this.error});

  final PlatformException? error;

  @override
  Future<bool> isSupported() async {
    if (error case final error?) throw error;
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('FakePlatform: ${invocation.memberName}');
}

FaceMessage face(String id, String assetId, {String? entityId}) => FaceMessage(
  id: id,
  assetId: assetId,
  entityId: entityId,
  x: 0.25,
  y: 0.5,
  width: 0.1,
  height: 0.2,
);

Matcher throwsMediaIntelligence(MediaIntelligenceErrorCode code) => throwsA(
  isA<MediaIntelligenceException>().having((e) => e.code, 'code', code),
);

void main() {
  late FakeHost host;
  late MediaIntelligenceBindings bindings;

  setUp(() {
    host = FakeHost();
    bindings = MediaIntelligenceBindings(
      host: host,
      platform: FakePlatform(),
      registerCallbacks: false,
    );
    MediaIntelligenceBindings.instance = bindings;
  });

  test('enums match the Pigeon enums name for name', () {
    expect(
      FaceGroupState.values.map((e) => e.name),
      FaceGroupStateMessage.values.map((e) => e.name),
    );
  });

  group('face groups', () {
    test('streams per-asset faces until completion', () async {
      final analyzer = await FaceGroupAnalyzer.open('/library');
      expect(host.calls, ['open /library']);
      expect(analyzer.workingDirectory, '/library');

      final events = <AssetFaces>[];
      final done = analyzer
          .insertOrUpdate(const [MediaAsset(id: 'a', path: '/a.jpg')])
          .forEach(events.add);
      await pumpEventQueue();

      final requestId = host.started.keys.single;
      expect(host.started[requestId]!.single.path, '/a.jpg');
      bindings.callbackHandler
        ..onAssetFaces(
          requestId,
          FaceGroupMessage(
            key: 'a',
            faces: [face('f1', 'a', entityId: 'p')],
          ),
        )
        ..onComplete(requestId);
      await done;

      expect(events.single.assetId, 'a');
      final found = events.single.faces.single;
      expect(found.id, 'f1');
      expect(found.entityId, 'p');
      expect(found.bounds, const Rect.fromLTWH(0.25, 0.5, 0.1, 0.2));
      expect(bindings.activeRequestCount, 0);
    });

    test('delivers a native failure as a stream error', () async {
      final analyzer = await FaceGroupAnalyzer.open('/library');
      final result = analyzer.identifyFaces(const [
        MediaAsset(id: 'a', path: '/a.jpg'),
      ]).toList();
      await pumpEventQueue();
      bindings.callbackHandler.onError(
        host.started.keys.single,
        RequestErrorMessage(
          code: 'face_group_processing',
          message: 'Cannot load',
        ),
      );
      await expectLater(
        result,
        throwsMediaIntelligence(MediaIntelligenceErrorCode.faceGroupProcessing),
      );
      expect(bindings.activeRequestCount, 0);
    });

    test('reports a rejected start as a stream error', () async {
      final analyzer = await FaceGroupAnalyzer.open('/library');
      host.nextError = PlatformException(code: 'not_found', message: 'gone');
      await expectLater(
        analyzer.insertOrUpdate(const [
          MediaAsset(id: 'a', path: '/a.jpg'),
        ]).toList(),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.notFound),
      );
      expect(bindings.activeRequestCount, 0);
    });

    test(
      'cancelling a subscription cancels natively and drops events',
      () async {
        final analyzer = await FaceGroupAnalyzer.open('/library');
        final events = <AssetFaces>[];
        final subscription = analyzer
            .insertOrUpdate(const [MediaAsset(id: 'a', path: '/a.jpg')])
            .listen(events.add);
        await pumpEventQueue();
        final requestId = host.started.keys.single;
        await subscription.cancel();

        expect(host.cancelled, [requestId]);
        bindings.callbackHandler.onAssetFaces(
          requestId,
          FaceGroupMessage(key: 'a', faces: []),
        );
        expect(events, isEmpty);
        expect(bindings.activeRequestCount, 0);
      },
    );

    test('does no work until the stream is listened to', () async {
      final analyzer = await FaceGroupAnalyzer.open('/library');
      analyzer.insertOrUpdate(const [MediaAsset(id: 'a', path: '/a.jpg')]);
      await pumpEventQueue();
      expect(host.started, isEmpty);
    });

    test('maps queries', () async {
      final analyzer = await FaceGroupAnalyzer.open('/library');
      expect(await analyzer.state(), FaceGroupState.stale);
      expect(await analyzer.entityIds(), ['person-1']);
      expect(await analyzer.assetIdsByEntity(), {
        'person-1': ['a', 'b'],
      });
      final inAssets = await analyzer.facesInAssets(['a']);
      expect(inAssets['a']!.single.id, 'f1');
    });

    test('dispose releases once and blocks further use', () async {
      final analyzer = await FaceGroupAnalyzer.open('/library');
      await analyzer.dispose();
      await analyzer.dispose();
      expect(host.released, [7]);
      expect(analyzer.state, throwsStateError);
      await expectLater(
        analyzer.insertOrUpdate(const []).toList(),
        throwsStateError,
      );
    });

    test('purge forwards the directory', () async {
      await FaceGroupAnalyzer.purge('/library');
      expect(host.calls, ['purge /library']);
    });
  });

  group('video', () {
    test('converts results and per-request errors', () async {
      host.video = VideoAnalysisMessage(
        highlights: [TimeRangeMessage(startSeconds: 3.1, durationSeconds: 2.9)],
        highlightLevels: [
          HighlightLevelMessage(
            range: TimeRangeMessage(startSeconds: 0, durationSeconds: 0.5),
            level: 0,
          ),
        ],
        keyFrameError: RequestErrorMessage(
          code: 'media_processing',
          message: 'bad',
        ),
      );
      final analysis = await VideoAnalyzer.analyze(
        const MediaAsset(id: 'v', path: '/v.mp4'),
      );
      expect(host.lastVideoArguments, ['v', '/v.mp4', true, true]);
      final highlight = analysis.highlights!.highlights.single;
      expect(highlight.start, const Duration(milliseconds: 3100));
      expect(highlight.end, const Duration(seconds: 6));
      expect(analysis.highlights!.levels.single.level, 0);
      expect(analysis.keyFrame, isNull);
      expect(
        analysis.keyFrameError?.code,
        MediaIntelligenceErrorCode.mediaProcessing,
      );
    });

    test('passes the requested analyses', () async {
      host.video = VideoAnalysisMessage(keyFrameSeconds: 5);
      final analysis = await VideoAnalyzer.analyze(
        const MediaAsset(id: 'v', path: '/v.mp4'),
        highlights: false,
      );
      expect(host.lastVideoArguments.skip(2), [false, true]);
      expect(analysis.keyFrame, const Duration(seconds: 5));
      expect(analysis.highlights, isNull);
    });
  });

  group('errors', () {
    test('translates wire codes and keeps unknown ones', () async {
      host.nextError = PlatformException(code: 'working_directory');
      await expectLater(
        FaceGroupAnalyzer.open('/x'),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.workingDirectory),
      );
      host.nextError = PlatformException(code: 'brand_new_code');
      await expectLater(
        VideoAnalyzer.analyze(const MediaAsset(id: 'v', path: '/v')),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.unknown),
      );
    });

    test('treats a missing channel as unsupported', () async {
      host.nextError = PlatformException(code: 'channel-error');
      await expectLater(
        FaceGroupAnalyzer.open('/x'),
        throwsMediaIntelligence(MediaIntelligenceErrorCode.unsupported),
      );
    });

    test('isSupported is false when the platform call fails', () async {
      expect(await MediaIntelligence.isSupported(), isTrue);
      MediaIntelligenceBindings.instance = MediaIntelligenceBindings(
        host: host,
        platform: FakePlatform(error: PlatformException(code: 'channel-error')),
        registerCallbacks: false,
      );
      expect(await MediaIntelligence.isSupported(), isFalse);
    });
  });
}
