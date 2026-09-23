import 'package:apple_translation/testing.dart';
import 'package:apple_translation_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Platform implements AppleTranslationPlatformApi {
  bool supported = true;
  bool sessions = true;

  @override
  Future<bool> isSupported() async => supported;
  @override
  Future<bool> isInstalledSessionSupported() async => sessions;
  @override
  Future<bool> isStrategySupported() async => false;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Host implements AppleTranslationHostApi {
  LanguageStatusMessage pairStatus = LanguageStatusMessage.supported;

  @override
  Future<List<LanguageMessage>> supportedLanguages(StrategyMessage? _) async =>
      [
        LanguageMessage(
          minimalIdentifier: 'en',
          maximalIdentifier: 'en-Latn-US',
          localizedName: 'English',
        ),
        LanguageMessage(
          minimalIdentifier: 'es',
          maximalIdentifier: 'es-Latn-ES',
          localizedName: 'Spanish',
        ),
      ];
  @override
  Future<LanguageStatusMessage> status(
    String source,
    String? target,
    StrategyMessage? strategy,
  ) async => pairStatus;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TranslationBindings previous;
  late _Platform platform;
  late _Host host;

  setUp(() {
    previous = TranslationBindings.instance;
    platform = _Platform();
    host = _Host();
    TranslationBindings.instance = TranslationBindings(
      platform: platform,
      host: host,
      registerCallbacks: false,
    );
  });
  tearDown(() => TranslationBindings.instance = previous);

  testWidgets('explains an unsupported platform', (tester) async {
    platform.supported = false;
    platform.sessions = false;
    await tester.pumpWidget(const TranslationExampleApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('requires iOS 18 or macOS 15'), findsOneWidget);
    expect(find.byKey(const ValueKey('translate')), findsNothing);
  });

  testWidgets('older systems can check languages but cannot translate', (
    tester,
  ) async {
    platform.sessions = false;
    host.pairStatus = LanguageStatusMessage.installed;
    await tester.pumpWidget(const TranslationExampleApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('requires iOS 26 or macOS 26'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('translate')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('missing packs can be rechecked on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const TranslationExampleApp());
    await tester.pumpAndSettle();
    final translate = find.byKey(const ValueKey('translate'));
    expect(find.textContaining('Download these languages'), findsOneWidget);
    expect(tester.widget<FilledButton>(translate).onPressed, isNull);

    host.pairStatus = LanguageStatusMessage.installed;
    final refresh = find.text('Check language packs');
    await tester.ensureVisible(refresh);
    await tester.tap(refresh);
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(translate).onPressed, isNotNull);

    final input = find.byKey(const ValueKey('source-text'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '   ');
    await tester.pump();
    expect(tester.widget<FilledButton>(translate).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unsupported pairs cannot start translation', (tester) async {
    host.pairStatus = LanguageStatusMessage.unsupported;
    await tester.pumpWidget(const TranslationExampleApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('pair is not supported'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('translate')))
          .onPressed,
      isNull,
    );
  });
}
