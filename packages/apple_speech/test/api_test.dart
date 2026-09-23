import 'dart:async';

import 'package:apple_speech/apple_speech.dart';
import 'package:apple_speech/testing.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlatform extends AppleSpeechPlatformApi {
  bool supported = true;
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<bool> isAnalyzerSupported() async => supported;
  @override
  Future<bool> isVersion27Supported() async => supported;
}

class FakeHost extends AppleSpeechHostApi {
  late SpeechBindings bindings;
  AnalysisRequestMessage? analysis;
  RecognitionRequestMessage? recognition;
  Future<void> Function()? start;
  Future<bool> Function(int)? install;
  final cancelled = <int>[];
  int finished = 0;
  int allCancelled = 0;
  @override
  Future<void> startAnalysis(AnalysisRequestMessage request) async {
    analysis = request;
    await start?.call();
  }

  @override
  Future<void> startRecognition(RecognitionRequestMessage request) async {
    recognition = request;
    await start?.call();
  }

  @override
  Future<void> cancelRequest(int id) async {
    cancelled.add(id);
  }

  @override
  Future<void> finishRequest(int id) async {
    finished++;
    bindings.callbackHandler.onRequestDone(id, 2.5);
  }

  @override
  Future<int> cancelAll() async {
    allCancelled++;
    return 0;
  }

  @override
  Future<int> activeRequestCount() async => bindings.routedRequestCount;
  @override
  Future<bool> installAssets(int id, List<ModuleConfigMessage> modules) async =>
      await install?.call(id) ?? false;
  @override
  Future<AssetStatusMessage> assetStatus(
    List<ModuleConfigMessage> modules,
  ) async => AssetStatusMessage.installed;
  @override
  Future<List<String>> reservedLocales() async => ['en-US'];
  @override
  Future<int> maximumReservedLocales() async => 5;
  @override
  Future<bool> reserveLocale(String locale) async => true;
  @override
  Future<bool> releaseLocale(String locale) async => false;
  @override
  Future<AudioFormatMessage?> bestAvailableAudioFormat(
    List<ModuleConfigMessage> modules,
  ) async => AudioFormatMessage(
    sampleRate: 16000,
    channelCount: 1,
    commonFormat: 'pcmFormatFloat32',
    isInterleaved: false,
  );
  @override
  Future<void> endModelRetention() async {}
  @override
  Future<bool> speechTranscriberIsAvailable() async => true;
  @override
  Future<List<String>> supportedLocales(ModuleKindMessage kind) async => [
    'en-US',
    'fr-FR',
  ];
  @override
  Future<List<String>> installedLocales(ModuleKindMessage kind) async => [
    'en-US',
  ];
  @override
  Future<String?> supportedLocaleEquivalent(
    ModuleKindMessage kind,
    String locale,
  ) async => locale == 'en_US' ? 'en-US' : null;
  @override
  Future<AuthorizationStatusMessage> speechAuthorizationStatus() async =>
      AuthorizationStatusMessage.denied;
  @override
  Future<AuthorizationStatusMessage> requestSpeechAuthorization() async =>
      AuthorizationStatusMessage.authorized;
  @override
  Future<AuthorizationStatusMessage> microphoneAuthorizationStatus() async =>
      AuthorizationStatusMessage.notDetermined;
  @override
  Future<AuthorizationStatusMessage> requestMicrophoneAuthorization() async =>
      AuthorizationStatusMessage.restricted;
  @override
  Future<List<String>> recognizerSupportedLocales() async => ['en-US'];
  @override
  Future<RecognizerInfoMessage?> recognizerInfo(String? locale) async =>
      locale == 'zz'
      ? null
      : RecognizerInfoMessage(
          locale: locale ?? 'en-US',
          isAvailable: true,
          supportsOnDeviceRecognition: true,
          defaultTaskHint: TaskHintMessage.dictation,
        );
}

AnalyzerResultMessage result(int id, {bool isFinal = true}) =>
    AnalyzerResultMessage(
      requestId: id,
      moduleIndex: 0,
      rangeStart: 0.125,
      rangeEnd: 1.25,
      resultsFinalizationTime: 1.25,
      isFinal: isFinal,
      text: '😀 hello',
      segments: [
        TranscriptionSegmentMessage(
          text: 'hello',
          start: 3,
          length: 5,
          startTime: 0.125,
          endTime: 1.25,
          confidence: 0.9,
          alternatives: [],
        ),
      ],
      alternatives: ['😀 hullo'],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeHost host;
  late FakePlatform platform;
  late SpeechBindings bindings;
  late SpeechBindings original;
  setUp(() {
    original = SpeechBindings.instance;
    host = FakeHost();
    platform = FakePlatform();
    bindings = SpeechBindings(
      host: host,
      platform: platform,
      registerCallbacks: false,
    );
    host.bindings = bindings;
    SpeechBindings.instance = bindings;
  });
  tearDown(() async {
    final count = bindings.routedRequestCount;
    await Speech.cancelAll();
    SpeechBindings.instance = original;
    expect(count, 0, reason: 'Dart callback routing leaked');
  });
  Future<SpeechAnalysis> analyze() => SpeechAnalyzer.analyze(
    source: const AudioSource.file('/speech.wav'),
    modules: const [SpeechTranscriber(locale: 'en-US')],
  );

  test('platform support and authorization are separate queries', () async {
    expect(await Speech.isSupported(), isTrue);
    expect(await Speech.isAnalyzerSupported(), isTrue);
    expect(await Speech.isVersion27Supported(), isTrue);
    platform.supported = false;
    expect(await Speech.isSupported(), isFalse);
    expect(
      await SpeechRecognizer.authorizationStatus(),
      AuthorizationStatus.denied,
    );
    expect(
      await SpeechRecognizer.requestAuthorization(),
      AuthorizationStatus.authorized,
    );
    expect(
      await Speech.microphoneAuthorizationStatus(),
      AuthorizationStatus.notDetermined,
    );
    expect(
      await Speech.requestMicrophoneAuthorization(),
      AuthorizationStatus.restricted,
    );
  });
  test(
    'locale, format, inventory and recognizer queries convert values',
    () async {
      expect(await SpeechTranscriber.isAvailable(), isTrue);
      expect(await SpeechTranscriber.supportedLocales(), ['en-US', 'fr-FR']);
      expect(await DictationTranscriber.installedLocales(), ['en-US']);
      expect(
        await SpeechTranscriber.supportedLocale(equivalentTo: 'en_US'),
        'en-US',
      );
      expect(
        await DictationTranscriber.supportedLocale(equivalentTo: 'zz'),
        isNull,
      );
      expect(await SpeechRecognizer.supportedLocales(), ['en-US']);
      expect(
        (await SpeechRecognizer.info())?.defaultTaskHint,
        RecognitionTaskHint.dictation,
      );
      expect(await SpeechRecognizer.info(locale: 'zz'), isNull);
      expect(
        (await SpeechAnalyzer.bestAvailableAudioFormat([]))?.sampleRate,
        16000,
      );
      expect(await AssetInventory.status([]), AssetStatus.installed);
      expect(await AssetInventory.reservedLocales(), ['en-US']);
      expect(await AssetInventory.maximumReservedLocales(), 5);
      expect(await AssetInventory.reserve('en-US'), isTrue);
      expect(await AssetInventory.release('en-US'), isFalse);
      await SpeechAnalyzer.endModelRetention();
    },
  );
  test('custom modules and presets map to the intended native enums', () {
    const custom = SpeechTranscriber.custom(
      locale: 'en-US',
      reportingOptions: {ReportingOption.fastResults},
      attributeOptions: {ResultAttributeOption.audioTimeRange},
    );
    expect(custom.toMessage().speechPreset, isNull);
    expect(custom.toMessage().reportingOptions, [
      ReportingOptionMessage.fastResults,
    ]);
    for (final preset in SpeechTranscriberPreset.values) {
      expect(
        SpeechTranscriber(
          locale: 'en-US',
          preset: preset,
        ).toMessage().speechPreset?.name,
        preset.name,
      );
    }
    for (final preset in DictationTranscriberPreset.values) {
      expect(
        DictationTranscriber(
          locale: 'en-US',
          preset: preset,
        ).toMessage().dictationPreset?.name,
        preset.name,
      );
    }
    const dictation = DictationTranscriber.custom(
      locale: 'en-US',
      contentHints: {DictationContentHint.atypicalSpeech},
      transcriptionOptions: {TranscriptionOption.emoji},
    );
    expect(dictation.toMessage().contentHints, [
      ContentHintMessage.atypicalSpeech,
    ]);
    expect(dictation.toMessage().transcriptionOptions, [
      TranscriptionOptionMessage.emoji,
    ]);
    expect(
      const SpeechDetector(
        sensitivity: SpeechDetectorSensitivity.high,
        reportResults: false,
      ).toMessage().reportResults,
      isFalse,
    );
  });
  test('analyzer snapshots context and maps source and options', () async {
    final strings = ['Codex'];
    final requestFuture = SpeechAnalyzer.analyze(
      source: const AudioSource.microphone(configureAudioSession: false),
      modules: const [SpeechTranscriber(locale: 'en-US')],
      contextualStrings: {'general': strings},
      options: const AnalyzerOptions(
        priority: AnalysisPriority.utility,
        modelRetention: ModelRetention.lingering,
        ignoresResourceLimits: true,
      ),
    );
    strings.add('later');
    final request = await requestFuture;
    expect(host.analysis?.source, AudioSourceKindMessage.microphone);
    expect(host.analysis?.configureAudioSession, isFalse);
    expect(host.analysis?.contextualStrings, {
      'general': ['Codex'],
    });
    expect(
      host.analysis?.options?.modelRetention,
      ModelRetentionMessage.lingering,
    );
    expect(host.analysis?.options?.priority, TaskPriorityMessage.utility);
    expect(host.analysis?.options?.ignoresResourceLimits, isTrue);
    await request.cancel();
  });
  test(
    'callbacks before startup returns are buffered, converted and closed',
    () async {
      host.start = () async {
        final id = host.analysis!.requestId;
        bindings.callbackHandler.onAnalyzerResult(result(id));
        bindings.callbackHandler.onRequestDone(id, 1.25);
      };
      final request = await analyze();
      final events = await request.results.toList();
      expect(
        events.single.segments.single.range.of(events.single.text!),
        'hello',
      );
      expect(
        events.single.segments.single.duration,
        const Duration(milliseconds: 1125),
      );
      expect(events.single.rangeStart, const Duration(milliseconds: 125));
      expect(events.single.segments.single.confidence, 0.9);
      expect(request.lastSampleTime, const Duration(milliseconds: 1250));
      expect(() => events.single.alternatives.add('x'), throwsUnsupportedError);
      await request.done;
      expect(host.cancelled, isEmpty);
    },
  );
  test(
    'events are isolated by request ID and unknown IDs are ignored',
    () async {
      final first = await analyze();
      final second = await analyze();
      bindings.callbackHandler.onAnalyzerResult(result(second.requestId));
      bindings.callbackHandler.onAnalyzerResult(result(9999));
      bindings.callbackHandler.onRequestDone(first.requestId, null);
      bindings.callbackHandler.onRequestDone(second.requestId, null);
      expect(await first.results.toList(), isEmpty);
      expect(await second.results.toList(), hasLength(1));
    },
  );
  test('startup platform failure is typed and unregisters routing', () async {
    host.start = () async => throw PlatformException(code: 'channel-error');
    await expectLater(
      analyze(),
      throwsA(
        isA<SpeechException>().having(
          (e) => e.code,
          'code',
          SpeechErrorCode.unsupported,
        ),
      ),
    );
  });
  test(
    'terminal callback followed by startup failure does not double complete',
    () async {
      host.start = () async {
        bindings.callbackHandler.onRequestDone(host.analysis!.requestId, null);
        throw PlatformException(code: 'invalid_argument', message: 'bad');
      };
      await expectLater(analyze(), throwsA(isA<SpeechException>()));
    },
  );
  test(
    'callback errors reach the stream and done with native details',
    () async {
      final request = await analyze();
      final streamError = expectLater(
        request.results,
        emitsError(
          isA<SpeechException>().having((e) => e.nativeCode, 'nativeCode', 3),
        ),
      );
      final doneError = expectLater(
        request.done,
        throwsA(
          isA<SpeechException>().having(
            (e) => e.domain,
            'domain',
            'SFSpeechErrorDomain',
          ),
        ),
      );
      bindings.callbackHandler.onRequestError(
        request.requestId,
        ErrorMessage(
          code: 'audio_format',
          message: 'bad',
          details: '{"domain":"SFSpeechErrorDomain","nativeCode":3}',
        ),
      );
      await streamError;
      await doneError;
      bindings.callbackHandler.onRequestDone(request.requestId, null);
    },
  );
  test('cancel is idempotent and drops late callbacks', () async {
    final request = await analyze();
    await Future.wait([request.cancel(), request.cancel()]);
    bindings.callbackHandler.onAnalyzerResult(result(request.requestId));
    expect(await request.results.toList(), isEmpty);
    await request.done;
    expect(host.cancelled, [request.requestId]);
  });
  test('subscription cancellation releases native work', () async {
    final request = await analyze();
    await request.results.listen((_) {}).cancel();
    expect(host.cancelled, [request.requestId]);
    await request.done;
  });
  test(
    'cancel-all waits for pending startup before native cancellation',
    () async {
      final ready = Completer<void>();
      host.start = () => ready.future;
      final starting = analyze();
      final cancelling = Speech.cancelAll();
      await Future<void>.delayed(Duration.zero);
      expect(host.cancelled, isEmpty);
      ready.complete();
      final request = await starting;
      expect(await cancelling, 1);
      expect(host.cancelled, [request.requestId]);
      expect(request.isActive, isFalse);
      await request.done;
    },
  );
  test('finish waits for finalization and records last sample time', () async {
    final request = await analyze();
    await request.finish();
    expect(host.finished, 1);
    expect(request.lastSampleTime, const Duration(milliseconds: 2500));
    expect(await request.results.toList(), isEmpty);
  });
  test(
    'recognition forwards options and converts hypotheses and metadata',
    () async {
      host.start = () async {
        final text = TranscriptionMessage(
          formattedString: 'hello',
          segments: [],
        );
        final id = host.recognition!.requestId;
        bindings.callbackHandler.onRecognitionResult(
          RecognitionResultMessage(
            requestId: id,
            bestTranscription: text,
            transcriptions: [text],
            isFinal: true,
            metadata: RecognitionMetadataMessage(
              speakingRate: 120,
              averagePauseDuration: 0.25,
              speechStartTimestamp: 0.5,
              speechDuration: 2,
            ),
          ),
        );
        bindings.callbackHandler.onRequestDone(id, null);
      };
      final request = await SpeechRecognizer.recognize(
        source: const AudioSource.file('/test.wav'),
        locale: 'en-US',
        requiresOnDeviceRecognition: true,
        taskHint: RecognitionTaskHint.search,
        contextualStrings: ['hello'],
        addsPunctuation: true,
        shouldReportPartialResults: false,
      );
      final event = (await request.results.toList()).single;
      expect(event.bestTranscription.formattedString, 'hello');
      expect(
        event.metadata?.averagePauseDuration,
        const Duration(milliseconds: 250),
      );
      expect(event.metadata?.speechDuration, const Duration(seconds: 2));
      expect(host.recognition?.requiresOnDeviceRecognition, isTrue);
      expect(host.recognition?.taskHint, TaskHintMessage.search);
      expect(host.recognition?.shouldReportPartialResults, isFalse);
      expect(host.recognition?.addsPunctuation, isTrue);
    },
  );
  test(
    'asset installation routes progress before awaiting completion',
    () async {
      final progress = <double>[];
      host.install = (id) async {
        bindings.callbackHandler.onInstallProgress(id, 0.25);
        bindings.callbackHandler.onInstallProgress(id, 1);
        return true;
      };
      expect(
        await AssetInventory.installAssets([], onProgress: progress.add),
        isTrue,
      );
      expect(progress, [0.25, 1]);
    },
  );
  test('asset installation no-op and failure release callbacks', () async {
    expect(await AssetInventory.installAssets([]), isFalse);
    host.install = (_) async => throw PlatformException(code: 'cancelled');
    await expectLater(
      AssetInventory.installAssets([]),
      throwsA(
        isA<SpeechException>().having(
          (e) => e.code,
          'code',
          SpeechErrorCode.cancelled,
        ),
      ),
    );
  });
  test('unknown and malformed native errors retain debug information', () {
    final error = SpeechException.fromPlatformException(
      PlatformException(code: 'future_error', details: '{broken'),
    );
    expect(error.code, SpeechErrorCode.unknown);
    expect(error.details['debug'], '{broken');
    expect(error.toString(), contains('unknown'));
  });
}
