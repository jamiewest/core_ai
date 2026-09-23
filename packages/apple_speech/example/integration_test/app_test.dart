import 'package:apple_speech/apple_speech.dart';
import 'package:apple_speech_example/fixtures.dart';
import 'package:apple_speech_example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() async {
    final count = await Speech.activeRequestCount();
    await Speech.cancelAll();
    expect(count, 0);
  });
  Future<void> waitFor(WidgetTester tester, bool Function() done) async {
    for (var tick = 0; tick < 900 && !done(); tick++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(done(), isTrue, reason: 'Timed out waiting for transcription');
  }

  testWidgets('example transcribes bundled speech and displays word timing', (
    tester,
  ) async {
    final previous = WidgetController.hitTestWarningShouldBeFatal;
    WidgetController.hitTestWarningShouldBeFatal = true;
    addTearDown(() => WidgetController.hitTestWarningShouldBeFatal = previous);
    await tester.pumpWidget(const SpeechExampleApp());
    final button = find.byKey(const ValueKey('sample'));
    await waitFor(tester, () => button.evaluate().isNotEmpty);
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();
    await waitFor(
      tester,
      () => find.text('Transcription complete.').evaluate().isNotEmpty,
    );
    expect(find.byKey(const ValueKey('speech-error')), findsNothing);
    final transcript = tester
        .widget<SelectableText>(find.byKey(const ValueKey('transcript')))
        .data!;
    String words(String text) => text
        .toLowerCase()
        .replaceAll(RegExp('[^a-z ]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    expect(words(transcript), words(SpeechFixture.transcript));
    expect(find.text('Word timing and confidence'), findsOneWidget);
    expect(await Speech.activeRequestCount(), 0);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
