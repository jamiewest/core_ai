import 'dart:async';
import 'dart:typed_data';

import 'package:apple_sound_analysis/apple_sound_analysis.dart';
import 'package:apple_sound_analysis/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform implements AppleSoundAnalysisPlatformApi {
  @override
  Future<bool> isSupported() async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeHost implements AppleSoundAnalysisHostApi {
  late SoundAnalysisBindings bindings;
  final calls = <String>[];
  final samples = <Uint8List>[];
  final running = <int>{};
  Completer<void>? startGate;
  Completer<void>? sampleGate;
  PlatformException? startError;
  PlatformException? sampleError;
  bool resultDuringStart = false;
  ClassifierConfigMessage? config;
  AudioFormatMessage? format;

  void result(int id) => bindings.callbackHandler.onResult(
    ClassificationResultMessage(
      requestId: id,
      startSeconds: 1.5,
      durationSeconds: 3,
      classifications: [
        ClassificationMessage(identifier: 'speech', confidence: 0.9),
      ],
    ),
  );
  void complete(int id) {
    running.remove(id);
    bindings.callbackHandler.onComplete(id);
  }

  Future<void> _start(int id, ClassifierConfigMessage value) async {
    calls.add('start:$id');
    config = value;
    if (startGate != null) await startGate!.future;
    if (startError != null) throw startError!;
    running.add(id);
    if (resultDuringStart) {
      result(id);
      complete(id);
    }
  }

  @override
  Future<void> startFileAnalysis(
    int requestId,
    String path,
    ClassifierConfigMessage config,
    int? maximumClassifications,
  ) => _start(requestId, config);
  @override
  Future<void> startMicrophoneAnalysis(
    int requestId,
    ClassifierConfigMessage config,
    int? maximumClassifications,
  ) => _start(requestId, config);
  @override
  Future<void> startStreamAnalysis(
    int requestId,
    AudioFormatMessage format,
    ClassifierConfigMessage config,
    int? maximumClassifications,
  ) {
    this.format = format;
    return _start(requestId, config);
  }

  @override
  Future<void> analyzeSamples(int requestId, Uint8List float32Samples) async {
    calls.add('samples:$requestId');
    if (sampleGate != null) await sampleGate!.future;
    final error = sampleError;
    sampleError = null;
    if (error != null) throw error;
    samples.add(float32Samples);
  }

  @override
  Future<void> completeStreamAnalysis(int requestId) async {
    calls.add('complete:$requestId');
    result(requestId);
    complete(requestId);
  }

  @override
  Future<void> cancel(int requestId) async {
    calls.add('cancel:$requestId');
    running.remove(requestId);
  }

  @override
  Future<int> cancelAll() async {
    calls.add('cancelAll');
    final count = running.length;
    running.clear();
    return count;
  }

  @override
  Future<ClassifierInfoMessage> classifierInfo(
    ClassifierConfigMessage config,
  ) async {
    this.config = config;
    return ClassifierInfoMessage(
      knownClassifications: ['speech', 'tone'],
      windowDurationSeconds: 3,
      overlapFactor: 0.5,
      allowedWindowDurationsSeconds: [],
      minimumWindowSeconds: 0.5,
      maximumWindowSeconds: 15,
    );
  }

  @override
  Future<MicrophonePermissionMessage> microphonePermission() async =>
      MicrophonePermissionMessage.denied;
  @override
  Future<bool> requestMicrophonePermission() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SoundAnalysisBindings previous;
  late SoundAnalysisBindings bindings;
  late FakeHost host;
  setUp(() {
    previous = SoundAnalysisBindings.instance;
    host = FakeHost();
    bindings = SoundAnalysisBindings(
      host: host,
      platform: FakePlatform(),
      registerCallbacks: false,
    );
    host.bindings = bindings;
    SoundAnalysisBindings.instance = bindings;
  });
  tearDown(() {
    expect(bindings.analyses, isEmpty, reason: 'Dart callback route leaked');
    expect(host.running, isEmpty, reason: 'native analysis leaked');
    SoundAnalysisBindings.instance = previous;
  });

  test(
    'classifier info forwards model settings and exposes immutable labels',
    () async {
      final info = await const SoundClassifier.model(
        '/model.mlmodel',
        windowDurationSeconds: 1,
        overlapFactor: 0,
      ).info();
      expect(host.config!.modelPath, '/model.mlmodel');
      expect(host.config!.windowDurationSeconds, 1);
      expect(host.config!.overlapFactor, 0);
      expect(info.knownClassifications, ['speech', 'tone']);
      expect(info.minimumWindowSeconds, 0.5);
      expect(
        () => info.knownClassifications.add('other'),
        throwsUnsupportedError,
      );
    },
  );

  test(
    'file starts on listen and preserves callbacks before startup returns',
    () async {
      host.resultDuringStart = true;
      final stream = SoundAnalyzer.classifyFile('/audio.wav');
      expect(host.calls, isEmpty);
      final results = await stream.toList();
      expect(results.single.top!.identifier, 'speech');
      expect(results.single.top!.confidence, 0.9);
      expect(results.single.startSeconds, 1.5);
      expect(results.single.durationSeconds, 3);
      expect(host.calls, ['start:1']);
    },
  );

  test(
    'cancelling during startup waits then cancels the native request',
    () async {
      host.startGate = Completer<void>();
      final sub = SoundAnalyzer.classifyFile(
        '/audio.wav',
      ).listen((_) => fail('late event'));
      final cancelled = sub.cancel();
      expect(host.calls, ['start:1']);
      host.startGate!.complete();
      await cancelled;
      expect(host.calls, ['start:1', 'cancel:1']);
      host.result(1);
    },
  );

  test('startup errors reach the stream and release routing', () async {
    host.startError = PlatformException(
      code: 'invalid_file',
      message: 'bad file',
    );
    await expectLater(
      SoundAnalyzer.classifyFile('/bad'),
      emitsInOrder([
        emitsError(
          isA<SoundAnalysisException>().having(
            (e) => e.code,
            'code',
            SoundAnalysisErrorCode.invalidFile,
          ),
        ),
        emitsDone,
      ]),
    );
  });

  test('asynchronous native errors close microphone results', () async {
    final stream = SoundAnalyzer.classifyMicrophone();
    final expectation = expectLater(
      stream,
      emitsInOrder([
        emitsError(
          isA<SoundAnalysisException>().having(
            (e) => e.code,
            'code',
            SoundAnalysisErrorCode.permissionDenied,
          ),
        ),
        emitsDone,
      ]),
    );
    await Future<void>.delayed(Duration.zero);
    host.running.remove(1);
    bindings.callbackHandler.onError(1, 'permission_denied', 'denied', null);
    await expectation;
  });

  test('cancelAll waits for pending starts and closes every stream', () async {
    host.startGate = Completer<void>();
    final a = SoundAnalyzer.classifyFile('/a').toList();
    final b = SoundAnalyzer.classifyMicrophone().toList();
    final cancelled = SoundAnalyzer.cancelAll();
    host.startGate!.complete();
    expect(await cancelled, 2);
    expect(await a, isEmpty);
    expect(await b, isEmpty);
    expect(host.calls.last, 'cancelAll');
  });

  test('PCM copies a subview as little-endian interleaved samples', () async {
    final stream = await SoundStreamClassifier.create(
      sampleRate: 16000,
      channelCount: 2,
    );
    final original = Float32List.fromList([99, 1, -0.5, 0.25, 0, 88]);
    final subview = Float32List.sublistView(original, 1, 5);
    final adding = stream.add(subview);
    original.fillRange(0, original.length, 7);
    await adding;
    final bytes = ByteData.sublistView(host.samples.single);
    expect(
      [for (var i = 0; i < 4; i++) bytes.getFloat32(i * 4, Endian.little)],
      [1, -0.5, 0.25, 0],
    );
    expect(host.format!.channelCount, 2);
    await stream.cancel();
  });

  test('PCM serializes adds before close and buffers final results', () async {
    final stream = await SoundStreamClassifier.create(sampleRate: 16000);
    host.sampleGate = Completer<void>();
    final a = stream.add(Float32List.fromList([0.1]));
    final b = stream.add(Float32List.fromList([0.2]));
    final closed = stream.close();
    await Future<void>.delayed(Duration.zero);
    expect(host.calls, ['start:1', 'samples:1']);
    host.sampleGate!.complete();
    await Future.wait([a, b, closed]);
    final results = await stream.results.toList();
    expect(results.single.top!.identifier, 'speech');
    await stream.close();
    expect(host.calls, ['start:1', 'samples:1', 'samples:1', 'complete:1']);
    expect(() => stream.add(Float32List(1)), throwsStateError);
  });

  test('invalid PCM frames do not poison subsequent input', () async {
    final stream = await SoundStreamClassifier.create(
      sampleRate: 16000,
      channelCount: 2,
    );
    expect(() => stream.add(Float32List(1)), throwsArgumentError);
    expect(
      () => stream.add(Float32List.fromList([double.nan, 0])),
      throwsArgumentError,
    );
    await stream.add(Float32List(2));
    await stream.cancel();
    await stream.cancel();
    expect(host.calls.where((c) => c == 'cancel:1'), hasLength(1));
  });

  test(
    'cancelling results cancels PCM input and rejects later samples',
    () async {
      final stream = await SoundStreamClassifier.create(sampleRate: 16000);
      await stream.results.listen((_) {}).cancel();
      expect(() => stream.add(Float32List(1)), throwsStateError);
    },
  );

  test('failed PCM startup throws and cleans routing', () async {
    host.startError = PlatformException(code: 'invalid_format');
    await expectLater(
      SoundStreamClassifier.create(sampleRate: 16000),
      throwsA(isA<SoundAnalysisException>()),
    );
  });

  test(
    'a rejected PCM write does not prevent later writes or completion',
    () async {
      final stream = await SoundStreamClassifier.create(sampleRate: 16000);
      final results = stream.results.toList();
      host.sampleError = PlatformException(code: 'invalid_argument');
      final rejected = stream.add(Float32List(1));
      final accepted = stream.add(Float32List.fromList([0.25]));
      await expectLater(rejected, throwsA(isA<SoundAnalysisException>()));
      await accepted;
      await stream.close();
      expect(await results, hasLength(1));
      expect(host.samples, hasLength(1));
    },
  );

  test('cancelling one analysis preserves the other callback route', () async {
    final a = SoundAnalyzer.classifyFile('/a').listen((_) => fail('cancelled'));
    final b = SoundAnalyzer.classifyFile('/b').toList();
    await a.cancel();
    host.result(1);
    host.result(2);
    host.complete(2);
    expect((await b).single.top!.identifier, 'speech');
    expect(host.calls.where((call) => call.startsWith('cancel:')), [
      'cancel:1',
    ]);
  });

  test(
    'invalid sample rates and channel counts never reach native code',
    () async {
      for (final rate in [double.nan, double.infinity, 0.0, -1.0, 400000.0]) {
        await expectLater(
          SoundStreamClassifier.create(sampleRate: rate),
          throwsArgumentError,
        );
      }
      for (final channels in [0, -1, 33]) {
        await expectLater(
          SoundStreamClassifier.create(
            sampleRate: 16000,
            channelCount: channels,
          ),
          throwsArgumentError,
        );
      }
      expect(host.calls, isEmpty);
    },
  );

  test(
    'availability and microphone permissions map without starting analysis',
    () async {
      expect(await SoundAnalyzer.isSupported(), isTrue);
      expect(await MicrophonePermission.status(), MicrophonePermission.denied);
      expect(await MicrophonePermission.request(), isFalse);
      expect(
        MicrophonePermission.values.map((p) => p.name),
        MicrophonePermissionMessage.values.map((p) => p.name),
      );
    },
  );

  test('missing channels and unknown errors have stable categories', () async {
    host.startError = PlatformException(code: 'channel-error');
    await expectLater(
      SoundAnalyzer.classifyFile('/x'),
      emitsError(
        isA<SoundAnalysisException>().having(
          (e) => e.code,
          'code',
          SoundAnalysisErrorCode.unsupported,
        ),
      ),
    );
    expect(
      SoundAnalysisErrorCode.fromWire('future_error'),
      SoundAnalysisErrorCode.unknown,
    );
  });
}
