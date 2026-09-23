import 'package:apple_speech/testing.dart';
import 'package:apple_speech_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class Platform extends AppleSpeechPlatformApi {
  bool supported = true;
  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<bool> isAnalyzerSupported() async => supported;
  @override
  Future<bool> isVersion27Supported() async => supported;
}

class Host extends AppleSpeechHostApi {
  bool installed = true;
  int permissions = 0;
  int installations = 0;
  int starts = 0;
  late SpeechBindings bindings;
  @override
  Future<bool> speechTranscriberIsAvailable() async => true;
  @override
  Future<List<String>> installedLocales(ModuleKindMessage kind) async =>
      installed ? ['en-US'] : [];
  @override
  Future<bool> installAssets(int id, List<ModuleConfigMessage> modules) async {
    installations++;
    installed = true;
    bindings.callbackHandler.onInstallProgress(id, 1);
    return true;
  }

  @override
  Future<void> startAnalysis(AnalysisRequestMessage request) async {
    starts++;
    bindings.callbackHandler.onAnalyzerResult(
      AnalyzerResultMessage(
        requestId: request.requestId,
        moduleIndex: 0,
        rangeStart: 0,
        rangeEnd: 1,
        resultsFinalizationTime: 1,
        isFinal: true,
        text: 'A clear transcript.',
        segments: [],
        alternatives: [],
      ),
    );
    bindings.callbackHandler.onRequestDone(request.requestId, 1);
  }

  @override
  Future<AuthorizationStatusMessage> requestMicrophoneAuthorization() async {
    permissions++;
    return AuthorizationStatusMessage.denied;
  }
}

void main() {
  late SpeechBindings original;
  late Platform platform;
  late Host host;
  setUp(() {
    original = SpeechBindings.instance;
    platform = Platform();
    host = Host();
    final bindings = SpeechBindings(
      host: host,
      platform: platform,
      registerCallbacks: false,
    );
    host.bindings = bindings;
    SpeechBindings.instance = bindings;
  });
  tearDown(() {
    expect(host.bindings.routedRequestCount, 0);
    SpeechBindings.instance = original;
  });
  Future<void> show(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SpeechExampleApp(samplePath: '/sample.wav'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key));
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('unsupported platform shows a notice and no recording controls', (
    tester,
  ) async {
    platform.supported = false;
    await show(tester);
    expect(
      find.text('Speech is unavailable on this platform.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('listen')), findsNothing);
    expect(host.permissions, 0);
  });
  testWidgets('missing models disable transcription until explicit download', (
    tester,
  ) async {
    host.installed = false;
    await show(tester);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sample')))
          .onPressed,
      isNull,
    );
    expect(host.installations, 0);
    await tap(tester, 'install');
    expect(host.installations, 1);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sample')))
          .onPressed,
      isNotNull,
    );
    expect(host.permissions, 0);
  });
  testWidgets('sample renders the real API result without asking permission', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'sample');
    expect(find.text('Transcription complete.'), findsOneWidget);
    expect(find.text('A clear transcript.'), findsOneWidget);
    expect(host.starts, 1);
    expect(host.permissions, 0);
    expect(tester.takeException(), isNull);
  });
  testWidgets('microphone denial displays an error without starting capture', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'listen');
    expect(host.permissions, 1);
    expect(host.starts, 0);
    expect(
      find.textContaining('Microphone permission was not granted'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
