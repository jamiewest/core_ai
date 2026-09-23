import 'dart:io';
import 'dart:typed_data';

import 'package:apple_sound_analysis/apple_sound_analysis.dart';
import 'package:apple_sound_analysis/testing.dart';
import 'package:apple_sound_analysis_example/fixtures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Matcher soundError(SoundAnalysisErrorCode code) =>
    isA<SoundAnalysisException>().having((error) => error.code, 'code', code);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late SoundFixtures fixtures;
  setUpAll(() async {
    expect(await SoundAnalyzer.isSupported(), isTrue);
    await SoundAnalyzer.cancelAll();
    fixtures = await SoundFixtures.load();
  });
  tearDownAll(() async {
    await SoundAnalyzer.cancelAll();
    await fixtures.dispose();
  });
  tearDown(() async {
    expect(SoundAnalysisBindings.instance.analyses, isEmpty);
    expect(
      await SoundAnalyzer.cancelAll(),
      0,
      reason: 'native analysis leaked',
    );
  });

  test('built-in labels, defaults and constraints', () async {
    final info = await const SoundClassifier.builtIn().info();
    expect(info.knownClassifications.length, 303);
    expect(
      info.knownClassifications,
      containsAll(['speech', 'whistling', 'beep']),
    );
    expect(info.windowDurationSeconds, 3);
    expect(info.overlapFactor, 0.5);
    expect(info.minimumWindowSeconds, 0.5);
    expect(info.maximumWindowSeconds, closeTo(15, 0.001));
    expect(info.allowedWindowDurationsSeconds, isEmpty);
  });

  test('built-in classifier detects speech with ordered windows', () async {
    final results = await SoundAnalyzer.classifyFile(
      fixtures.speech,
      maximumClassifications: 3,
    ).toList();
    expect(results.length, greaterThanOrEqualTo(2));
    expect(results.first.top!.identifier, 'speech');
    expect(results.first.top!.confidence, greaterThan(0.7));
    expect(results.first.startSeconds, 0);
    expect(results.first.durationSeconds, 3);
    expect(results[1].startSeconds, closeTo(1.5, 0.001));
    for (final result in results) {
      expect(result.classifications, hasLength(3));
      final scores = result.classifications.map((c) => c.confidence).toList();
      expect(scores, [...scores]..sort((a, b) => b.compareTo(a)));
    }
  });

  test(
    'custom model classifies both files and exposes its default window',
    () async {
      final classifier = SoundClassifier.model(fixtures.model);
      final info = await classifier.info();
      expect(info.knownClassifications, unorderedEquals(['speech', 'tone']));
      expect(info.windowDurationSeconds, closeTo(0.975, 0.001));
      for (final entry in {
        'speech': fixtures.speech,
        'tone': fixtures.tone,
      }.entries) {
        final results = await SoundAnalyzer.classifyFile(
          entry.value,
          classifier: classifier,
          maximumClassifications: 1,
        ).toList();
        expect(results, isNotEmpty);
        expect(results.first.top!.identifier, entry.key);
        expect(results.first.top!.confidence, greaterThan(0.95));
      }
    },
  );

  test('PCM chunks match the custom tone classifier', () async {
    final samples = decodeFixtureWav(await File(fixtures.tone).readAsBytes());
    final stream = await SoundStreamClassifier.create(
      sampleRate: 16000,
      classifier: SoundClassifier.model(fixtures.model),
      maximumClassifications: 1,
    );
    final results = stream.results.toList();
    try {
      for (var offset = 0; offset < samples.length; offset += 4096) {
        final end = (offset + 4096).clamp(0, samples.length);
        await stream.add(Float32List.sublistView(samples, offset, end));
      }
      await stream.close();
      final windows = await results;
      expect(windows, isNotEmpty);
      expect(windows.first.top!.identifier, 'tone');
      expect(windows.first.top!.confidence, greaterThan(0.95));
      expect(windows.first.startSeconds, 0);
    } finally {
      await stream.cancel();
    }
  });

  test('window and overlap overrides work', () async {
    final info = await const SoundClassifier.builtIn(
      windowDurationSeconds: 1,
      overlapFactor: 0.25,
    ).info();
    expect(info.windowDurationSeconds, 1);
    expect(info.overlapFactor, 0.25);
  });

  test('stereo PCM is deinterleaved and classified', () async {
    final mono = decodeFixtureWav(await File(fixtures.tone).readAsBytes());
    final stereo = Float32List.fromList([
      for (final sample in mono) ...[sample, sample],
    ]);
    final stream = await SoundStreamClassifier.create(
      sampleRate: 16000,
      channelCount: 2,
      classifier: SoundClassifier.model(fixtures.model),
    );
    final results = stream.results.toList();
    try {
      await stream.add(stereo);
      await stream.close();
      expect((await results).first.top!.identifier, 'tone');
    } finally {
      await stream.cancel();
    }
  });

  test('taking one file result cancels native file work', () async {
    final results = await SoundAnalyzer.classifyFile(
      fixtures.speech,
    ).take(1).toList();
    expect(results.single.top!.identifier, 'speech');
  });

  test(
    'native PCM validation rejects unsafe formats and malformed buffers',
    () async {
      final host = SoundAnalysisBindings.instance.host;
      final invalid = throwsA(
        isA<PlatformException>().having(
          (error) => error.code,
          'code',
          'invalid_argument',
        ),
      );
      for (final format in [
        AudioFormatMessage(sampleRate: double.infinity, channelCount: 1),
        AudioFormatMessage(sampleRate: 16000, channelCount: 1 << 40),
        AudioFormatMessage(sampleRate: -1, channelCount: 1),
      ]) {
        await expectLater(
          host.startStreamAnalysis(
            9000,
            format,
            ClassifierConfigMessage(),
            null,
          ),
          invalid,
        );
      }
      final stream = await SoundStreamClassifier.create(sampleRate: 16000);
      try {
        final id = SoundAnalysisBindings.instance.analyses.keys.single;
        await expectLater(host.analyzeSamples(id, Uint8List(3)), invalid);
        final nan = ByteData(4)..setFloat32(0, double.nan, Endian.little);
        await expectLater(
          host.analyzeSamples(id, nan.buffer.asUint8List()),
          invalid,
        );
      } finally {
        await stream.cancel();
      }
    },
  );

  test('invalid windows and overlaps throw rather than trap in ObjC', () async {
    for (final window in [0.0, -1.0, 0.1, 20.0, double.nan, double.infinity]) {
      await expectLater(
        SoundClassifier.builtIn(windowDurationSeconds: window).info(),
        throwsA(soundError(SoundAnalysisErrorCode.invalidArgument)),
      );
    }
    for (final overlap in [-0.1, 1.0, double.nan, double.infinity]) {
      await expectLater(
        SoundClassifier.builtIn(overlapFactor: overlap).info(),
        throwsA(soundError(SoundAnalysisErrorCode.invalidArgument)),
      );
    }
    final custom = await SoundClassifier.model(fixtures.model).info();
    final invalidWindow =
        (custom.maximumWindowSeconds ??
            custom.allowedWindowDurationsSeconds.reduce(
              (a, b) => a > b ? a : b,
            )) +
        1;
    await expectLater(
      SoundClassifier.model(
        fixtures.model,
        windowDurationSeconds: invalidWindow,
      ).info(),
      throwsA(soundError(SoundAnalysisErrorCode.invalidArgument)),
    );
  });

  test('missing and non-audio files return invalid_file', () async {
    for (final path in ['/nonexistent/sound.wav', fixtures.model]) {
      await expectLater(
        SoundAnalyzer.classifyFile(path),
        emitsInOrder([
          emitsError(soundError(SoundAnalysisErrorCode.invalidFile)),
          emitsDone,
        ]),
      );
    }
  });

  test('missing model and invalid result limits report errors', () async {
    await expectLater(
      const SoundClassifier.model('/nonexistent/model.mlmodel').info(),
      throwsA(soundError(SoundAnalysisErrorCode.notFound)),
    );
    await expectLater(
      SoundAnalyzer.classifyFile(fixtures.speech, maximumClassifications: 0),
      emitsInOrder([
        emitsError(soundError(SoundAnalysisErrorCode.invalidArgument)),
        emitsDone,
      ]),
    );
  });

  test(
    'duplicate request IDs leave the existing native analyzer intact',
    () async {
      final stream = await SoundStreamClassifier.create(
        sampleRate: 16000,
        classifier: SoundClassifier.model(fixtures.model),
      );
      final results = stream.results.toList();
      try {
        final bindings = SoundAnalysisBindings.instance;
        final id = bindings.analyses.keys.single;
        await expectLater(
          bindings.host.startStreamAnalysis(
            id,
            AudioFormatMessage(sampleRate: 16000, channelCount: 1),
            ClassifierConfigMessage(),
            null,
          ),
          throwsA(
            isA<PlatformException>().having(
              (e) => e.code,
              'code',
              'invalid_argument',
            ),
          ),
        );
        await stream.add(
          decodeFixtureWav(await File(fixtures.tone).readAsBytes()),
        );
        await stream.close();
        expect((await results).first.top!.identifier, 'tone');
      } finally {
        await stream.cancel();
      }
    },
  );

  test('cancelling input and cancelAll release native analyzers', () async {
    final a = await SoundStreamClassifier.create(sampleRate: 16000);
    final b = await SoundStreamClassifier.create(sampleRate: 16000);
    final aResults = a.results.toList();
    final bResults = b.results.toList();
    expect(await SoundAnalyzer.cancelAll(), 2);
    expect(await aResults, isEmpty);
    expect(await bResults, isEmpty);
    expect(() => a.add(Float32List(1)), throwsStateError);
    await a.cancel();
    await b.cancel();
  });

  test(
    'microphone authorization is read without requesting permission',
    () async {
      final permission = await MicrophonePermission.status();
      expect(permission, isIn(MicrophonePermission.values));
      if (permission != MicrophonePermission.authorized) {
        await expectLater(
          SoundAnalyzer.classifyMicrophone(),
          emitsInOrder([
            emitsError(soundError(SoundAnalysisErrorCode.permissionDenied)),
            emitsDone,
          ]),
        );
      }
    },
  );
}
