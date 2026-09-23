import 'dart:io';

import 'package:apple_speech/apple_speech.dart';
import 'package:apple_speech/testing.dart';
import 'package:apple_speech_example/fixtures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late SpeechFixture fixture;
  const transcriber = SpeechTranscriber.custom(
    locale: 'en-US',
    attributeOptions: {
      ResultAttributeOption.audioTimeRange,
      ResultAttributeOption.transcriptionConfidence,
    },
  );
  setUpAll(() async {
    fixture = await SpeechFixture.load();
    expect(await Speech.isAnalyzerSupported(), isTrue);
    expect(await SpeechTranscriber.isAvailable(), isTrue);
    expect(
      await SpeechTranscriber.installedLocales(),
      contains('en-US'),
      reason:
          'Install English speech assets manually before running this suite.',
    );
  });
  tearDownAll(() async {
    await SpeechAnalyzer.endModelRetention();
    await fixture.dispose();
  });
  tearDown(() async {
    final count = await Speech.activeRequestCount();
    await Speech.cancelAll();
    expect(count, 0, reason: 'native request leaked');
    expect(SpeechBindings.instance.routedRequestCount, 0);
  });

  String words(String text) => text
      .toLowerCase()
      .replaceAll(RegExp('[^a-z ]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  Future<List<AnalysisResult>> analyze(
    AudioSource source, {
    List<SpeechModule> modules = const [transcriber],
  }) async {
    final request = await SpeechAnalyzer.analyze(
      source: source,
      modules: modules,
    );
    try {
      final results = await request.results.toList().timeout(
        const Duration(seconds: 90),
      );
      await request.done;
      expect(request.isActive, isFalse);
      expect(results.where((r) => r.isFinal && r.text != null), isNotEmpty);
      final text = results
          .where((r) => r.isFinal && r.moduleIndex == 0)
          .map((r) => r.text ?? '')
          .join(' ');
      expect(words(text), words(SpeechFixture.transcript));
      return results;
    } finally {
      await request.cancel();
    }
  }

  Matcher code(SpeechErrorCode code) =>
      isA<SpeechException>().having((e) => e.code, 'code', code);

  testWidgets('support, locale equivalence, assets and audio format', (
    _,
  ) async {
    expect(await Speech.isSupported(), isTrue);
    expect(await SpeechRecognizer.supportedLocales(), contains('en-US'));
    final info = await SpeechRecognizer.info(locale: 'en-US');
    expect(info?.locale, 'en-US');
    expect(await SpeechTranscriber.supportedLocales(), contains('en-US'));
    expect(
      await SpeechTranscriber.supportedLocale(equivalentTo: 'en_US'),
      'en-US',
    );
    // Apple's status can be `supported` even for an installed model. The
    // setup and concrete transcription checks independently verify usability.
    expect(
      await AssetInventory.status([transcriber]),
      anyOf(AssetStatus.installed, AssetStatus.supported),
    );
    expect(await AssetInventory.maximumReservedLocales(), greaterThan(0));
    expect(await AssetInventory.reservedLocales(), isA<List<String>>());
    final format = await SpeechAnalyzer.bestAvailableAudioFormat([transcriber]);
    expect(format?.sampleRate, greaterThan(0));
    expect(format?.channelCount, greaterThan(0));
  });
  testWidgets(
    'file transcription has exact words, UTF16 ranges, timing and confidence',
    (_) async {
      final results = await analyze(AudioSource.file(fixture.path));
      final segments = results
          .where((r) => r.isFinal)
          .expand((r) => r.segments)
          .toList();
      expect(segments.length, greaterThan(15));
      for (final result in results.where((r) => r.isFinal)) {
        expect(result.rangeEnd, greaterThan(result.rangeStart));
        for (final segment in result.segments) {
          expect(segment.range.of(result.text!), segment.text);
          expect(segment.startTime, isNotNull);
          expect(segment.endTime, greaterThanOrEqualTo(segment.startTime!));
          expect(segment.confidence, inInclusiveRange(0, 1));
        }
      }
    },
  );
  testWidgets(
    'progressive simulated microphone yields the complete transcript',
    (_) async {
      final results = await analyze(
        AudioSource.simulatedMicrophone(fixture.path),
        modules: const [
          SpeechTranscriber(
            locale: 'en-US',
            preset: SpeechTranscriberPreset.timeIndexedProgressiveTranscription,
          ),
        ],
      );
      expect(results.any((r) => !r.isFinal), isTrue);
    },
  );
  testWidgets('media asset input on version 27', (_) async {
    expect(await Speech.isVersion27Supported(), isTrue);
    await analyze(AudioSource.asset(fixture.path));
  });
  testWidgets('dictation transcribes installed English', (_) async {
    expect(await DictationTranscriber.installedLocales(), contains('en-US'));
    await analyze(
      AudioSource.file(fixture.path),
      modules: const [
        DictationTranscriber(
          locale: 'en-US',
          preset: DictationTranscriberPreset.timeIndexedLongDictation,
        ),
      ],
    );
  });
  testWidgets('detector can accompany a transcriber', (_) async {
    await analyze(
      AudioSource.file(fixture.path),
      modules: const [transcriber, SpeechDetector()],
    );
  });
  testWidgets(
    'empty modules and detector alone are rejected before framework traps',
    (_) async {
      for (final modules in <List<SpeechModule>>[
        [],
        [const SpeechDetector()],
      ]) {
        await expectLater(
          SpeechAnalyzer.analyze(
            source: AudioSource.file(fixture.path),
            modules: modules,
          ),
          throwsA(code(SpeechErrorCode.invalidArgument)),
        );
      }
    },
  );
  testWidgets('unsupported locale and invalid custom options are typed', (
    _,
  ) async {
    await expectLater(
      SpeechAnalyzer.analyze(
        source: AudioSource.file(fixture.path),
        modules: const [SpeechTranscriber(locale: 'zz-ZZ')],
      ),
      throwsA(code(SpeechErrorCode.unsupportedLocale)),
    );
    await expectLater(
      SpeechAnalyzer.analyze(
        source: AudioSource.file(fixture.path),
        modules: const [
          SpeechTranscriber.custom(
            locale: 'en-US',
            transcriptionOptions: {TranscriptionOption.punctuation},
          ),
        ],
      ),
      throwsA(code(SpeechErrorCode.invalidArgument)),
    );
  });
  testWidgets('missing and malformed files report errors and clean up', (
    _,
  ) async {
    await expectLater(
      SpeechAnalyzer.analyze(
        source: const AudioSource.file('/missing/speech.wav'),
        modules: const [transcriber],
      ),
      throwsA(code(SpeechErrorCode.notFound)),
    );
    final invalid = File('${fixture.directory.path}/invalid.wav');
    await invalid.writeAsString('not audio');
    await expectLater(
      SpeechAnalyzer.analyze(
        source: AudioSource.file(invalid.path),
        modules: const [transcriber],
      ),
      throwsA(isA<SpeechException>()),
    );
  });
  testWidgets('cancel and subscription cancel remove active requests', (
    _,
  ) async {
    final first = await SpeechAnalyzer.analyze(
      source: AudioSource.simulatedMicrophone(fixture.path),
      modules: const [transcriber],
    );
    expect(await Speech.activeRequestCount(), 1);
    await first.cancel();
    await first.cancel();
    await first.done;
    expect(await first.results.toList(), isEmpty);
    final second = await SpeechAnalyzer.analyze(
      source: AudioSource.simulatedMicrophone(fixture.path),
      modules: const [transcriber],
    );
    final subscription = second.results.listen((_) {});
    await subscription.cancel();
    await second.done;
  });
  testWidgets('cancel-all closes a live input stream', (_) async {
    final request = await SpeechAnalyzer.analyze(
      source: AudioSource.simulatedMicrophone(fixture.path),
      modules: const [transcriber],
    );
    expect(await Speech.cancelAll(), 1);
    await request.done;
    await request.results.drain<void>();
  });
  testWidgets('finish finalizes simulated live input and releases it', (
    _,
  ) async {
    final request = await SpeechAnalyzer.analyze(
      source: AudioSource.simulatedMicrophone(fixture.path),
      modules: const [transcriber],
    );
    final results = request.results.toList();
    await Future<void>.delayed(const Duration(seconds: 2));
    await request.finish().timeout(const Duration(seconds: 30));
    expect(await results, isNotEmpty);
    expect(request.isActive, isFalse);
  });
  testWidgets('duplicate native IDs leave the original analysis cancellable', (
    _,
  ) async {
    final request = await SpeechAnalyzer.analyze(
      source: AudioSource.simulatedMicrophone(fixture.path),
      modules: const [transcriber],
    );
    try {
      await expectLater(
        SpeechBindings.instance.host.startAnalysis(
          AnalysisRequestMessage(
            requestId: request.requestId,
            source: AudioSourceKindMessage.file,
            path: fixture.path,
            modules: [transcriber.toMessage()],
            contextualStrings: {},
            configureAudioSession: false,
          ),
        ),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'invalid_argument',
          ),
        ),
      );
      expect(await Speech.activeRequestCount(), 1);
    } finally {
      await request.cancel();
    }
  });
  testWidgets('legacy authorization denial is explicit and never prompts', (
    _,
  ) async {
    final status = await SpeechRecognizer.authorizationStatus();
    expect(
      await Speech.microphoneAuthorizationStatus(),
      isA<AuthorizationStatus>(),
    );
    if (status != AuthorizationStatus.authorized) {
      await expectLater(
        SpeechRecognizer.recognize(
          source: AudioSource.file(fixture.path),
          locale: 'en-US',
          requiresOnDeviceRecognition: true,
        ),
        throwsA(code(SpeechErrorCode.notAuthorized)),
      );
    } else {
      final request = await SpeechRecognizer.recognize(
        source: AudioSource.file(fixture.path),
        locale: 'en-US',
        requiresOnDeviceRecognition: true,
      );
      try {
        final results = await request.results.toList().timeout(
          const Duration(seconds: 90),
        );
        expect(results.last.isFinal, isTrue);
        expect(
          words(results.last.bestTranscription.formattedString),
          words(SpeechFixture.transcript),
        );
      } finally {
        await request.cancel();
      }
    }
  });
}
